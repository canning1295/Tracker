import SwiftUI

struct CrownMenu<Option: Identifiable, RowContent: View>: View {
    let title: String
    let options: [Option]
    @Binding var selectionIndex: Int
    let screenIndex: Int
    let screenCount: Int
    let onSelect: (Option) -> Void
    var onBack: (() -> Void)?
    var onForward: ((Option) -> Void)?
    var fillRows = false
    var showsPageDots = false
    @ViewBuilder let rowContent: (Option, Bool) -> RowContent

    @FocusState private var focused: Bool
    @State private var crownValue: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if options.isEmpty {
                Spacer(minLength: 0)
                Text("No workouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if fillRows {
                VStack(spacing: 5) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        optionButton(option, at: index)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: options.count > 3) {
                        LazyVStack(spacing: 5) {
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                optionButton(option, at: index)
                                    .id(option.id)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .onAppear {
                        scrollToSelection(using: proxy, animated: false)
                    }
                    .onChange(of: clampedSelectionIndex) { _, _ in
                        scrollToSelection(using: proxy, animated: true)
                    }
                }
            }

            if showsPageDots {
                CrownPageDots(current: screenIndex, count: screenCount)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .focusable(!options.isEmpty)
        .focused($focused)
        .digitalCrownRotation(
            $crownValue,
            from: scrollModel.crownLowerBound,
            through: scrollModel.crownUpperBound,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            syncCrownToSelection()
            focused = !options.isEmpty
        }
        .onChange(of: crownValue) { _, newValue in
            updateSelection(from: newValue)
        }
        .onChange(of: selectionIndex) { _, _ in
            syncCrownToSelection()
        }
    }

    private var clampedSelectionIndex: Int {
        scrollModel.clampedSelection(selectionIndex)
    }

    private func optionButton(_ option: Option, at index: Int) -> some View {
        Button {
            selectionIndex = index
            onSelect(option)
        } label: {
            rowContent(option, index == clampedSelectionIndex)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func scrollToSelection(using proxy: ScrollViewProxy, animated: Bool) {
        guard options.indices.contains(clampedSelectionIndex) else { return }
        let selectedID = options[clampedSelectionIndex].id
        if animated {
            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(selectedID, anchor: .center)
            }
        } else {
            proxy.scrollTo(selectedID, anchor: .center)
        }
    }

    private var scrollModel: CrownMenuScrollModel {
        CrownMenuScrollModel(optionCount: options.count, hasBack: onBack != nil, hasForward: onForward != nil)
    }

    private func syncCrownToSelection() {
        guard !options.isEmpty else { return }
        let clamped = clampedSelectionIndex
        if selectionIndex != clamped {
            selectionIndex = clamped
        }
        let next = scrollModel.crownValue(forSelection: clamped)
        if crownValue != next {
            crownValue = next
        }
    }

    private func updateSelection(from value: Double) {
        guard !options.isEmpty else { return }

        switch scrollModel.action(forCrownValue: value, currentSelectionIndex: selectionIndex) {
        case .select(let index):
            selectionIndex = index
        case .back:
            crownValue = scrollModel.crownValue(forSelection: 0)
            onBack?()
        case .forward(let index):
            crownValue = scrollModel.crownValue(forSelection: index)
            selectionIndex = index
            if options.indices.contains(index) {
                onForward?(options[index])
            }
        case nil:
            break
        }
    }
}

struct CrownMenuRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var subtitle: String?
    var fillHeight = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, subtitle == nil ? 8 : 5)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.orange : Color.clear)
        }
    }
}

struct CrownPageDots: View {
    let current: Int
    let count: Int

    var body: some View {
        Group {
            if count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { index in
                        Circle()
                            .fill(index == current ? Color.orange : Color.secondary.opacity(0.35))
                            .frame(width: index == current ? 6 : 4, height: index == current ? 6 : 4)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
