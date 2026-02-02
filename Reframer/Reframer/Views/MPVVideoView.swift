import Cocoa
import Combine
import os.log
import Darwin

/// Video view that uses libmpv for playback (dynamically loaded)
final class MPVVideoView: NSOpenGLView {

    // MARK: - Debug Logging

    private static let debugLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.reframer", category: "MPVVideoView")

    private func mpvLog(_ message: String) {
        os_log("%{public}@", log: Self.debugLog, type: .debug, message)
        print("MPVVideoView: \(message)")
    }

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()
    private var mpvHandle: mpv_handle?
    private var renderContext: mpv_render_context?
    private var glModule: UnsafeMutableRawPointer?
    private var timeObserverTimer: Timer?
    private var isStopped = false
    private var eventQueue = DispatchQueue(label: "com.reframer.mpv.events")

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if let format = MPVVideoView.makePixelFormat() {
            pixelFormat = format
            openGLContext = NSOpenGLContext(format: format, share: nil)
        }
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let format = MPVVideoView.makePixelFormat() {
            pixelFormat = format
            if openGLContext == nil {
                openGLContext = NSOpenGLContext(format: format, share: nil)
            }
        }
        setupView()
    }

    private static func makePixelFormat() -> NSOpenGLPixelFormat? {
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            0
        ]
        return NSOpenGLPixelFormat(attributes: attrs)
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        wantsBestResolutionOpenGLSurface = true
    }

    override var isOpaque: Bool { false }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        openGLContext?.makeCurrentContext()
    }

    override func reshape() {
        super.reshape()
        openGLContext?.update()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        renderFrame()
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

        state.seekRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                switch request {
                case .time(let time, let accurate):
                    self?.seek(to: time, accurate: accurate)
                case .frame(let frame):
                    self?.seekToFrame(frame)
                }
            }
            .store(in: &cancellables)

        state.frameStepRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                let forward = request.direction == .forward
                self?.stepFrame(forward: forward, amount: request.amount)
            }
            .store(in: &cancellables)
    }

    // MARK: - Video Loading

    func loadVideo(url: URL) {
        isStopped = false
        guard setupMPV() else {
            showVideoLoadError("libmpv is not available. Install MPV in Preferences.")
            return
        }

        guard let state = videoState else { return }

        // Reset state
        state.currentTime = 0
        state.currentFrame = 0
        state.duration = 0
        state.totalFrames = 0
        state.isVideoLoaded = false

        if state.videoTitle == nil {
            state.videoTitle = url.lastPathComponent
        }

        let result = mpvCommand(["loadfile", url.path, "replace"])
        if result < 0 {
            showVideoLoadError("MPV failed to load file: \(MPVLibrary.shared.errorString(result))")
            return
        }

        setVolume(Int(state.volume * 100))
        if state.isPlaying {
            play()
        } else {
            pause()
        }
        startTimeObserver()
    }

    /// Load a YouTube video with optional separate audio stream and HTTP headers
    func loadYouTubeVideo(videoURL: URL, audioURL: URL?, headers: [String: String]?) {
        isStopped = false
        guard setupMPV() else {
            showVideoLoadError("libmpv is not available. Install MPV in Preferences.")
            return
        }

        guard let state = videoState else { return }

        // Reset state
        state.currentTime = 0
        state.currentFrame = 0
        state.duration = 0
        state.totalFrames = 0
        state.isVideoLoaded = false

        // Configure network options for streaming
        setOption("cache", "yes")
        setOption("cache-secs", "30")
        setOption("demuxer-max-bytes", "50MiB")
        setOption("demuxer-max-back-bytes", "20MiB")

        // Set HTTP headers if provided (required for YouTube DASH streams)
        if let headers = headers {
            let headerStrings = headers.map { "\($0.key): \($0.value)" }
            let joinedHeaders = headerStrings.joined(separator: "\r\n")
            setOption("http-header-fields", joinedHeaders)
            mpvLog("Set HTTP headers: \(headerStrings)")
        }

        // Set separate audio track if provided (for YouTube separate video/audio streams)
        if let audioURL = audioURL {
            setOption("audio-file", audioURL.absoluteString)
            mpvLog("Set audio file: \(audioURL.absoluteString.prefix(80))...")
        }

        let result = mpvCommand(["loadfile", videoURL.absoluteString, "replace"])
        if result < 0 {
            showVideoLoadError("MPV failed to load stream: \(MPVLibrary.shared.errorString(result))")
            return
        }

        mpvLog("Loading YouTube stream: \(videoURL.absoluteString.prefix(80))...")

        setVolume(Int(state.volume * 100))
        if state.isPlaying {
            play()
        } else {
            pause()
        }
        startTimeObserver()
    }

    // MARK: - Playback Control

    func play() {
        setPause(false)
    }

    func pause() {
        setPause(true)
    }

    func stop() {
        isStopped = true
        _ = mpvCommand(["stop"])
        stopTimeObserver()
    }

    func seek(to time: Double, accurate: Bool) {
        guard let state = videoState, state.duration > 0 else { return }
        let clamped = max(0, min(state.duration, time))
        let mode = accurate ? "absolute+exact" : "absolute"
        _ = mpvCommand(["seek", String(format: "%.6f", clamped), mode])
    }

    func seekToFrame(_ frame: Int) {
        guard let state = videoState else { return }
        let time = Double(frame) / state.frameRate
        seek(to: time, accurate: true)
    }

    func stepFrame(forward: Bool, amount: Int) {
        guard amount > 0 else { return }
        pause()
        videoState?.isPlaying = false

        let command = forward ? "frame-step" : "frame-back-step"
        for _ in 0..<amount {
            _ = mpvCommand([command])
        }
    }

    func setVolume(_ volume: Int) {
        var value = Double(max(0, min(100, volume)))
        _ = withUnsafeMutablePointer(to: &value) { ptr in
            "volume".withCString { name in
                MPVLibrary.shared.mpv_set_property(mpvHandle, name, MPVFormat.double, UnsafeMutableRawPointer(ptr))
            }
        }
    }

    // MARK: - MPV Setup

    private func setupMPV() -> Bool {
        if mpvHandle != nil { return true }

        if !MPVManager.shared.isReady {
            MPVManager.shared.loadLibrary()
        }

        guard MPVManager.shared.isReady else { return false }
        let library = MPVLibrary.shared

        guard let handle = library.mpv_create() else {
            mpvLog("mpv_create failed")
            return false
        }
        mpvHandle = handle

        applyMPVOptions()

        let initResult = library.mpv_initialize(handle)
        if initResult < 0 {
            mpvLog("mpv_initialize failed: \(library.errorString(initResult))")
            return false
        }

        setupRenderContext()
        setupWakeupCallback()
        return true
    }

    private func applyMPVOptions() {
        setOption("vo", "libmpv")
        setOption("hwdec", "videotoolbox")
        setOption("gpu-api", "opengl")
        setOption("hr-seek", "yes")
        setOption("hr-seek-framedrop", "no")
        setOption("keep-open", "yes")
        setOption("osd-level", "0")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard", "no")
    }

    private func setOption(_ name: String, _ value: String) {
        _ = name.withCString { namePtr in
            value.withCString { valuePtr in
                MPVLibrary.shared.mpv_set_option_string(mpvHandle, namePtr, valuePtr)
            }
        }
    }

    private func setupRenderContext() {
        guard let handle = mpvHandle else { return }
        openGLContext?.makeCurrentContext()

        if glModule == nil {
            glModule = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_NOW)
        }

        guard let glModule = glModule else {
            mpvLog("OpenGL framework not available")
            return
        }

        var initParams = mpv_opengl_init_params(
            get_proc_address: MPVVideoView.getProcAddress,
            get_proc_address_ctx: glModule
        )

        var ctx: mpv_render_context?
        let result: Int32 = "opengl".withCString { apiType in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPVRenderParamType.apiType, data: UnsafeMutableRawPointer(mutating: apiType)),
                mpv_render_param(type: MPVRenderParamType.openglInitParams, data: UnsafeMutableRawPointer(&initParams)),
                mpv_render_param(type: MPVRenderParamType.invalid, data: nil)
            ]
            return params.withUnsafeBufferPointer { buffer in
                let rawParams = buffer.baseAddress.map { UnsafeRawPointer($0) }
                return MPVLibrary.shared.mpv_render_context_create(&ctx, handle, rawParams)
            }
        }
        if result < 0 {
            mpvLog("mpv_render_context_create failed: \(MPVLibrary.shared.errorString(result))")
            return
        }
        renderContext = ctx

        MPVLibrary.shared.mpv_render_context_set_update_callback(
            renderContext,
            MPVVideoView.renderUpdateCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    private func setupWakeupCallback() {
        MPVLibrary.shared.mpv_set_wakeup_callback(
            mpvHandle,
            MPVVideoView.wakeupCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    // MARK: - MPV Rendering

    private func renderFrame() {
        guard let renderContext = renderContext else { return }
        openGLContext?.makeCurrentContext()

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        let width = Int32(bounds.width * scale)
        let height = Int32(bounds.height * scale)

        var fbo = mpv_opengl_fbo(fbo: 0, w: width, h: height, internal_format: 0)
        var flipY: Int32 = 1

        var params: [mpv_render_param] = [
            mpv_render_param(type: MPVRenderParamType.openglFBO, data: UnsafeMutableRawPointer(&fbo)),
            mpv_render_param(type: MPVRenderParamType.flipY, data: UnsafeMutableRawPointer(&flipY)),
            mpv_render_param(type: MPVRenderParamType.invalid, data: nil)
        ]

        params.withUnsafeBufferPointer { buffer in
            let rawParams = buffer.baseAddress.map { UnsafeRawPointer($0) }
            MPVLibrary.shared.mpv_render_context_render(renderContext, rawParams)
        }
        openGLContext?.flushBuffer()
    }

    private static let getProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { ctx, name in
        guard let ctx = ctx, let name = name else { return nil }
        return dlsym(ctx, name)
    }

    private static let renderUpdateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
        guard let ctx = ctx else { return }
        let view = Unmanaged<MPVVideoView>.fromOpaque(ctx).takeUnretainedValue()
        DispatchQueue.main.async {
            view.needsDisplay = true
        }
    }

    private static let wakeupCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
        guard let ctx = ctx else { return }
        let view = Unmanaged<MPVVideoView>.fromOpaque(ctx).takeUnretainedValue()
        view.handleWakeup()
    }

    private func handleWakeup() {
        eventQueue.async { [weak self] in
            self?.drainEvents()
        }
    }

    private func drainEvents() {
        guard let handle = mpvHandle else { return }
        while true {
            guard let eventPtr = MPVLibrary.shared.mpv_wait_event(handle, 0) else { break }
            let event = eventPtr.assumingMemoryBound(to: mpv_event.self).pointee
            if event.event_id == 0 { break }
            guard let namePtr = MPVLibrary.shared.mpv_event_name(event.event_id) else { continue }
            let name = String(cString: namePtr)
            handleEvent(name: name, event: event)
        }
    }

    private func handleEvent(name: String, event: mpv_event) {
        switch name {
        case "file-loaded":
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let state = self.videoState else { return }
                state.isVideoLoaded = true
                self.updateMediaInfo()
                self.scheduleMetadataRefresh()
                if state.isPlaying {
                    self.play()
                }
            }
        case "end-file":
            DispatchQueue.main.async { [weak self] in
                guard let state = self?.videoState else { return }
                state.isPlaying = false
                state.currentTime = 0
                state.currentFrame = 0
            }
        case "shutdown":
            DispatchQueue.main.async { [weak self] in
                self?.videoState?.isVideoLoaded = false
            }
        case "log-message":
            break
        default:
            break
        }
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
        guard let state = videoState else { return }
        guard let time = getDoubleProperty("time-pos") else { return }
        if time.isFinite {
            state.currentTime = time
            state.currentFrame = Int(time * state.frameRate)
        }
    }

    private func updateMediaInfo() {
        guard let state = videoState else { return }

        if let duration = getDoubleProperty("duration"), duration.isFinite {
            state.duration = duration
        }

        if let fps = getDoubleProperty("container-fps"), fps > 0 {
            state.frameRate = fps
        } else if let fps = getDoubleProperty("fps"), fps > 0 {
            state.frameRate = fps
        } else if let fps = getDoubleProperty("estimated-vf-fps"), fps > 0 {
            state.frameRate = fps
        }

        if let width = getIntProperty("width"), let height = getIntProperty("height"), width > 0, height > 0 {
            state.videoNaturalSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        } else if let dwidth = getDoubleProperty("dwidth"), let dheight = getDoubleProperty("dheight"), dwidth > 0, dheight > 0 {
            state.videoNaturalSize = CGSize(width: dwidth, height: dheight)
        }

        if state.frameRate > 0 && state.duration > 0 {
            let estimated = (state.frameRate * state.duration).rounded()
            state.totalFrames = Int(max(0, estimated))
        }
    }

    private func scheduleMetadataRefresh(retries: Int = 3) {
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self, let state = self.videoState else { return }
            self.updateMediaInfo()
            let needsRefresh = state.duration <= 0 || state.frameRate <= 0 || state.videoNaturalSize == .zero
            if needsRefresh {
                self.scheduleMetadataRefresh(retries: retries - 1)
            }
        }
    }

    private func getDoubleProperty(_ name: String) -> Double? {
        guard let handle = mpvHandle else { return nil }
        var value = Double(0)
        let result = withUnsafeMutablePointer(to: &value) { ptr -> Int32 in
            return name.withCString { namePtr in
                MPVLibrary.shared.mpv_get_property(handle, namePtr, MPVFormat.double, UnsafeMutableRawPointer(ptr))
            }
        }
        return result >= 0 ? value : nil
    }

    private func getIntProperty(_ name: String) -> Int? {
        guard let handle = mpvHandle else { return nil }
        var value = Int64(0)
        let result = withUnsafeMutablePointer(to: &value) { ptr -> Int32 in
            return name.withCString { namePtr in
                MPVLibrary.shared.mpv_get_property(handle, namePtr, MPVFormat.int64, UnsafeMutableRawPointer(ptr))
            }
        }
        return result >= 0 ? Int(value) : nil
    }

    private func setPause(_ pause: Bool) {
        var flag: Int32 = pause ? 1 : 0
        _ = withUnsafeMutablePointer(to: &flag) { ptr in
            "pause".withCString { name in
                MPVLibrary.shared.mpv_set_property(mpvHandle, name, MPVFormat.flag, UnsafeMutableRawPointer(ptr))
            }
        }
    }

    private func mpvCommand(_ args: [String]) -> Int32 {
        guard let handle = mpvHandle else { return -1 }
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cStrings.append(nil)
        defer {
            for ptr in cStrings {
                if let ptr = ptr {
                    free(ptr)
                }
            }
        }
        return cStrings.withUnsafeBufferPointer { buffer in
            let raw = buffer.baseAddress.map { UnsafeRawPointer($0) }
            let casted = raw?.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
            return MPVLibrary.shared.mpv_command(handle, casted)
        }
    }

    // MARK: - Cleanup

    deinit {
        stop()
        if let renderContext = renderContext {
            MPVLibrary.shared.mpv_render_context_free(renderContext)
        }
        if let handle = mpvHandle {
            MPVLibrary.shared.mpv_terminate_destroy(handle)
        }
        if let glModule = glModule {
            dlclose(glModule)
        }
    }

    private func showVideoLoadError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            // Suppress error alerts if playback was intentionally stopped
            if self?.isStopped == true { return }
            let alert = NSAlert()
            alert.messageText = "Playback Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let window = self?.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
}
