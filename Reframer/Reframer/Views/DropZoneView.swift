import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var videoState: VideoState
    @State private var isTargeted: Bool = false

    var body: some View {
        ZStack {
            // macOS glass background
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)

            // Drop target highlight
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 2)
            }

            // Content
            VStack(spacing: 16) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Drop video here")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)

                Text("or press ⌘O to open")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // Supported formats hint
                Text(VideoFormats.displayString)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
        .onDrop(of: VideoFormats.supportedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onTapGesture {
            openVideoFile()
        }
        .contentShape(Rectangle())
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        for type in VideoFormats.supportedTypes {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            videoState.videoURL = url
                            videoState.isVideoLoaded = true
                        }
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            videoState.videoURL = url
                            videoState.isVideoLoaded = true
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func openVideoFile() {
        NotificationCenter.default.post(name: .openVideo, object: nil)
    }
}

// MARK: - Preview

struct DropZoneView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Simulate desktop background
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            DropZoneView()
                .environmentObject(VideoState())
                .padding(40)
        }
        .frame(width: 600, height: 400)
    }
}
