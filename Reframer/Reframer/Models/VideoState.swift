import Foundation
import AVFoundation
import Combine

class VideoState: ObservableObject {
    enum PlaybackEngine {
        case auto
        case avFoundation
        case vlc
    }

    enum SeekRequest: Equatable {
        case time(Double, accurate: Bool)
        case frame(Int)
    }

    enum FrameStepDirection: Equatable {
        case forward
        case backward
    }

    struct FrameStepRequest: Equatable {
        let direction: FrameStepDirection
        let amount: Int
    }

    // Video loading
    @Published var videoURL: URL?
    @Published var videoAudioURL: URL?
    @Published var videoHeaders: [String: String]?
    @Published var videoTitle: String?
    @Published var playbackEngine: PlaybackEngine = .auto
    @Published var isVideoLoaded: Bool = false

    // Playback
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentFrame: Int = 0
    @Published var totalFrames: Int = 0
    @Published var frameRate: Double = 30.0
    @Published var videoNaturalSize: CGSize = .zero

    // Volume
    @Published var volume: Float = 0.0 { didSet { handleVolumeChange(oldValue: oldValue) } }
    @Published var isMuted: Bool = true { didSet { handleMuteChange(oldValue: oldValue) } }

    // Zoom & Pan
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    // Opacity
    @Published var opacity: Double = 1.0 { didSet { persistDouble(opacity, key: DefaultsKeys.opacity) } }

    // Quick Filter (single filter from dropdown, controls toolbar slider)
    @Published var quickFilter: VideoFilter? = nil
    @Published var quickFilterValue: Double = 0.5  // 0-1 normalized value for toolbar slider

    // Advanced Filters (multiple filters from panel, stackable)
    @Published var advancedFilters: Set<VideoFilter> = []
    @Published var filterSettings: FilterSettings = .defaults
    @Published var showFilterPanel: Bool = false

    // Lock mode - disables pan/zoom gestures on video, controls remain active
    @Published var isLocked: Bool = false

    // Always on top
    @Published var isAlwaysOnTop: Bool = true { didSet { persistBool(isAlwaysOnTop, key: DefaultsKeys.alwaysOnTop) } }

    // Help
    @Published var showHelp: Bool = false

    // Requests
    let seekRequests = PassthroughSubject<SeekRequest, Never>()
    let frameStepRequests = PassthroughSubject<FrameStepRequest, Never>()

    @Published private(set) var lastSeekRequest: SeekRequest?
    @Published private(set) var lastFrameStepRequest: FrameStepRequest?

    private var isLoadingPreferences = false
    private var isAdjustingMute = false
    private var lastNonZeroVolume: Float = 0.5

    // Computed properties
    var zoomPercentage: Int {
        Int((zoomScale * 100).rounded())
    }

    var zoomPercentageValue: Double {
        Double(zoomScale * 100)
    }

    var opacityPercentage: Int {
        Int((opacity * 100).rounded())
    }

