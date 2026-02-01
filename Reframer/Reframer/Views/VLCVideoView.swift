import Cocoa
import Combine

/// Video view that uses VLCKit for playback (dynamically loaded)
class VLCVideoView: NSView {

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()

    // VLCKit objects (loaded dynamically via ObjC runtime)
    private var mediaPlayer: NSObject?
    private var vlcVideoView: NSView?

    // Playback state tracking
    private var timeObserverTimer: Timer?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        guard VLCKitManager.shared.isReady else {
            print("VLCVideoView: VLCKit not ready")
            return
        }

        setupVLCPlayer()
    }

    // MARK: - VLCKit Setup

    private func setupVLCPlayer() {
        print("VLCVideoView: Setting up VLC player...")
        if let pluginPath = getenv("VLC_PLUGIN_PATH") {
            print("VLCVideoView: VLC_PLUGIN_PATH = \(String(cString: pluginPath))")
        } else {
            print("VLCVideoView: VLC_PLUGIN_PATH not set!")
        }

        // First create the VLCVideoView (the drawable)
        guard let videoViewClass = NSClassFromString("VLCVideoView") as? NSView.Type else {
            print("VLCVideoView: VLCVideoView class not found, using self as drawable")
            setupPlayerWithDrawable(self)
            return
        }

        let videoView = videoViewClass.init(frame: bounds)
        videoView.autoresizingMask = [.width, .height]
        addSubview(videoView)
        vlcVideoView = videoView
        print("VLCVideoView: Created VLCVideoView")

        setupPlayerWithDrawable(videoView)
    }

    private func setupPlayerWithDrawable(_ drawable: NSView) {
        // Get VLCMediaPlayer class dynamically
        guard let playerClass: AnyClass = NSClassFromString("VLCMediaPlayer") else {
            print("VLCVideoView: VLCMediaPlayer class not found")
            return
        }
        print("VLCVideoView: Found VLCMediaPlayer class")

        // Get options from VLCKitManager - these will create a private VLCLibrary
        let options = VLCKitManager.shared.getLibraryOptions()
        print("VLCVideoView: Using options: \(options)")

        // Create media player with initWithDrawable:options: to use private library with our options
        // This is critical - initWithVideoView: uses shared library and ignores VLC_PLUGIN_PATH timing
        let initWithDrawableOptionsSel = NSSelectorFromString("initWithDrawable:options:")
        let playerResult = (playerClass as AnyObject).perform(NSSelectorFromString("alloc"))
        guard let allocatedPlayer = playerResult?.takeUnretainedValue() as? NSObject else {
            print("VLCVideoView: Failed to alloc VLCMediaPlayer")
            return
        }

        // Call initWithDrawable:options: - this creates a private VLCLibrary with our options
        if allocatedPlayer.responds(to: initWithDrawableOptionsSel) {
            // Use NSInvocation-style call for two arguments
            let imp = allocatedPlayer.method(for: initWithDrawableOptionsSel)
            typealias InitFunc = @convention(c) (AnyObject, Selector, NSView, NSArray) -> AnyObject
            let initFunc = unsafeBitCast(imp, to: InitFunc.self)
            _ = initFunc(allocatedPlayer, initWithDrawableOptionsSel, drawable, options as NSArray)
            mediaPlayer = allocatedPlayer
            print("VLCVideoView: Created media player with drawable and options (private library)")
        } else {
            // Fallback to initWithVideoView: if method not available
            print("VLCVideoView: initWithDrawable:options: not found, falling back to initWithVideoView:")
            let initWithVideoViewSel = NSSelectorFromString("initWithVideoView:")
            _ = allocatedPlayer.perform(initWithVideoViewSel, with: drawable)
            mediaPlayer = allocatedPlayer
            print("VLCVideoView: Created media player with video view (shared library)")
        }

        // Set up notifications for media player state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mediaPlayerStateChanged(_:)),
            name: NSNotification.Name("VLCMediaPlayerStateChanged"),
            object: mediaPlayer
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mediaPlayerTimeChanged(_:)),
            name: NSNotification.Name("VLCMediaPlayerTimeChanged"),
            object: mediaPlayer
        )
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        // Volume
        state.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.setVolume(Int(volume * 100))
            }
            .store(in: &cancellables)

        // Play/Pause
        state.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                if isPlaying {
                    self?.play()
                } else {
                    self?.pause()
                }
            }
            .store(in: &cancellables)

        // Seek notifications
        NotificationCenter.default.publisher(for: .seekToTime)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? Double }
            .sink { [weak self] time in
                self?.seek(to: time)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .seekToFrame)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? Int }
            .sink { [weak self] frame in
                self?.seekToFrame(frame)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .frameStepForward)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? Int }
            .sink { [weak self] amount in
                self?.stepFrame(forward: true, amount: amount)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .frameStepBackward)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? Int }
            .sink { [weak self] amount in
                self?.stepFrame(forward: false, amount: amount)
            }
            .store(in: &cancellables)
    }

    // MARK: - Video Loading

    func loadVideo(url: URL) {
        // Try to set up VLC player if not already done
        if mediaPlayer == nil {
            print("VLCVideoView: MediaPlayer is nil, attempting setup...")
            if VLCKitManager.shared.isReady {
                setupVLCPlayer()
            } else {
                // Try loading the framework
                VLCKitManager.shared.loadFramework()
                if VLCKitManager.shared.isReady {
                    setupVLCPlayer()
                }
            }
        }

        guard let mediaPlayer = mediaPlayer else {
            print("VLCVideoView: No media player after setup attempt")
            return
        }

        guard let state = videoState else { return }

        // Reset state
        state.currentTime = 0
        state.currentFrame = 0
        state.duration = 0
        state.totalFrames = 0
        state.isVideoLoaded = false

        // Create VLCMedia using URL (not path) for proper handling
        guard let mediaClass: AnyClass = NSClassFromString("VLCMedia") else {
            print("VLCVideoView: VLCMedia class not found")
            return
        }

        // Try mediaWithURL: first (handles file:// URLs properly)
        let mediaWithURLSel = NSSelectorFromString("mediaWithURL:")
        let mediaResult = (mediaClass as AnyObject).perform(mediaWithURLSel, with: url)
        guard let media = mediaResult?.takeUnretainedValue() as? NSObject else {
            print("VLCVideoView: Failed to create media with URL: \(url)")
            return
        }
        print("VLCVideoView: Created media for \(url.lastPathComponent)")
        print("VLCVideoView: Media object: \(media)")

        if let headers = state.videoHeaders, !headers.isEmpty {
            let options = headers.map { ":http-header=\($0.key): \($0.value)" }
            let addOptionsSel = NSSelectorFromString("addOptions:")
            let addOptionSel = NSSelectorFromString("addOption:")
            if media.responds(to: addOptionsSel) {
                _ = media.perform(addOptionsSel, with: options)
            } else if media.responds(to: addOptionSel) {
                for option in options {
                    _ = media.perform(addOptionSel, with: option)
                }
            }
        }

        // Parse media to get metadata (async if available)
        let parseAsyncSel = NSSelectorFromString("parseWithOptions:")
        if media.responds(to: parseAsyncSel) {
            _ = media.perform(parseAsyncSel, with: 1)
        } else {
            let parseSel = NSSelectorFromString("parse")
            if media.responds(to: parseSel) {
                media.perform(parseSel)
            }
        }

        // Check if media is parsed and get info
        if let isParsed = media.value(forKey: "isParsed") as? Bool {
            print("VLCVideoView: Media isParsed: \(isParsed)")
        }

        // Set media on player
        mediaPlayer.perform(Selector(("setMedia:")), with: media)
        print("VLCVideoView: Set media on player")

        // Add media delegate for state changes
        if media.responds(to: NSSelectorFromString("setDelegate:")) {
            print("VLCVideoView: Media supports delegate")
        }

        // Start playing to get duration
        play()

        // Set volume
        setVolume(Int(state.volume * 100))

        // Start time observer
        startTimeObserver()
    }

    // MARK: - Playback Control

    func play() {
        mediaPlayer?.perform(Selector(("play")))
    }

    func pause() {
        mediaPlayer?.perform(Selector(("pause")))
    }

    func stop() {
        mediaPlayer?.perform(Selector(("stop")))
        stopTimeObserver()
    }

    func seek(to time: Double) {
        guard let state = videoState, state.duration > 0 else { return }
        let position = Float(time / state.duration)
        mediaPlayer?.perform(Selector(("setPosition:")), with: NSNumber(value: position))
    }

    func seekToFrame(_ frame: Int) {
        guard let state = videoState else { return }
        let time = Double(frame) / state.frameRate
        seek(to: time)
    }

    func stepFrame(forward: Bool, amount: Int) {
        guard let state = videoState else { return }
        pause()
        state.isPlaying = false

        let delta = forward ? amount : -amount
        let newFrame = max(0, min(state.totalFrames - 1, state.currentFrame + delta))
        seekToFrame(newFrame)
    }

    func setVolume(_ volume: Int) {
        let selector = Selector(("audio"))
        guard let audio = mediaPlayer?.perform(selector)?.takeUnretainedValue() as? NSObject else { return }
        audio.perform(Selector(("setVolume:")), with: NSNumber(value: volume))
    }

    // MARK: - Time Observer

    private func startTimeObserver() {
        stopTimeObserver()
        timeObserverTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.updateTimeFromPlayer()
        }
    }

    private func stopTimeObserver() {
        timeObserverTimer?.invalidate()
        timeObserverTimer = nil
    }

    private func updateTimeFromPlayer() {
        guard let mediaPlayer = mediaPlayer,
              let state = videoState else { return }

        // Get position (0.0 to 1.0)
        if let positionValue = mediaPlayer.value(forKey: "position") as? Float {
            let currentTime = Double(positionValue) * state.duration
            if currentTime.isFinite {
                state.currentTime = currentTime
                state.currentFrame = Int(currentTime * state.frameRate)
            }
        }
    }

    // MARK: - Notifications

    @objc private func mediaPlayerStateChanged(_ notification: Notification) {
        guard let state = videoState else { return }

        // Get state value
        if let stateValue = mediaPlayer?.value(forKey: "state") as? Int {
            // VLCMediaPlayerState: 0=stopped, 1=opening, 2=buffering, 3=playing, 4=paused, 5=ended, 6=error
            print("VLCVideoView: State changed to \(stateValue)")
            switch stateValue {
            case 0: // Stopped
                print("VLCVideoView: Stopped")
            case 1: // Opening
                print("VLCVideoView: Opening")
            case 2: // Buffering
                print("VLCVideoView: Buffering")
            case 3: // Playing
                print("VLCVideoView: Playing")
                state.isPlaying = true
                state.isVideoLoaded = true
                updateMediaInfo()
            case 4: // Paused
                print("VLCVideoView: Paused")
                state.isPlaying = false
            case 5: // Ended
                print("VLCVideoView: Ended")
                state.isPlaying = false
                state.currentTime = 0
                state.currentFrame = 0
            case 6: // Error
                print("VLCVideoView: Error state")
                state.isVideoLoaded = false
            default:
                print("VLCVideoView: Unknown state \(stateValue)")
                break
            }
        }
    }

    @objc private func mediaPlayerTimeChanged(_ notification: Notification) {
        updateTimeFromPlayer()
    }

    private func updateMediaInfo() {
        guard let mediaPlayer = mediaPlayer,
              let state = videoState else { return }

        // Get media
        guard let media = mediaPlayer.value(forKey: "media") as? NSObject else { return }

        // Get duration
        if let lengthObj = media.perform(Selector(("length")))?.takeUnretainedValue() as? NSObject,
           let intValue = lengthObj.value(forKey: "intValue") as? Int {
            let durationSeconds = Double(intValue) / 1000.0
            state.duration = durationSeconds
            state.totalFrames = Int(durationSeconds * state.frameRate)
        }

        if let info = extractVideoInfo(from: media) {
            if let size = info.size, size != .zero {
                state.videoNaturalSize = size
            } else if state.videoNaturalSize == .zero {
                state.videoNaturalSize = CGSize(width: 1920, height: 1080)
            }
            if let fps = info.fps, fps > 0 {
                state.frameRate = fps
                state.totalFrames = Int(state.duration * fps)
            }
        } else if state.videoNaturalSize == .zero {
            state.videoNaturalSize = CGSize(width: 1920, height: 1080)
        }
    }

    private func extractVideoInfo(from media: NSObject) -> (size: CGSize?, fps: Double?)? {
        // Try tracksInformation first (older VLCKit API)
        if let infos = media.value(forKey: "tracksInformation") as? [[String: Any]] {
            for info in infos {
                let width = info["width"] as? Int ?? info["videoWidth"] as? Int
                let height = info["height"] as? Int ?? info["videoHeight"] as? Int
                let fpsValue = info["frameRate"] as? Double ?? info["fps"] as? Double
                if let width = width, let height = height, width > 0, height > 0 {
                    return (CGSize(width: width, height: height), fpsValue)
                }
            }
        }

        // Try tracks array (newer VLCKit API)
        if let tracks = media.value(forKey: "tracks") as? [NSObject] {
            for track in tracks {
                let width = track.value(forKey: "videoWidth") as? Int ?? track.value(forKey: "width") as? Int
                let height = track.value(forKey: "videoHeight") as? Int ?? track.value(forKey: "height") as? Int
                var fps: Double?
                if let fpsValue = track.value(forKey: "frameRate") as? Double {
                    fps = fpsValue
                } else if let num = track.value(forKey: "frameRateNum") as? Double,
                          let den = track.value(forKey: "frameRateDen") as? Double,
                          den != 0 {
                    fps = num / den
                }
                if let width = width, let height = height, width > 0, height > 0 {
                    return (CGSize(width: width, height: height), fps)
                }
            }
        }

        return nil
    }

    // MARK: - Cleanup

    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }
}
