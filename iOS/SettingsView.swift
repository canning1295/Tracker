import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showsStravaSetup = false
    @State private var isImportingHealthMetrics = false
    @State private var isConnectingStrava = false

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section("Units") {
                Picker("Distance", selection: $appState.settings.distanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }

                Picker("Pace", selection: $appState.settings.paceMode) {
                    ForEach(PaceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Stepper("Rolling pace \(appState.settings.rollingPaceSeconds)s", value: $appState.settings.rollingPaceSeconds, in: 5...180, step: 5)
            }

            Section("Watch Controls") {
                Label("Touch navigation stays on", systemImage: "hand.tap")
                    .foregroundStyle(.secondary)

                Picker("Announce Every", selection: $appState.settings.splitAnnouncementUnit) {
                    ForEach(WorkoutAnnouncementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }

            Section("Heart Rate") {
                Stepper("Max HR \(appState.settings.heartRate.maxHeartRate)", value: $appState.settings.heartRate.maxHeartRate, in: 120...230)

                ForEach(HeartRateZone.allCases) { zone in
                    HStack {
                        Circle()
                            .fill(zone.color)
                            .frame(width: 10, height: 10)
                        Text(zone.displayName)
                        Spacer()
                        Text(HeartRateZoneCalculator.bpmRangeText(for: zone, settings: appState.settings.heartRate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("VO2 Estimate Inputs") {
                OptionalIntField(title: "Age (years)", value: $appState.settings.userMetrics.age)
                Picker("Sex", selection: Binding(
                    get: { appState.settings.userMetrics.biologicalSex ?? .notSet },
                    set: { appState.settings.userMetrics.biologicalSex = $0 == .notSet ? nil : $0 }
                )) {
                    ForEach(BiologicalSex.allCases) { sex in
                        Text(sex.displayName).tag(sex)
                    }
                }
                Picker("Body Units", selection: $appState.settings.bodyMeasurementUnit) {
                    ForEach(BodyMeasurementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                if appState.settings.bodyMeasurementUnit == .metric {
                    OptionalDoubleField(title: "Height (cm)", value: $appState.settings.userMetrics.heightCentimeters)
                    OptionalDoubleField(title: "Weight (kg)", value: $appState.settings.userMetrics.weightKilograms)
                } else {
                    OptionalDoubleField(title: "Height (in)", value: heightInchesBinding)
                    OptionalDoubleField(title: "Weight (lb)", value: weightPoundsBinding)
                }
                OptionalIntField(title: "Resting HR (bpm)", value: $appState.settings.userMetrics.restingHeartRate)
                OptionalDoubleField(title: "Known VO2 Max (ml/kg/min)", value: $appState.settings.userMetrics.knownVO2Max)

                Button {
                    Task { await importHealthMetrics() }
                } label: {
                    HStack {
                        Label("Import From Apple Health", systemImage: "heart.text.square")
                        if isImportingHealthMetrics {
                            Spacer()
                            ThinkingIndicator()
                        }
                    }
                }
                .disabled(isImportingHealthMetrics)

                if let message = appState.healthMetricsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Outdoor Order") {
                ForEach(appState.settings.outdoorOrder) { activity in
                    Label(activity.displayName, systemImage: activity.symbolName)
                }
                .onMove(perform: appState.moveOutdoor)
            }

            Section("Indoor Order") {
                ForEach(appState.settings.indoorOrder) { activity in
                    Label(activity.displayName, systemImage: activity.symbolName)
                }
                .onMove(perform: appState.moveIndoor)
            }

            Section("Strava") {
                Toggle("Auto-upload", isOn: $appState.settings.stravaAutoUpload)

                if let message = appState.stravaConnectionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(appState.stravaIsConnected ? .green : .secondary)
                }

                Button {
                    if appState.stravaCredentialsAreComplete {
                        Task { await connectStrava() }
                    } else {
                        showsStravaSetup = true
                        appState.requestStravaCredentialSetup()
                    }
                } label: {
                    HStack {
                        Label(appState.stravaIsConnected ? "Change Strava Login" : "Connect Strava", systemImage: "link")
                        if isConnectingStrava {
                            Spacer()
                            ThinkingIndicator()
                        }
                    }
                }
                .disabled(isConnectingStrava)

                Button {
                    showsStravaSetup.toggle()
                } label: {
                    Label(showsStravaSetup ? "Hide Advanced API Setup" : "Advanced API Setup", systemImage: "gearshape")
                }

                if showsStravaSetup || appState.stravaHasAnyCredentialInput {
                    Text("These are Strava developer API values, not your Strava username or password. Your Strava login happens in Strava after you connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup steps")
                            .font(.caption.weight(.semibold))
                        Text("1. Tap Open Strava API Settings, or visit strava.com/settings/api in Safari.")
                        Text("2. Sign in to Strava in the browser if asked.")
                        Text("3. Find My API Application. If it is blank or missing, create an app named Tracker.")
                        Text("4. Set Website to https://localhost and Authorization Callback Domain to \(appState.stravaRequiredCallbackDomain).")
                        Text("5. Save the Strava API application.")
                        Text("6. Copy Client ID and Client Secret from that page into Tracker.")
                        Text("7. Tap Connect Strava.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    TextField("Strava API Client ID", text: $appState.stravaClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Strava API Client Secret", text: $appState.stravaClientSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    LabeledContent("Callback") {
                        Text(appState.stravaRequiredRedirectURI)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Callback Domain") {
                        Text(appState.stravaRequiredCallbackDomain)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Scope") {
                        Text(appState.stravaRequiredScopeText)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://www.strava.com/settings/api")!) {
                        Label("Open Strava API Settings", systemImage: "safari")
                    }

                    ForEach(appState.stravaSetupWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        appState.saveStravaCredentials()
                    } label: {
                        Label("Save API Credentials", systemImage: "key")
                    }
                }

                if appState.stravaIsConnected {
                    Button(role: .destructive) {
                        appState.disconnectStrava()
                    } label: {
                        Label("Disconnect Strava", systemImage: "link.badge.minus")
                    }
                }
            }

            Section("Device Readiness") {
                ForEach(appState.deviceReadinessItems) { item in
                    DeviceReadinessRow(item: item)
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar { EditButton() }
    }

    private func importHealthMetrics() async {
        guard !isImportingHealthMetrics else { return }
        isImportingHealthMetrics = true
        await appState.importUserMetricsFromHealth()
        isImportingHealthMetrics = false
    }

    private func connectStrava() async {
        guard !isConnectingStrava else { return }
        isConnectingStrava = true
        await appState.connectStrava(forceLogin: appState.stravaIsConnected)
        isConnectingStrava = false
    }

    private var heightInchesBinding: Binding<Double?> {
        Binding(
            get: {
                appState.settings.userMetrics.heightCentimeters.map { $0 / 2.54 }
            },
            set: { newValue in
                appState.settings.userMetrics.heightCentimeters = newValue.map { $0 * 2.54 }
            }
        )
    }

    private var weightPoundsBinding: Binding<Double?> {
        Binding(
            get: {
                appState.settings.userMetrics.weightKilograms.map { $0 * 2.2046226218 }
            },
            set: { newValue in
                appState.settings.userMetrics.weightKilograms = newValue.map { $0 / 2.2046226218 }
            }
        )
    }
}

private struct DeviceReadinessRow: View {
    let item: DeviceReadinessItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.level.symbolName)
                .foregroundStyle(item.level.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(item.level.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.level.color)
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private extension DeviceReadinessLevel {
    var displayName: String {
        switch self {
        case .ready: return "Ready"
        case .warning: return "Check"
        case .blocked: return "Blocked"
        }
    }

    var symbolName: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .green
        case .warning: return .orange
        case .blocked: return .red
        }
    }
}

private extension HeartRateZone {
    var color: Color {
        switch self {
        case .zone1: return .blue
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        }
    }
}

private struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        LabeledContent(title) {
            TextField("Not set", value: Binding(
                get: { value ?? 0 },
                set: { value = $0 == 0 ? nil : $0 }
            ), format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 120)
            .accessibilityLabel(title)
        }
    }
}

private struct OptionalDoubleField: View {
    let title: String
    @Binding var value: Double?

    var body: some View {
        LabeledContent(title) {
            TextField("Not set", value: Binding(
                get: { value ?? 0 },
                set: { value = $0 == 0 ? nil : $0 }
            ), format: .number.precision(.fractionLength(1)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 120)
            .accessibilityLabel(title)
        }
    }
}
