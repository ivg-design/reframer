import SwiftUI

struct ControlWindowView: View {
    @EnvironmentObject var videoState: VideoState

    var body: some View {
        ZStack {
            Color.clear
            VStack {
                Spacer()
                WindowDragView {
                    ControlBarView()
                }
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ControlWindowView_Previews: PreviewProvider {
    static var previews: some View {
        ControlWindowView()
            .environmentObject(VideoState())
            .frame(width: 600, height: 80)
            .background(Color.black.opacity(0.2))
    }
}
