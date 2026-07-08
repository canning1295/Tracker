import SwiftUI

enum LoadingPhraseProvider {
    static let healthImportPhrases = [
        "Reticulating splits...",
        "Negotiating with HealthKit...",
        "Warming up the tiny treadmill...",
        "Going DEFCON 5. Launching all split calculations.",
        "Finding yesterday's motivation...",
        "Calculating the sweat-to-snack exchange rate...",
        "Pretending this is a training montage...",
        "Asking the map where it left your route...",
        "Convincing the stopwatch to cooperate...",
        "Sorting heroic efforts by start time..."
    ]
}

struct HumorousLoadingView: View {
    let title: String
    let phrases: [String]
    @State private var phraseIndex = 0

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(currentPhrase)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .id(currentPhrase)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
                guard phrases.count > 1 else { continue }
                withAnimation(.easeInOut(duration: 0.25)) {
                    phraseIndex = (phraseIndex + 1) % phrases.count
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var currentPhrase: String {
        guard !phrases.isEmpty else { return "" }
        return phrases[phraseIndex % phrases.count]
    }
}

struct ThinkingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isAnimating ? 1.0 : 0.45)
                    .opacity(isAnimating ? 1.0 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.55)
                        .repeatForever()
                        .delay(Double(index) * 0.16),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
        .accessibilityLabel("Loading")
    }
}
