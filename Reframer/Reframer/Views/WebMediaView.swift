import Cocoa
import Combine
import WebKit

enum WebMediaSource: Equatable {
    case localWebM(URL)
    case youtube(YouTubePlaybackAuthorization)

    var displayName: String {
        switch self {
        case .localWebM(let url):
            return url.lastPathComponent
        case .youtube:
            return "YouTube video"
        }
    }

    var isYouTube: Bool {
        if case .youtube = self {
            return true
        }
        return false
    }
}

struct YouTubeVideoReference: Equatable {
    static let qualityDisclosure =
        "YouTube automatically selects the highest quality appropriate for the player size, display, and connection. Its supported embed API does not let Reframer force a specific quality level."

    let videoID: String
    let canonicalURL: URL

    static func parse(_ input: String) -> YouTubeVideoReference? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              let rawHost = components.host?.lowercased() else {
            return nil
        }

        let host: String
        switch rawHost {
        case "www.youtube.com", "m.youtube.com", "music.youtube.com":
            host = "youtube.com"
        case "www.youtube-nocookie.com":
            host = "youtube-nocookie.com"
        default:
            host = rawHost
        }
        let pathSegments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        let videoID: String?
        switch host {
        case "youtu.be":
            videoID = pathSegments.count == 1 ? pathSegments[0] : nil
        case "youtube.com", "youtube-nocookie.com":
            switch pathSegments.first?.lowercased() {
            case "watch" where pathSegments.count == 1:
                let identifiers = components.queryItems?
                    .filter { $0.name.lowercased() == "v" }
                    .compactMap(\.value) ?? []
                videoID = identifiers.count == 1 ? identifiers[0] : nil
            case "shorts", "embed", "live":
                videoID = pathSegments.count == 2 ? pathSegments[1] : nil
            default:
                videoID = nil
            }
        default:
            videoID = nil
        }

        guard let videoID, isValidVideoID(videoID),
              let canonicalURL = URL(
                string: "https://www.youtube.com/watch?v=\(videoID)"
              ) else {
            return nil
        }
        return YouTubeVideoReference(
            videoID: videoID,
            canonicalURL: canonicalURL
        )
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        guard value.utf8.count == 11 else { return false }
        return value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57)
                || ($0 >= 65 && $0 <= 90)
                || ($0 >= 97 && $0 <= 122)
                || $0 == 95
                || $0 == 45
        }
    }
}

enum WebMediaHTML {
    static let youtubeBaseURL = URL(
        string: "https://com.reframer.app/"
    )!

