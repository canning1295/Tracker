import AuthenticationServices
import Foundation
import UIKit

struct StravaCredentials: Codable, Equatable {
    var clientID: String
    var clientSecret: String

    var isComplete: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct StravaStoredToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scope: String?
    var athleteID: Int?

    var needsRefresh: Bool {
        expiresAt <= Date().addingTimeInterval(90)
    }

    var grantedScopes: Set<String> {
        guard let scope else { return [] }
        return Set(scope.split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }.map(String.init))
    }
}

struct StravaUploadResult: Equatable {
    var uploadID: String
    var activityID: String?
    var status: String?
}

enum StravaAuthorizationResult: Equatable {
    case connected
    case openedStravaApp
}

@MainActor
final class StravaClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let redirectURI = "tracker://localhost/strava"
    static let requiredScopes: Set<String> = ["activity:write"]

    private let callbackScheme = "tracker"
    private let keychain = KeychainStore(service: "Tracker.Strava")
    private var authSession: ASWebAuthenticationSession?

    private enum Account {
        static let credentials = "credentials"
        static let token = "token"
    }

    func storedCredentials() -> StravaCredentials {
        guard let data = keychain.data(for: Account.credentials),
              let credentials = try? JSONDecoder().decode(StravaCredentials.self, from: data) else {
            return StravaCredentials(clientID: "", clientSecret: "")
        }
        return credentials
    }

    func saveCredentials(clientID: String, clientSecret: String) throws {
        let credentials = StravaCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let data = try JSONEncoder().encode(credentials)
        try keychain.set(data, for: Account.credentials)
    }

    func hasStoredToken() -> Bool {
        storedToken() != nil
    }

    func storedAccessToken() -> String? {
        storedToken()?.accessToken
    }

    func missingRequiredScopes() -> Set<String> {
        guard let token = storedToken() else { return [] }
        return Self.requiredScopes.subtracting(token.grantedScopes)
    }

    func authorize(forceLogin: Bool = false) async throws -> StravaAuthorizationResult {
        let credentials = storedCredentials()
        guard credentials.isComplete else {
            throw StravaClientError.missingCredentials
        }

        let approvalPrompt = forceLogin ? "force" : "auto"
        let appAuthorizeURL = try authorizationURL(clientID: credentials.clientID, approvalPrompt: approvalPrompt, useStravaScheme: true)
        if UIApplication.shared.canOpenURL(appAuthorizeURL) {
            try await openStravaAppAuthorization(url: appAuthorizeURL)
            return .openedStravaApp
        }

        let webAuthorizeURL = try authorizationURL(clientID: credentials.clientID, approvalPrompt: approvalPrompt, useStravaScheme: false)
        let callbackURL = try await startAuthenticationSession(url: webAuthorizeURL)
        try await handleCallback(url: callbackURL)
        return .connected
    }

    func handleCallback(url: URL) async throws {
        guard url.scheme == callbackScheme else {
            throw StravaClientError.invalidCallback
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw StravaClientError.authorizationDenied(error)
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw StravaClientError.invalidCallback
        }

        let credentials = storedCredentials()
        guard credentials.isComplete else {
            throw StravaClientError.missingCredentials
        }

        let token = try await exchangeCode(code, credentials: credentials)
        try validateScopes(token)
        try store(token)
    }

    func validAccessToken() async throws -> String? {
        guard var token = storedToken() else { return nil }
        try validateScopes(token)
        if token.needsRefresh {
            token = try await refresh(token: token)
            try validateScopes(token)
            try store(token)
        }
        return token.accessToken
    }

    func disconnect() {
        keychain.delete(account: Account.token)
    }

    func createUpload(workout: WorkoutSummary, tcxData: Data, accessToken: String) async throws -> StravaUploadResult {
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormData(boundary: boundary)
            .addField(name: "data_type", value: "tcx")
            .addField(name: "name", value: workout.activity.displayName)
            .addField(name: "description", value: "Uploaded by Tracker")
            .addField(name: "trainer", value: workout.activity.environment == .indoor ? "1" : "0")
            .addField(name: "external_id", value: "\(workout.id.uuidString).tcx")
            .addFile(name: "file", filename: "\(workout.id.uuidString).tcx", mimeType: "application/vnd.garmin.tcx+xml", data: tcxData)
            .data

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let upload = try JSONDecoder().decode(StravaUploadResponse.self, from: data)
        return try result(from: upload)
    }

    func waitForUploadProcessing(
        uploadID: String,
        accessToken: String,
        pollIntervalSeconds: UInt64 = 1,
        maxAttempts: Int = 30
    ) async throws -> StravaUploadResult {
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: max(1, pollIntervalSeconds) * 1_000_000_000)
            }

            let upload = try await uploadStatus(uploadID: uploadID, accessToken: accessToken)
            let uploadResult = try result(from: upload, fallbackUploadID: uploadID)
            if uploadResult.activityID != nil {
                return uploadResult
            }
        }

        throw StravaClientError.uploadTimedOut(uploadID)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func authorizationURL(clientID: String, approvalPrompt: String, useStravaScheme: Bool) throws -> URL {
        var components = URLComponents(string: useStravaScheme ? "strava://oauth/mobile/authorize" : "https://www.strava.com/oauth/mobile/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: approvalPrompt),
            URLQueryItem(name: "scope", value: "activity:write,read")
        ]
        guard let url = components?.url else {
            throw StravaClientError.invalidAuthorizationURL
        }
        return url
    }

    private func openStravaAppAuthorization(url: URL) async throws {
        let opened = await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }

        guard opened else {
            throw StravaClientError.authorizationAppOpenFailed
        }
    }

    private func startAuthenticationSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: StravaClientError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            session.start()
        }
    }

    private func exchangeCode(_ code: String, credentials: StravaCredentials) async throws -> StravaStoredToken {
        try await tokenRequest(parameters: [
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ])
    }

    private func refresh(token: StravaStoredToken) async throws -> StravaStoredToken {
        let credentials = storedCredentials()
        guard credentials.isComplete else {
            throw StravaClientError.missingCredentials
        }

        return try await tokenRequest(parameters: [
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "refresh_token": token.refreshToken,
            "grant_type": "refresh_token"
        ])
    }

    private func tokenRequest(parameters: [String: String]) async throws -> StravaStoredToken {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let token = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        guard let accessToken = token.accessToken, let refreshToken = token.refreshToken, let expiresAt = token.expiresAt else {
            throw StravaClientError.missingToken
        }

        return StravaStoredToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt)),
            scope: token.scope,
            athleteID: token.athlete?.id
        )
    }

    private func validateScopes(_ token: StravaStoredToken) throws {
        let missing = Self.requiredScopes.subtracting(token.grantedScopes)
        guard missing.isEmpty else {
            throw StravaClientError.missingScopes(missing.sorted())
        }
    }

    private func uploadStatus(uploadID: String, accessToken: String) async throws -> StravaUploadResponse {
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads/\(uploadID)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(StravaUploadResponse.self, from: data)
    }

    private func result(from upload: StravaUploadResponse, fallbackUploadID: String? = nil) throws -> StravaUploadResult {
        if let error = upload.normalizedError {
            throw StravaClientError.uploadFailed(error)
        }

        guard let uploadID = upload.uploadIDString ?? fallbackUploadID else {
            throw StravaClientError.missingUploadID
        }

        return StravaUploadResult(
            uploadID: uploadID,
            activityID: upload.activityIDString,
            status: upload.status
        )
    }

    private func storedToken() -> StravaStoredToken? {
        guard let data = keychain.data(for: Account.token) else { return nil }
        return try? JSONDecoder().decode(StravaStoredToken.self, from: data)
    }

    private func store(_ token: StravaStoredToken) throws {
        let data = try JSONEncoder().encode(token)
        try keychain.set(data, for: Account.token)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw StravaClientError.requestFailed(message)
        }
    }

    private func formBody(_ parameters: [String: String]) -> Data {
        let encoded = parameters
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }
}

