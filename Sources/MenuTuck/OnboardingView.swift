import SwiftUI

/// Step 1: MenuTuck can't see the menu bar until Accessibility is granted.
struct OnboardingPermissionView: View {
    let onRequestTrust: () -> Void

    var body: some View {
        OnboardingCard(step: 1, symbol: "hand.raised.fill", title: "Allow Accessibility access") {
            Text("MenuTuck uses Accessibility to list your menu bar icons and open their menus. It never records your screen.")
            HStack(spacing: 12) {
                Button("Open Accessibility Settings", action: onRequestTrust)
                    .buttonStyle(.borderedProminent)
                ProgressView().controlSize(.mini)
                Text("This screen moves on by itself once it's on.")
                    .font(.caption)
            }
            Label(
                "Just updated MenuTuck and it's already on? Remove MenuTuck from the list (–) and add it again (+).",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.caption)
        }
    }
}

/// Step 2: pick which icons leave the menu bar.
struct OnboardingPickView: View {
    @ObservedObject var model: ItemsModel
    let onNext: () -> Void

    var body: some View {
        let items = model.items.filter { $0.section != .alwaysHidden && $0.pid != 0 }
        OnboardingCard(step: 2, symbol: "checklist", title: "Pick icons to tuck away") {
            Text("Ticked icons leave the menu bar and wait in the Tray. You can change this any time.")
            List(items) { item in
                Toggle(isOn: Binding(
                    get: { item.section == .hidden },
                    set: { model.move(item, to: $0 ? .hidden : .visible) }
                )) {
                    HStack(spacing: 8) {
                        Image(nsImage: item.appIcon).resizable().frame(width: 18, height: 18)
                        Text(item.appName)
                    }
                }
            }
            .frame(minHeight: 180)
            HStack {
                Spacer()
                Button("Continue", action: onNext).buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Step 3: show where the tucked icons went.
struct OnboardingDoneView: View {
    @ObservedObject var model: ItemsModel
    let onDone: () -> Void

    var body: some View {
        let tucked = model.items(in: .hidden).prefix(12)
        OnboardingCard(step: 3, symbol: "checkmark.circle.fill", title: "That's it") {
            Text("Click |‹ in the menu bar\(Preferences.shared.toggleShortcut.map { " or press \($0.label)" } ?? "") to open the Tray. Type to filter, press 1–9 to open an icon.")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 8) {
                ForEach(Array(tucked.enumerated()), id: \.element.id) { index, item in
                    Image(nsImage: item.appIcon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .frame(width: 44, height: 44)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topLeading) {
                            if index < 9 {
                                Text("\(index + 1)").font(.caption2.monospacedDigit()).padding(3)
                            }
                        }
                        .accessibilityLabel(item.appName)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Spacer()
                Button("Done", action: onDone).buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct OnboardingCard<Content: View>: View {
    let step: Int
    let symbol: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Step \(step) of 3").font(.caption).foregroundStyle(.secondary)
                    Text(title).font(.headline)
                }
            }
            VStack(alignment: .leading, spacing: 10) { content }
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}
