import SwiftUI

struct OnboardingPermissionView: View {
    let alwaysHiddenEnabled: Bool
    let onRequestTrust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow Accessibility Access to Manage Menu Bar Icons")
                        .font(.headline)
                    Text("MenuTuck uses macOS Accessibility to list your active menu bar items, detect live ⌘-drags across the |› and ‖ dividers, and open items from Settings. No Screen Recording permission is used.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button("Open Accessibility Settings", action: onRequestTrust)
                            .buttonStyle(.borderedProminent)
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Waiting for permission — this screen updates automatically")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)

                    Divider()
                        .padding(.vertical, 4)

                    Label(
                        "Just updated MenuTuck? If Accessibility already appears ON in System Settings, select MenuTuck, click remove (–), and add it again (+).",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 10) {
                Text("How MenuTuck Works")
                    .font(.headline)

                OnboardingStepRow(
                    symbol: "menubar.rectangle",
                    title: "Click |‹ in the menu bar\(Preferences.shared.toggleShortcut.map { " (or press \($0.label))" } ?? "") to expand",
                    detail: "Expanding reveals your Hidden icons along with the |› and ‖ section dividers."
                )
                OnboardingStepRow(
                    symbol: "hand.draw",
                    title: "Hold ⌘ and drag any icon left of |› or ‖",
                    detail: alwaysHiddenEnabled
                        ? "Icons left of |› are Hidden when collapsed. Icons left of ‖ are Always Hidden."
                        : "Icons left of |› are Hidden when collapsed; icons right of |› stay Visible."
                )
                OnboardingStepRow(
                    symbol: "slider.horizontal.3",
                    title: "Or assign sections directly from this list",
                    detail: "Once Accessibility is enabled above, all running menu bar apps appear here."
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingStepRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