enum StravaClientError: LocalizedError {
    case missingCredentials
    case invalidAuthorizationURL
    case invalidCallback
    case authorizationDenied(String)
    case authorizationAppOpenFailed
    case missingToken
    case missingScopes([String])
    case missingUploadID
    case uploadFailed(String)
    case uploadTimedOut(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Enter Strava API Client ID and Client Secret before connecting. Do not enter your Strava username or password."
        case .invalidAuthorizationURL:
            return "Could not create the Strava authorization URL."
        case .invalidCallback:
            return "The Strava authorization callback was invalid."
        case .authorizationDenied(let reason):
            return "Strava authorization failed: \(reason)."
        case .authorizationAppOpenFailed:
            return "Could not open Strava for authorization."
        case .missingToken:
            return "Strava did not return a usable access token."
        case .missingScopes(let scopes):
            return "Reconnect Strava and approve: \(scopes.joined(separator: ", "))."
        case .missingUploadID:
            return "Strava accepted the upload but did not return an upload ID."
        case .uploadFailed(let message):
            return "Strava upload failed: \(message)"
        case .uploadTimedOut(let uploadID):
            return "Strava upload \(uploadID) is still processing. Retry upload status later."
        case .requestFailed(let message):
            return "Strava request failed: \(message)"
        }
    }
}

private struct StravaTokenResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Int?
    var scope: String?
    var athlete: StravaAthlete?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case scope
        case athlete
    }
}

private struct StravaAthlete: Decodable {
    var id: Int
}

private struct StravaUploadResponse: Decodable {
    var id: Int64?
    var idString: String?
    var activityID: Int64?
    var externalID: String?
    var error: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case idString = "id_str"
        case activityID = "activity_id"
        case externalID = "external_id"
        case error
        case status
    }

    var uploadIDString: String? {
        id.map(String.init) ?? trimmed(idString)
    }

    var activityIDString: String? {
        activityID.map(String.init)
    }

    var normalizedError: String? {
        trimmed(error)
    }

    private func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct MultipartFormData {
    let boundary: String
    private(set) var data = Data()

    func addField(name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.data.append("--\(boundary)\r\n")
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.data.append("\(value)\r\n")
        return copy
    }

    func addFile(name: String, filename: String, mimeType: String, data fileData: Data) -> MultipartFormData {
        var copy = self
        copy.data.append("--\(boundary)\r\n")
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        copy.data.append("Content-Type: \(mimeType)\r\n\r\n")
        copy.data.append(fileData)
        copy.data.append("\r\n--\(boundary)--\r\n")
        return copy
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return allowed
    }()
}
