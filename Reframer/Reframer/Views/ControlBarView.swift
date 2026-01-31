import SwiftUI
import AppKit

struct ControlBarView: View {
    @EnvironmentObject var videoState: VideoState
    @State private var isHovering = false
    @State private var frameText = "0"
    @State private var zoomText = "100"
    @State private var opacityText = "100"
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            // Open
            ControlButton(icon: "folder", action: { NotificationCenter.default.post(name: .openVideo, object: nil) })

            Divider().frame(height: 16)

            // Playback
            ControlButton(icon: "backward.frame", action: { NotificationCenter.default.post(name: .frameStepBackward, object: 1) })
                .disabled(!videoState.isVideoLoaded)

            ControlButton(icon: videoState.isPlaying ? "pause.fill" : "play.fill", action: { videoState.isPlaying.toggle() })
                .disabled(!videoState.isVideoLoaded)

            ControlButton(icon: "forward.frame", action: { NotificationCenter.default.post(name: .frameStepForward, object: 1) })
                .disabled(!videoState.isVideoLoaded)

            // Timeline
            if videoState.isVideoLoaded {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : videoState.currentTime },
                        set: { newValue in
                            scrubValue = newValue
                            NotificationCenter.default.post(name: .seekToTime, object: newValue)
                        }
                    ),
                    in: 0...max(0.1, videoState.duration),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            NotificationCenter.default.post(name: .seekToTime, object: scrubValue)
                        }
                    }
                )
                .frame(minWidth: 80, maxWidth: 200)
                .controlSize(.small)
            }

            Divider().frame(height: 16)

            // Frame
            HStack(spacing: 2) {
                Image(systemName: "film").font(.system(size: 10)).foregroundStyle(.secondary)
                NumericInputField(
                    text: $frameText,
                    min: 0,
                    max: Double(max(videoState.totalFrames - 1, 0)),
                    allowsDecimal: false,
                    step: 1,
                    shiftStep: 10,
                    cmdStep: nil,
                    decimalPlaces: 0,
                    font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    alignment: .right,
                    isEnabled: videoState.isVideoLoaded,
                    onValueChange: { value in
                        let frame = Int(round(value))
                        let clamped = max(0, min(videoState.totalFrames - 1, frame))
                        NotificationCenter.default.post(name: .seekToFrame, object: clamped)
                    }
                )
                .frame(width: 52)
                Text("/ \(videoState.totalFrames)").font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Divider().frame(height: 16)

            // Zoom
            HStack(spacing: 2) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                NumericInputField(
                    text: $zoomText,
                    min: 10,
                    max: 1000,
                    allowsDecimal: true,
                    step: 1,
                    shiftStep: 10,
                    cmdStep: 0.1,
                    decimalPlaces: 1,
                    font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    alignment: .right,
                    isEnabled: videoState.isVideoLoaded && !videoState.isLocked,
                    onValueChange: { value in
                        videoState.setZoomPercentage(value)
                    }
                )
                .frame(width: 44)
                Text("%").font(.system(size: 10)).foregroundStyle(.secondary)
            }

            ControlButton(icon: "arrow.counterclockwise", action: { videoState.resetView() })
                .disabled(videoState.isLocked)

            Divider().frame(height: 16)

            // Opacity
            HStack(spacing: 2) {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 10)).foregroundStyle(.secondary)
                NumericInputField(
                    text: $opacityText,
                    min: 2,
                    max: 100,
                    allowsDecimal: false,
                    step: 1,
                    shiftStep: 10,
                    cmdStep: nil,
                    decimalPlaces: 0,
                    font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    alignment: .right,
                    isEnabled: videoState.isVideoLoaded,
                    onValueChange: { value in
                        videoState.setOpacityPercentage(Int(round(value)))
                    }
                )
                .frame(width: 40)
                Text("%").font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Slider(value: $videoState.opacity, in: 0.02...1.0)
                .frame(width: 50)
                .controlSize(.mini)

            Divider().frame(height: 16)

            // Volume
            ControlButton(icon: videoState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", action: { videoState.toggleMute() })

            if !videoState.isMuted {
                Slider(value: $videoState.volume, in: 0...1)
                    .frame(width: 50)
                    .controlSize(.mini)
            }

            Divider().frame(height: 16)

            // Lock
            ControlButton(icon: videoState.isLocked ? "lock.fill" : "lock.open", action: { videoState.isLocked.toggle() }, isActive: videoState.isLocked)

            // Pin
            ControlButton(icon: videoState.isAlwaysOnTop ? "pin.fill" : "pin", action: { videoState.isAlwaysOnTop.toggle() }, isActive: videoState.isAlwaysOnTop)

            // Help
            ControlButton(icon: "questionmark.circle", action: { videoState.showHelp = true })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(GlassBackgroundModifier(cornerRadius: 10))
        .padding(8)
        .opacity(isHovering || !videoState.isVideoLoaded || videoState.isLocked ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear {
            frameText = "\(videoState.currentFrame)"
            zoomText = formatZoomText(videoState.zoomPercentageValue)
            opacityText = "\(videoState.opacityPercentage)"
            scrubValue = videoState.currentTime
        }
        .onChange(of: videoState.currentFrame) { _, newValue in frameText = "\(newValue)" }
        .onChange(of: videoState.zoomPercentageValue) { _, newValue in zoomText = formatZoomText(newValue) }
        .onChange(of: videoState.opacityPercentage) { _, newValue in opacityText = "\(newValue)" }
        .onChange(of: videoState.currentTime) { _, newValue in
            if !isScrubbing {
                scrubValue = newValue
            }
        }
    }

    private func formatZoomText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        var text = String(format: "%.1f", rounded)
        if text.hasSuffix(".0") {
            text = String(text.dropLast(2))
        }
        return text
    }
}

struct ControlButton: View {
    let icon: String
    let action: () -> Void
    var isActive: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 4).fill(isActive ? Color.accentColor.opacity(0.2) : .clear))
    }
}

// MARK: - Glass Background Modifier (Tahoe + Sequoia fallback)

struct GlassBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        }
    }
}

// MARK: - Glass Background Shape (for standalone use)

struct GlassBackgroundShape: View {
    let cornerRadius: CGFloat

    var body: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
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
        }
    }
}