    static func youtube(
        videoID: String,
        token: String,
        audience: YouTubeAudience = .general
    ) -> String {
        let generation = javascriptString(token)
        let audienceValue = audience == .madeForKids
            ? "made-for-kids"
            : "general"
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <meta name="reframer-audience" content="\(audienceValue)">
          <meta http-equiv="Content-Security-Policy"
                content="default-src 'none'; frame-src https://www.youtube.com https://www.youtube-nocookie.com; script-src https://www.youtube.com https://s.ytimg.com 'unsafe-inline'; img-src https://i.ytimg.com https://*.googleusercontent.com data:; connect-src https://www.youtube.com https://*.googlevideo.com https://*.google.com; media-src https://*.googlevideo.com blob:; style-src 'unsafe-inline'">
          <style>
            html, body, #player {
              width: 100%; height: 100%; margin: 0; overflow: hidden;
              background: #000;
            }
          </style>
        </head>
        <body>
          <iframe
            id="player"
            title="YouTube video player"
            width="100%"
            height="100%"
            frameborder="0"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen
            referrerpolicy="strict-origin-when-cross-origin"
            src="https://www.youtube-nocookie.com/embed/\(videoID)?enablejsapi=1&amp;origin=https%3A%2F%2Fcom.reframer.app&amp;autoplay=0&amp;controls=1&amp;playsinline=1">
          </iframe>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
          (() => {
            "use strict";
            const version = 1;
            const token = \(generation);
            let player = null;
            let timer = null;
            let pendingIntent = null;

            function emit(type, values = {}) {
              try {
                window.webkit.messageHandlers.reframerMedia.postMessage(
                  Object.assign({ version, type, token }, values)
                );
              } catch (_) {}
            }
            function finite(value, fallback = 0) {
              return Number.isFinite(value) ? value : fallback;
            }
            function acknowledgesPendingIntent(playerState, intent) {
              if (!intent) return false;
              if (intent.playerState === 1) return playerState === 1;
              return [-1, 0, 2, 5].includes(playerState);
            }
            function snapshot(type) {
              if (!player || typeof player.getCurrentTime !== "function") return;
              const playerState = player.getPlayerState();
              let commandRevision = null;
              let pendingRevision = null;
              if (pendingIntent) {
                if (acknowledgesPendingIntent(playerState, pendingIntent)) {
                  commandRevision = pendingIntent.revision;
                  pendingIntent = null;
                } else {
                  pendingRevision = pendingIntent.revision;
                }
              }
              emit(type, {
                currentTime: finite(player.getCurrentTime()),
                duration: finite(player.getDuration()),
                playerState,
                volume: finite(player.getVolume()) / 100,
                muted: Boolean(player.isMuted()),
                commandRevision,
                pendingRevision
              });
            }

            window.onYouTubeIframeAPIReady = () => {
              player = new YT.Player("player", {
                events: {
                  onReady: () => {
                    snapshot("ready");
                    timer = window.setInterval(() => snapshot("time"), 250);
                  },
                  onStateChange: event => {
                    const names = {
                      "-1": "unstarted",
                      "0": "ended",
                      "1": "playing",
                      "2": "paused",
                      "3": "buffering",
                      "5": "cued"
                    };
                    snapshot(names[String(event.data)] || "state");
                  },
                  onError: event => emit("error", {
                    code: event.data
                  }),
                  onAutoplayBlocked: () => emit("autoplayBlocked")
                }
              });
            };

            window.reframerMedia = {
              play(revision) {
                if (!player) return;
                pendingIntent = {
                  revision: String(revision),
                  playerState: 1
                };
                player.playVideo();
                snapshot("state");
              },
              pause(revision) {
                if (!player) return;
                pendingIntent = {
                  revision: String(revision),
                  playerState: 2
                };
                player.pauseVideo();
                snapshot("state");
              },
              seek(seconds, allowSeekAhead) {
                if (!player || !Number.isFinite(seconds)) return;
                const duration = finite(player.getDuration(), seconds);
                player.seekTo(
                  Math.max(0, Math.min(duration, seconds)),
                  Boolean(allowSeekAhead)
                );
                snapshot("time");
              },
              setVolume(value) {
                if (player && Number.isFinite(value)) {
                  player.setVolume(Math.max(0, Math.min(100, value * 100)));
                }
              },
              setMuted(value) {
                if (!player) return;
                value ? player.mute() : player.unMute();
              },
              destroy() {
                if (timer) window.clearInterval(timer);
                timer = null;
                pendingIntent = null;
                if (player && typeof player.destroy === "function") player.destroy();
                player = null;
              }
            };
          })();
          </script>
        </body>
        </html>
        """
    }

    private static func javascriptString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private enum WebPlayerState: Int {
    case unstarted = -1
    case ended = 0
    case playing = 1
    case paused = 2
    case buffering = 3
    case cued = 5
}

enum WebMediaAudioReconciliationPolicy {
    static func shouldReconcile(messageType: String) -> Bool {
        messageType != "ready"
    }

    static func shouldSetPlayerVolume(_ displayedVolume: Float) -> Bool {
        displayedVolume.isFinite && displayedVolume > 0
    }
}

enum WebMediaVisibilityPolicy {
    static func shouldPause(isYouTube: Bool, isPlaying: Bool) -> Bool {
        isYouTube && isPlaying
    }
}

private enum YouTubePlayerError {
    static func message(for code: Int?) -> String {
        switch code {
        case 2:
            return "YouTube rejected the video identifier."
        case 5:
            return "The YouTube HTML5 player could not start this video."
        case 100:
            return "This YouTube video is private, deleted, or unavailable."
        case 101, 150:
            return "The video owner does not allow this YouTube video to be embedded."
        case 153:
            return "YouTube rejected Reframer’s player identity. The app’s Referer configuration needs repair."
        default:
            return "YouTube could not play this video."
        }
    }
}

struct WebMediaGenerationGate {
    private(set) var token: String?

    mutating func begin(token: String = UUID().uuidString) -> String {
        self.token = token
        return token
    }

    mutating func invalidate() {
        token = nil
    }

    func accepts(_ candidate: String) -> Bool {
        token != nil && token == candidate
    }
}

/// Coalesces uncancellable asynchronous work to its newest requested value.
/// A request submitted while work is active is covered by that in-flight
/// operation and replaces any older pending value.
struct LatestValueOperationGate<Value> {
    private(set) var isRunning = false
    private var latestValue: Value?

    mutating func submit(_ value: Value) -> Bool {
        latestValue = value
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    mutating func complete() -> Value? {
        guard isRunning else { return nil }
        isRunning = false
        defer { latestValue = nil }
        return latestValue
    }

    mutating func cancelPending() {
        latestValue = nil
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(
            userContentController,
            didReceive: message
        )
    }
}

/// Coordinates WebM preparation and hosts policy-compliant YouTube embeds.
/// Prepared WebM files transition into the normal AVFoundation transport;
/// only YouTube remains in this view for playback.
final class WebMediaView:
    NSView,
    WKScriptMessageHandler,
    WKNavigationDelegate,
    WKUIDelegate
{
    private static let messageHandlerName = "reframerMedia"

    private struct PendingYouTubeLoad {
        let authorization: YouTubePlaybackAuthorization
        let token: String
        let state: VideoState
    }

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private let webView: WKWebView
    private let messageProxy = WeakScriptMessageHandler()
    private var source: WebMediaSource?
    private var generationGate = WebMediaGenerationGate()
    private var preparationSession: WebMPreparationSession?
    private var cancellables = Set<AnyCancellable>()
    private var readyTimeoutWorkItem: DispatchWorkItem?
    private var websiteDataClearGate =
        LatestValueOperationGate<PendingYouTubeLoad>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isReconcilingPlayerAudio = false

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.messageHandlerName
        )
        cleanup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityIdentifier("web-media-view")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setAccessibilityIdentifier("web-media-player")
        addSubview(webView)

        messageProxy.delegate = self
        webView.configuration.userContentController.add(
            messageProxy,
            name: Self.messageHandlerName
        )

        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  notification.object as? NSWindow === self.window,
                  self.source?.isYouTube == true else {
                return
            }
            self.pauseYouTubeForVisibility()
        })
        notificationObservers.append(center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  notification.object as? NSWindow === self.window,
                  self.window?.occlusionState.contains(.visible) != true else {
                return
            }
            self.pauseYouTubeForVisibility()
        })
        for name in [
            NSApplication.didHideNotification,
            NSApplication.willTerminateNotification
        ] {
            notificationObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.pauseYouTubeForVisibility()
            })
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ] {
            workspaceObservers.append(workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.pauseYouTubeForVisibility()
            })
        }
    }

    private func pauseYouTubeForVisibility() {
        guard let state = videoState,
              WebMediaVisibilityPolicy.shouldPause(
                isYouTube: source?.isYouTube == true,
                isPlaying: state.isPlaying
              ) else {
            return
        }
        _ = state.setPlaybackIntent(false)
    }

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        state.$webMediaSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                self?.load(source)
            }
            .store(in: &cancellables)

        state.$isPlaying
            .sink { [weak self, weak state] isPlaying in
                guard let self, let state else { return }
                let revision = String(state.playbackIntentRevision)
                self.call(
                    isPlaying
                        ? "play(\"\(revision)\")"
                        : "pause(\"\(revision)\")"
                )
            }
            .store(in: &cancellables)

        state.$volume
            .sink { [weak self] volume in
                precondition(Thread.isMainThread)
                guard let self,
                      !self.isReconcilingPlayerAudio,
                      WebMediaAudioReconciliationPolicy
                        .shouldSetPlayerVolume(volume) else {
                    return
                }
                self.call("setVolume(\(Double(volume)))")
            }
            .store(in: &cancellables)

        state.$isMuted
            .sink { [weak self] muted in
                precondition(Thread.isMainThread)
                guard let self, !self.isReconcilingPlayerAudio else {
                    return
                }
                self.call("setMuted(\(muted ? "true" : "false"))")
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(state.$zoomScale, state.$panOffset)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.needsLayout = true }
            .store(in: &cancellables)

        state.seekRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                guard let self else { return }
                switch request {
                case .time(let time, _):
                    self.seek(to: time, allowSeekAhead: true)
                case .frame:
                    break
                }
            }
            .store(in: &cancellables)

        state.frameStepRequests
            .receive(on: DispatchQueue.main)
            .sink { _ in }
            .store(in: &cancellables)

        state.scrubRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                guard let self, let state = self.videoState else { return }
                let revision = String(state.playbackIntentRevision)
                switch request {
                case .began:
                    self.call("pause(\"\(revision)\")")
                case .preview(let time):
                    self.seek(to: time, allowSeekAhead: false)
                case .ended(let time):
                    self.seek(to: time, allowSeekAhead: true)
                    if state.isPlaying {
                        self.call("play(\"\(revision)\")")
                    }
                case .cancelled:
                    if state.isPlaying {
                        self.call("play(\"\(revision)\")")
                    }
                }
            }
            .store(in: &cancellables)

        state.reloadRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak state] in
                guard let source = state?.webMediaSource,
                      !source.isYouTube else {
                    return
                }
                self?.load(source)
            }
            .store(in: &cancellables)
    }

    private func load(_ newSource: WebMediaSource?) {
        guard newSource != source || newSource != nil else { return }
        cleanup()
        source = newSource
        guard let newSource, let state = videoState else {
            needsLayout = true
            return
        }

        let token = generationGate.begin()
        state.cancelScrubbing()
        state.setPlaybackIntent(false)
        state.isVideoLoaded = false
        state.isVideoLoading = true
        state.videoErrorMessage = nil
        state.filterErrorMessage = nil
        state.isAtEnd = false
        state.currentTime = 0
        state.currentFrame = 0
        state.duration = 0
        state.totalFrames = 0
        state.frameNavigationPrecision = .unavailable
        state.frameNavigationMessage = nil
        if newSource.isYouTube {
            state.frameRate = 0
        }
        state.videoNaturalSize = newSource.isYouTube
            ? CGSize(width: 16, height: 9)
            : .zero

        switch newSource {
        case .localWebM(let url):
            prepareWebM(url, token: token, state: state)
        case .youtube(let authorization):
            webView.underPageBackgroundColor = .black
            loadYouTube(
                authorization,
                token: token,
                state: state
            )
        }
        needsLayout = true
    }

    private func loadYouTube(
        _ authorization: YouTubePlaybackAuthorization,
        token: String,
        state: VideoState
    ) {
        let shouldStartClear = websiteDataClearGate.submit(
            PendingYouTubeLoad(
                authorization: authorization,
                token: token,
                state: state
            )
        )
        guard shouldStartClear else {
            return
        }

        // Start every embed with an empty ephemeral store. This applies the
        // stricter no-retained-tracking posture to all videos, including those
        // identified as Made for Kids, and prevents one player from inheriting
        // another player's cookies or local storage. Clears are serialized so
        // an obsolete generation can never erase storage underneath a newer
        // player load.
        let dataStore = webView.configuration.websiteDataStore
        dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let pending = self.websiteDataClearGate.complete() else {
                    return
                }

                guard
                      self.generationGate.accepts(pending.token),
                      self.source == .youtube(pending.authorization),
                      pending.state.isVideoLoading else {
                    return
                }
                self.scheduleReadyTimeout(
                    token: pending.token,
                    state: pending.state
                )
                self.webView.loadHTMLString(
                    WebMediaHTML.youtube(
                        videoID:
                            pending.authorization.reference.videoID,
                        token: pending.token,
                        audience: pending.authorization.audience
                    ),
                    baseURL: WebMediaHTML.youtubeBaseURL
                )
            }
        }
    }

    private func cleanup() {
        readyTimeoutWorkItem?.cancel()
        readyTimeoutWorkItem = nil
        websiteDataClearGate.cancelPending()
        generationGate.invalidate()
        preparationSession?.cancel()
        preparationSession = nil
        call("destroy()")
        webView.stopLoading()
        source = nil
    }

    func shutdown() {
        let activePreparation = preparationSession
        preparationSession = nil
        activePreparation?.cancelAndWait()
        cleanup()
    }

    private func scheduleReadyTimeout(
        token: String,
        state: VideoState
    ) {
        readyTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state,
                  self.generationGate.accepts(token),
                  self.source?.isYouTube == true,
                  state.isVideoLoading else {
                return
            }
            self.fail(
                "The YouTube player did not become ready. Check your connection, then reload the video.",
                state: state
            )
        }
        readyTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 20,
            execute: workItem
        )
    }

    private func prepareWebM(
        _ url: URL,
        token: String,
        state: VideoState
    ) {
        let session = WebMPreparationSession(inputURL: url)
        preparationSession = session
        session.start { [weak self, weak state, weak session] result in
            guard let self, let state, let session,
                  self.generationGate.accepts(token),
                  self.preparationSession === session else {
                if case .success(let staleURL) = result {
                    try? FileManager.default.removeItem(at: staleURL)
                }
                return
            }
            self.preparationSession = nil
            switch result {
            case .success(let preparedURL):
                state.activatePreparedWebM(preparedURL)
            case .failure(let error):
                guard (error as? WebMPreparationError) != .cancelled else {
                    return
                }
                self.fail(error.localizedDescription, state: state)
            }
        }
    }

    private func call(_ expression: String) {
        guard source != nil else { return }
        webView.evaluateJavaScript(
            "window.reframerMedia && window.reframerMedia.\(expression)",
            completionHandler: nil
        )
    }

    private func seek(
        to time: Double,
        allowSeekAhead: Bool
    ) {
        guard time.isFinite else { return }
        call(
            "seek(\(max(0, time)), \(allowSeekAhead ? "true" : "false"))"
        )
    }

    override func layout() {
        super.layout()
        // Keep the official player viewport at the full canvas size. YouTube
        // owns its internal aspect fit and letterboxing; shrinking WKWebView
        // itself for vertical media can violate the 200-by-200 minimum player
        // size and make standard controls unusable.
        webView.frame = bounds
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageHandlerName,
              message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "com.reframer.app",
              [0, 443].contains(message.frameInfo.securityOrigin.port),
              let values = message.body as? [String: Any],
              (values["version"] as? NSNumber)?.intValue == 1,
              let messageToken = values["token"] as? String,
              generationGate.accepts(messageToken),
              let type = values["type"] as? String,
              let state = videoState,
              source?.isYouTube == true else {
            return
        }

        let currentTime = number(values["currentTime"])
        let duration = number(values["duration"])
        let commandRevision = (values["commandRevision"] as? String)
            .flatMap(UInt64.init)
        let pendingRevision = (values["pendingRevision"] as? String)
            .flatMap(UInt64.init)
        let playerVolume = number(values["volume"])
        let playerMuted = (values["muted"] as? NSNumber)?.boolValue

        switch type {
        case "ready":
            readyTimeoutWorkItem?.cancel()
            readyTimeoutWorkItem = nil
            if let width = number(values["width"]),
               let height = number(values["height"]),
               width > 0, height > 0 {
                state.videoNaturalSize = CGSize(width: width, height: height)
            }
            updateTime(
                currentTime: currentTime,
                duration: duration,
                state: state
            )
            state.frameNavigationPrecision = .unavailable
            state.frameNavigationMessage =
                "YouTube playback is time-based; frame stepping is unavailable."
            state.isVideoLoading = false
            state.isVideoLoaded = true
            state.videoErrorMessage = nil
            call(
                "setVolume(\(Double(state.playerVolumeWhenUnmuted)))"
            )
            call("setMuted(\(state.isMuted ? "true" : "false"))")
        case "time", "frame", "buffering", "cued", "unstarted", "state":
            updateTime(
                currentTime: currentTime,
                duration: duration,
                state: state
            )
        case "playing":
            updateTime(
                currentTime: currentTime,
                duration: duration,
                state: state
            )
        case "paused":
            updateTime(
                currentTime: currentTime,
                duration: duration,
                state: state
            )
        case "ended":
            updateTime(
                currentTime: currentTime ?? duration,
                duration: duration,
                state: state
            )
            state.isAtEnd = true
        case "autoplayBlocked":
            state.frameNavigationMessage =
                "Playback was blocked by the embedded player. Press Play again or use the YouTube player control."
            reconcilePlaybackIntent(false, state: state)
        case "error":
            let code = (values["code"] as? NSNumber)?.intValue
            fail(YouTubePlayerError.message(for: code), state: state)
        default:
            break
        }

        if WebMediaAudioReconciliationPolicy.shouldReconcile(
            messageType: type
        ), let playerVolume, let playerMuted {
            isReconcilingPlayerAudio = true
            state.reconcileExternalAudio(
                volume: playerVolume,
                isMuted: playerMuted
            )
            isReconcilingPlayerAudio = false
        }

        if let rawState = (values["playerState"] as? NSNumber)?.intValue,
           let playerState = WebPlayerState(rawValue: rawState) {
            reconcilePlayerState(
                playerState,
                commandRevision: commandRevision,
                pendingRevision: pendingRevision,
                state: state
            )
        }
    }

    private func updateTime(
        currentTime: Double?,
        duration: Double?,
        state: VideoState
    ) {
        if let duration, duration.isFinite, duration > 0 {
            state.duration = duration
            state.totalFrames = 0
        }
        if let currentTime, currentTime.isFinite, currentTime >= 0,
           !state.isScrubbing {
            state.currentTime = min(
                max(0, currentTime),
                state.duration > 0 ? state.duration : currentTime
            )
            state.currentFrame = 0
        }
    }

    private func reconcilePlayerState(
        _ playerState: WebPlayerState,
        commandRevision: UInt64?,
        pendingRevision: UInt64?,
        state: VideoState
    ) {
        if commandRevision == state.playbackIntentRevision
            || pendingRevision == state.playbackIntentRevision {
            return
        }
        switch playerState {
        case .playing:
            state.isAtEnd = false
            if !state.isPlaying {
                reconcilePlaybackIntent(true, state: state)
            }
        case .paused, .cued:
            guard state.isPlaying, !state.isScrubbing else { return }
            reconcilePlaybackIntent(false, state: state)
        case .ended:
            state.isAtEnd = true
            reconcilePlaybackIntent(false, state: state)
        case .unstarted, .buffering:
            break
        }
    }

    private func reconcilePlaybackIntent(_ shouldPlay: Bool, state: VideoState) {
        guard state.isPlaying != shouldPlay else { return }
        _ = state.setPlaybackIntent(shouldPlay)
    }

    private func fail(_ message: String, state: VideoState) {
        // A player failure is terminal for this generation. Invalidate the
        // bridge token and stop the page before changing visible state so a
        // late ready/time message cannot resurrect a failed player. The model
        // retains its source, allowing an explicit Reload to mint a new token.
        cleanup()
        state.cancelScrubbing()
        state.setPlaybackIntent(false)
        state.isVideoLoading = false
        state.isVideoLoaded = false
        state.isAtEnd = false
        state.currentTime = 0
        state.currentFrame = 0
        state.duration = 0
        state.totalFrames = 0
        state.frameNavigationPrecision = .unavailable
        state.frameNavigationMessage = nil
        state.videoNaturalSize = .zero
        state.videoErrorMessage = message
    }

    #if DEBUG
    var hasActivePlaybackGeneration: Bool {
        generationGate.token != nil
    }

    func beginPlaybackGenerationForTesting(token: String) {
        _ = generationGate.begin(token: token)
    }

    func failPlaybackGenerationForTesting(
        _ message: String,
        state: VideoState
    ) {
        fail(message, state: state)
    }
    #endif

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated {
            openExternallyIfSafe(navigationAction.request.url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            openExternallyIfSafe(navigationAction.request.url)
            decisionHandler(.cancel)
            return
        }
        guard navigationAction.targetFrame?.isMainFrame == true else {
            decisionHandler(
                isAllowedPlayerFrameURL(navigationAction.request.url)
                    ? .allow
                    : .cancel
            )
            return
        }

        let url = navigationAction.request.url
        let isSyntheticHostPage =
            url?.scheme == "about"
            || (
                url?.scheme == "https"
                && url?.host == WebMediaHTML.youtubeBaseURL.host
                && url?.path == WebMediaHTML.youtubeBaseURL.path
            )
        if navigationAction.navigationType == .other, isSyntheticHostPage {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated {
            openExternallyIfSafe(navigationAction.request.url)
        }
        return nil
    }

    private func openExternallyIfSafe(_ url: URL?) {
        guard let url, isValidatedExternalURL(url) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func isValidatedExternalURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }

    private func isAllowedPlayerFrameURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme == "about", url.absoluteString == "about:blank" {
            return true
        }
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else {
            return false
        }
        return [
            "youtube.com",
            "youtube-nocookie.com",
            "ytimg.com",
            "googlevideo.com",
            "google.com",
            "gstatic.com",
            "doubleclick.net",
            "googlesyndication.com"
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard let state = videoState,
              source != nil,
              state.isVideoLoading else {
            return
        }
        fail("The embedded player could not be loaded. \(error.localizedDescription)", state: state)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard let state = videoState,
              source?.isYouTube == true,
              state.isVideoLoading else {
            return
        }
        fail(
            "The embedded player stopped loading. \(error.localizedDescription)",
            state: state
        )
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let state = videoState,
              source?.isYouTube == true else {
            return
        }
        fail(
            "The YouTube player process stopped unexpectedly. Reload the video to try again.",
            state: state
        )
    }

}
