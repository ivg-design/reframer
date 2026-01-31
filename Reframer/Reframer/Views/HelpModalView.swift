import SwiftUI

struct HelpModalView: View {
    @EnvironmentObject var videoState: VideoState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button(action: { videoState.showHelp = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Shortcuts list
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ShortcutSection(title: "File") {
                        ShortcutRow(keys: "⌘O", description: "Open video file")
                    }

                    ShortcutSection(title: "Playback") {
                        ShortcutRow(keys: "Space", description: "Play / Pause")
                        ShortcutRow(keys: "← →", description: "Step frame back/forward")
                        ShortcutRow(keys: "⇧← ⇧→", description: "Step 10 frames")
                        ShortcutRow(keys: "Scroll", description: "Step frames (unlocked)")
                        ShortcutRow(keys: "⌘ PgUp/Dn", description: "Step frame (global, ⇧ for 10)")
                    }

                    ShortcutSection(title: "View") {
                        ShortcutRow(keys: "↑ ↓", description: "Zoom in/out (5%)")
                        ShortcutRow(keys: "⇧↑ ⇧↓", description: "Zoom faster (10%)")
                        ShortcutRow(keys: "+ / -", description: "Zoom in/out")
                        ShortcutRow(keys: "0", description: "Reset zoom to 100%")
                        ShortcutRow(keys: "R", description: "Reset zoom and pan")
                        ShortcutRow(keys: "⇧ Scroll", description: "Zoom (5%, unlocked)")
                        ShortcutRow(keys: "⌘⇧ Scroll", description: "Fine zoom (0.1%, unlocked)")
                    }

                    ShortcutSection(title: "Window & Lock") {
                        ShortcutRow(keys: "L", description: "Toggle lock mode")
                        ShortcutRow(keys: "⌘⇧L", description: "Toggle lock (global)")
                        ShortcutRow(keys: "H / ?", description: "Show this help")
                        ShortcutRow(keys: "Esc", description: "Close help")
                    }

                    ShortcutSection(title: "Mouse") {
                        ShortcutRow(keys: "Drag video", description: "Pan when zoomed (unlocked)")
                        ShortcutRow(keys: "Drag bar", description: "Move window (unlocked)")
                        ShortcutRow(keys: "Drag handle", description: "Move window (unlocked)")
                        ShortcutRow(keys: "Drag edges", description: "Resize window (unlocked)")
                    }

                    ShortcutSection(title: "Inputs") {
                        ShortcutRow(keys: "↑ / ↓", description: "Step value (⇧ for 10, ⌘ for 0.1% zoom)")
                        ShortcutRow(keys: "Esc / Enter", description: "Defocus and return to previous app")
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Text("Video Overlay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Press Esc to close")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 340, height: 480)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Shortcut Section

struct ShortcutSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}

// MARK: - Shortcut Row

struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 90, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Preview

struct HelpModalView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.5)
            HelpModalView()
                .environmentObject(VideoState())
        }
        .frame(width: 500, height: 600)
    }
}
