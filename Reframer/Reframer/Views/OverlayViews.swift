import SwiftUI

// MARK: - Lock Indicator

struct LockIndicator: View {
    @EnvironmentObject var videoState: VideoState

    var body: some View {
        Group {
            if videoState.isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                    Text("Locked")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.9))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: videoState.isLocked)
    }
}