    var opacityPercentageValue: Double {
        opacity * 100
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    private enum DefaultsKeys {
        static let volume = "VideoOverlay.volume"
        static let lastVolume = "VideoOverlay.lastVolume"
        static let muted = "VideoOverlay.muted"
        static let opacity = "VideoOverlay.opacity"
        static let alwaysOnTop = "VideoOverlay.alwaysOnTop"
    }

    init() {
        isLoadingPreferences = true
        loadPreferences()
        isLoadingPreferences = false
    }

    // MARK: - Methods

    func resetView() {
        zoomScale = 1.0
        panOffset = .zero
    }

    func setZoomPercentage(_ percentage: Int) {
        setZoomPercentage(Double(percentage))
    }

    func setZoomPercentage(_ percentage: Double) {
        let clamped = max(10.0, min(1000.0, percentage))
        zoomScale = CGFloat(clamped / 100.0)
    }

    func setOpacityPercentage(_ percentage: Int) {
        let clamped = max(2, min(100, percentage))
        opacity = Double(clamped) / 100.0
    }

    func adjustZoom(byPercent percent: Double) {
        let newPercentage = zoomPercentageValue + percent
        setZoomPercentage(newPercentage)
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func requestSeek(time: Double, accurate: Bool) {
        let request: SeekRequest = .time(time, accurate: accurate)
        lastSeekRequest = request
        seekRequests.send(request)
    }

    func requestSeek(frame: Int) {
        let request: SeekRequest = .frame(frame)
        lastSeekRequest = request
        seekRequests.send(request)
    }

    func requestFrameStep(direction: FrameStepDirection, amount: Int) {
        let request = FrameStepRequest(direction: direction, amount: amount)
        lastFrameStepRequest = request
        frameStepRequests.send(request)
    }

    // MARK: - Quick Filter Methods (dropdown - single select)

    /// Set the quick filter (replaces any existing)
    func setQuickFilter(_ filter: VideoFilter?) {
        quickFilter = filter
        // Reset slider to middle when changing filters
        if filter != nil {
            quickFilterValue = 0.5
        }
    }

    /// Get the actual parameter value for the quick filter based on slider position
    func quickFilterParameterValue() -> Double {
        guard let filter = quickFilter else { return 0 }
        let range = filter.parameterRange
        return range.min + (quickFilterValue * (range.max - range.min))
    }

    // MARK: - Advanced Filter Methods (panel - multi select)

    /// Toggle an advanced filter on/off
    func toggleAdvancedFilter(_ filter: VideoFilter) {
        if advancedFilters.contains(filter) {
            advancedFilters.remove(filter)
        } else {
            advancedFilters.insert(filter)
        }
    }

    /// Check if an advanced filter is active
    func isAdvancedFilterActive(_ filter: VideoFilter) -> Bool {
        advancedFilters.contains(filter)
    }

    /// Clear all advanced filters
    func clearAdvancedFilters() {
        advancedFilters.removeAll()
    }

    /// Get advanced filters in a consistent order for chaining
    var orderedAdvancedFilters: [VideoFilter] {
        VideoFilter.allCases.filter { advancedFilters.contains($0) }
    }

    /// Get all active filters (quick + advanced) in order
    var allActiveFilters: [VideoFilter] {
        var filters: [VideoFilter] = []
        if let quick = quickFilter {
            filters.append(quick)
        }
        filters.append(contentsOf: orderedAdvancedFilters)
        return filters
    }

    /// Reset filter settings to defaults
    func resetFilterSettings() {
        filterSettings = .defaults
    }

    /// Clear everything (quick filter and advanced filters)
    func clearAllFilters() {
        quickFilter = nil
        advancedFilters.removeAll()
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: DefaultsKeys.alwaysOnTop) != nil {
            isAlwaysOnTop = defaults.bool(forKey: DefaultsKeys.alwaysOnTop)
        }

        if defaults.object(forKey: DefaultsKeys.opacity) != nil {
            opacity = defaults.double(forKey: DefaultsKeys.opacity)
        }

        if defaults.object(forKey: DefaultsKeys.lastVolume) != nil {
            lastNonZeroVolume = defaults.float(forKey: DefaultsKeys.lastVolume)
        } else {
            lastNonZeroVolume = 0.5
        }
        if lastNonZeroVolume <= 0 {
            lastNonZeroVolume = 0.5
        }

        let hasVolume = defaults.object(forKey: DefaultsKeys.volume) != nil
        let savedVolume = hasVolume ? defaults.float(forKey: DefaultsKeys.volume) : lastNonZeroVolume
        let hasMuted = defaults.object(forKey: DefaultsKeys.muted) != nil
        let savedMuted = hasMuted ? defaults.bool(forKey: DefaultsKeys.muted) : true

        isMuted = savedMuted
        volume = savedMuted ? 0.0 : savedVolume
    }

    private func handleVolumeChange(oldValue: Float) {
        guard !isLoadingPreferences else { return }
        if volume > 0 {
            lastNonZeroVolume = volume
            persistFloat(lastNonZeroVolume, key: DefaultsKeys.lastVolume)
        }

        if !isAdjustingMute {
            if volume <= 0 && !isMuted {
                isAdjustingMute = true
                isMuted = true
                isAdjustingMute = false
            } else if volume > 0 && isMuted {
                isAdjustingMute = true
                isMuted = false
                isAdjustingMute = false
            }
        }

        persistFloat(volume, key: DefaultsKeys.volume)
    }

    private func handleMuteChange(oldValue: Bool) {
        guard !isLoadingPreferences else { return }
        guard oldValue != isMuted else { return }

        if !isAdjustingMute {
            isAdjustingMute = true
            if isMuted {
                if volume > 0 {
                    lastNonZeroVolume = volume
                    persistFloat(lastNonZeroVolume, key: DefaultsKeys.lastVolume)
                }
                volume = 0.0
            } else {
                let restored = lastNonZeroVolume > 0 ? lastNonZeroVolume : 0.5
                volume = restored
            }
            isAdjustingMute = false
        }

        persistBool(isMuted, key: DefaultsKeys.muted)
    }

    private func persistBool(_ value: Bool, key: String) {
        guard !isLoadingPreferences else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistFloat(_ value: Float, key: String) {
        guard !isLoadingPreferences else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistDouble(_ value: Double, key: String) {
        guard !isLoadingPreferences else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}
