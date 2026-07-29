import Foundation
import AVFoundation
import Combine

enum FrameNavigationPrecision: Equatable {
    case unavailable
    case indexing
    case exact
    case estimated

    var isExact: Bool { self == .exact }

    var supportsFrameNavigation: Bool {
        switch self {
        case .unavailable:
            return false
        case .indexing, .exact, .estimated:
            return true
        }
    }

    static func whileBuildingExactIndex(hasEstimatedTimeline: Bool) -> Self {
        hasEstimatedTimeline ? .indexing : .unavailable
    }

    static func afterExactIndexFailure(hasEstimatedTimeline: Bool) -> Self {
        hasEstimatedTimeline ? .estimated : .unavailable
    }
}

enum NumericTextResult: Equatable {
    case accepted(value: Double, canonical: String)
    case rejected(canonical: String, message: String)
}

/// Locale-independent validation for the compact numeric fields in the
/// control bar. Non-finite input is rejected before it can reach AVFoundation,
/// Core Animation, or Core Image.
struct NumericTextInput {
    static func integer(
        _ text: String,
        current: Int,
        range: ClosedRange<Int>,
        fieldName: String
    ) -> NumericTextResult {
        let canonicalCurrent = String(max(range.lowerBound, min(range.upperBound, current)))
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = Double(trimmed),
              parsed.isFinite,
              parsed.rounded(.towardZero) == parsed,
              parsed >= Double(Int.min),
              parsed <= Double(Int.max) else {
            return .rejected(
                canonical: canonicalCurrent,
                message: "\(fieldName) must be a whole number from \(range.lowerBound) to \(range.upperBound)."
            )
        }

        let value = max(range.lowerBound, min(range.upperBound, Int(parsed)))
        return .accepted(value: Double(value), canonical: String(value))
    }

    static func decimal(
        _ text: String,
        current: Double,
        range: ClosedRange<Double>,
        fractionDigits: Int,
        fieldName: String
    ) -> NumericTextResult {
        let fallback = current.isFinite
            ? max(range.lowerBound, min(range.upperBound, current))
            : range.lowerBound
        let canonicalCurrent = canonical(fallback, fractionDigits: fractionDigits)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = Double(trimmed),
              parsed.isFinite else {
            return .rejected(
                canonical: canonicalCurrent,
                message: "\(fieldName) must be a finite number from \(canonical(range.lowerBound, fractionDigits: fractionDigits)) to \(canonical(range.upperBound, fractionDigits: fractionDigits))."
            )
        }

        let value = max(range.lowerBound, min(range.upperBound, parsed))
        return .accepted(
            value: value,
            canonical: canonical(value, fractionDigits: fractionDigits)
        )
    }

    static func canonical(_ value: Double, fractionDigits: Int) -> String {
        let normalized = value == 0 ? 0 : value
        var result = String(
            format: "%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            max(0, fractionDigits),
            normalized
        )
        if result.contains(".") {
            while result.last == "0" {
                result.removeLast()
            }
            if result.last == "." {
                result.removeLast()
            }
        }
        return result
    }
}

class VideoState: ObservableObject {
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

    enum ScrubRequest: Equatable {
        case began
        case preview(Double)
        case ended(Double)
        case cancelled
    }

    // Video loading
    @Published var videoURL: URL?
    @Published var isVideoLoaded: Bool = false
    @Published var isVideoLoading: Bool = false
    @Published var videoErrorMessage: String?
    @Published var filterErrorMessage: String?

    // Playback
    @Published private(set) var isPlaying: Bool = false
    private(set) var playbackIntentRevision: UInt64 = 0
    @Published var isAtEnd: Bool = false
    @Published private(set) var isScrubbing: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentFrame: Int = 0
    @Published var totalFrames: Int = 0
    @Published var frameRate: Double = 30.0
    @Published var frameNavigationPrecision: FrameNavigationPrecision = .unavailable
    @Published var frameNavigationMessage: String?
    @Published var videoNaturalSize: CGSize = .zero

    // Volume
    @Published var volume: Float = 0.0 { didSet { handleVolumeChange(oldValue: oldValue) } }
    @Published var isMuted: Bool = true { didSet { handleMuteChange(oldValue: oldValue) } }

    // Zoom & Pan
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    @Published var opacity: Double = 1.0 { didSet { handleOpacityChange() } }

    // Quick Filter (single filter from dropdown, controls toolbar slider)
    @Published var quickFilter: VideoFilter? = nil { didSet { persistQuickFilter() } }
    @Published var quickFilterValue: Double = 0.5 { didSet { handleQuickFilterValueChange() } }

    // Advanced Filters (multiple filters from panel, stackable)
    @Published var advancedFilters: Set<VideoFilter> = [] { didSet { persistAdvancedFilters() } }
    @Published var filterSettings: FilterSettings = .defaults { didSet { handleFilterSettingsChange() } }
    @Published var showFilterPanel: Bool = false

    // Lock mode makes the complete overlay pointer-transparent and prevents
    // movement, resizing, zooming, and panning. Use the global lock shortcut
    // to recover interaction while another app remains active.
    @Published var isLocked: Bool = false

    // Persisted unlocked-state preference. Lock mode overrides this with the
    // public status-bar window tier and restores the preference when unlocked.
    @Published var isAlwaysOnTop: Bool = true { didSet { persistBool(isAlwaysOnTop, key: DefaultsKeys.alwaysOnTop) } }

    // Help
    @Published var showHelp: Bool = false

    // Shortcut recording state (prevents Esc from closing help while recording)
    @Published var isRecordingShortcut: Bool = false

    // Shortcut settings (configurable keyboard shortcuts)
    let shortcutSettings: ShortcutSettings

    // Requests
    let seekRequests = PassthroughSubject<SeekRequest, Never>()
    let frameStepRequests = PassthroughSubject<FrameStepRequest, Never>()
    let scrubRequests = PassthroughSubject<ScrubRequest, Never>()
    let reloadRequests = PassthroughSubject<Void, Never>()

    @Published private(set) var lastSeekRequest: SeekRequest?
    @Published private(set) var lastFrameStepRequest: FrameStepRequest?
    @Published private(set) var lastScrubRequest: ScrubRequest?

    private var isLoadingPreferences = false
    private var isAdjustingMute = false
    private var lastNonZeroVolume: Float = 0.5
    private let defaults: UserDefaults

    /// The single preference store selected for this process. App-owned
    /// window geometry must use the same store so UI tests never read or
    /// mutate the user's release preferences.
    var preferenceStore: UserDefaults {
        defaults
    }

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

    var canNavigateFrames: Bool {
        isVideoLoaded
            && totalFrames > 0
            && frameNavigationPrecision.supportsFrameNavigation
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
        static let quickFilter = "VideoOverlay.quickFilter"
        static let quickFilterValue = "VideoOverlay.quickFilterValue"
        static let advancedFilters = "VideoOverlay.advancedFilters"
        static let filterSettings = "VideoOverlay.filterSettings"
    }

    init(defaults: UserDefaults? = nil) {
        let resolvedDefaults = defaults ?? Self.runtimeDefaults()
        self.defaults = resolvedDefaults
        self.shortcutSettings = ShortcutSettings(userDefaults: resolvedDefaults)
        isLoadingPreferences = true
        loadPreferences()
        isLoadingPreferences = false
    }

    private static func runtimeDefaults() -> UserDefaults {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["UITEST_MODE"] == "1",
           let suiteName = environment["UITEST_PREFERENCES_SUITE"],
           !suiteName.isEmpty,
           let defaults = UserDefaults(suiteName: suiteName) {
            if environment["UITEST_RESET_PREFERENCES"] == "1" {
                defaults.removePersistentDomain(forName: suiteName)
            }
            return defaults
        }
        #endif
        return .standard
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
        guard percentage.isFinite else { return }
        let clamped = max(10.0, min(1000.0, percentage))
        zoomScale = CGFloat(clamped / 100.0)
    }

    func setOpacityPercentage(_ percentage: Int) {
        setOpacityPercentage(Double(percentage))
    }

    func setOpacityPercentage(_ percentage: Double) {
        guard percentage.isFinite else { return }
        let clamped = max(2, min(100, percentage))
        opacity = clamped / 100
    }

    func adjustZoom(byPercent percent: Double) {
        let newPercentage = zoomPercentageValue + percent
        setZoomPercentage(newPercentage)
    }

    func toggleMute() {
        isMuted.toggle()
    }

    /// Updates playback intent synchronously on AppKit's main thread and
    /// advances the revision used to invalidate deferred seek completions.
    @discardableResult
    func setPlaybackIntent(_ shouldPlay: Bool) -> UInt64 {
        precondition(Thread.isMainThread)
        playbackIntentRevision &+= 1
        isPlaying = shouldPlay
        return playbackIntentRevision
    }

    @discardableResult
    func togglePlaybackIntent() -> UInt64 {
        setPlaybackIntent(!isPlaying)
    }

    func requestSeek(time: Double, accurate: Bool) {
        guard time.isFinite else { return }
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

    func beginScrubbing() {
        guard isVideoLoaded, !isScrubbing else { return }
        isScrubbing = true
        lastScrubRequest = .began
        scrubRequests.send(.began)
    }

    func previewScrub(time: Double) {
        guard isVideoLoaded, isScrubbing, time.isFinite else { return }
        lastScrubRequest = .preview(time)
        scrubRequests.send(.preview(time))
    }

    func endScrubbing(time: Double) {
        isScrubbing = false
        guard isVideoLoaded, time.isFinite else { return }
        lastScrubRequest = .ended(time)
        scrubRequests.send(.ended(time))
    }

    func cancelScrubbing() {
        isScrubbing = false
        lastScrubRequest = .cancelled
        scrubRequests.send(.cancelled)
    }

    func reloadVideo() {
        guard videoURL != nil else { return }
        reloadRequests.send()
    }

    // MARK: - Quick Filter Methods (dropdown - single select)

    /// Set the quick filter (replaces any existing)
    func setQuickFilter(_ filter: VideoFilter?) {
        guard filter != quickFilter else { return }
        quickFilter = filter
        if let filter {
            quickFilterValue = filter.defaultNormalizedValue
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

    /// Advanced filters that remain after the single quick-filter slot has
    /// taken ownership of the same effect.
    var effectiveAdvancedFilters: [VideoFilter] {
        orderedAdvancedFilters.filter { $0 != quickFilter }
    }

    /// Get all active filters (quick + advanced) in order
    var allActiveFilters: [VideoFilter] {
        var filters: [VideoFilter] = []
        if let quick = quickFilter {
            filters.append(quick)
        }
        filters.append(contentsOf: effectiveAdvancedFilters)
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
        if defaults.object(forKey: DefaultsKeys.alwaysOnTop) != nil {
            isAlwaysOnTop = defaults.bool(forKey: DefaultsKeys.alwaysOnTop)
        }

        if let storedOpacity = defaults.object(forKey: DefaultsKeys.opacity) as? NSNumber {
            opacity = Self.sanitized(storedOpacity.doubleValue, range: 0.02...1, fallback: 1)
        }

        if defaults.object(forKey: DefaultsKeys.lastVolume) != nil {
            lastNonZeroVolume = Self.sanitized(
                defaults.float(forKey: DefaultsKeys.lastVolume),
                range: 0...1,
                fallback: 0.5
            )
        } else {
            lastNonZeroVolume = 0.5
        }
        if lastNonZeroVolume <= 0 {
            lastNonZeroVolume = 0.5
        }

        let hasVolume = defaults.object(forKey: DefaultsKeys.volume) != nil
        let savedVolume = hasVolume
            ? Self.sanitized(defaults.float(forKey: DefaultsKeys.volume), range: 0...1, fallback: lastNonZeroVolume)
            : lastNonZeroVolume
        let hasMuted = defaults.object(forKey: DefaultsKeys.muted) != nil
        let savedMuted = hasMuted ? defaults.bool(forKey: DefaultsKeys.muted) : true

        isMuted = savedMuted
        volume = savedMuted ? 0.0 : savedVolume

        if let rawFilter = defaults.string(forKey: DefaultsKeys.quickFilter) {
            quickFilter = VideoFilter(rawValue: rawFilter)
        }
        if let storedValue = defaults.object(forKey: DefaultsKeys.quickFilterValue) as? NSNumber {
            quickFilterValue = Self.sanitized(storedValue.doubleValue, range: 0...1, fallback: quickFilter?.defaultNormalizedValue ?? 0.5)
        } else if let quickFilter {
            quickFilterValue = quickFilter.defaultNormalizedValue
        }

        if let rawFilters = defaults.array(forKey: DefaultsKeys.advancedFilters) as? [String] {
            advancedFilters = Set(rawFilters.compactMap(VideoFilter.init(rawValue:)))
        }
        if let data = defaults.data(forKey: DefaultsKeys.filterSettings),
           let decoded = try? JSONDecoder().decode(FilterSettings.self, from: data) {
            filterSettings = decoded.sanitized
        }
    }

    private func handleVolumeChange(oldValue: Float) {
        guard !isLoadingPreferences else { return }
        let sanitized = Self.sanitized(volume, range: 0...1, fallback: oldValue)
        if sanitized != volume {
            volume = sanitized
            return
        }
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
        defaults.set(value, forKey: key)
    }

    private func persistFloat(_ value: Float, key: String) {
        guard !isLoadingPreferences else { return }
        defaults.set(value, forKey: key)
    }

    private func persistDouble(_ value: Double, key: String) {
        guard !isLoadingPreferences else { return }
        defaults.set(value, forKey: key)
    }

    private func handleOpacityChange() {
        guard !isLoadingPreferences else { return }
        let sanitized = Self.sanitized(opacity, range: 0.02...1, fallback: 1)
        if sanitized != opacity {
            opacity = sanitized
            return
        }
        persistDouble(opacity, key: DefaultsKeys.opacity)
    }

    private func handleQuickFilterValueChange() {
        guard !isLoadingPreferences else { return }
        let sanitized = Self.sanitized(quickFilterValue, range: 0...1, fallback: quickFilter?.defaultNormalizedValue ?? 0.5)
        if sanitized != quickFilterValue {
            quickFilterValue = sanitized
            return
        }
        persistDouble(quickFilterValue, key: DefaultsKeys.quickFilterValue)
    }

    private func persistQuickFilter() {
        guard !isLoadingPreferences else { return }
        if let quickFilter {
            defaults.set(quickFilter.rawValue, forKey: DefaultsKeys.quickFilter)
        } else {
            defaults.removeObject(forKey: DefaultsKeys.quickFilter)
        }
    }

    private func persistAdvancedFilters() {
        guard !isLoadingPreferences else { return }
        defaults.set(
            orderedAdvancedFilters.map(\.rawValue),
            forKey: DefaultsKeys.advancedFilters
        )
    }

    private func handleFilterSettingsChange() {
        guard !isLoadingPreferences else { return }
        let sanitized = filterSettings.sanitized
        if sanitized != filterSettings {
            filterSettings = sanitized
            return
        }
        if let data = try? JSONEncoder().encode(filterSettings) {
            defaults.set(data, forKey: DefaultsKeys.filterSettings)
        }
    }

    private static func sanitized<T: BinaryFloatingPoint>(
        _ value: T,
        range: ClosedRange<T>,
        fallback: T
    ) -> T {
        guard value.isFinite else { return fallback }
        return max(range.lowerBound, min(range.upperBound, value))
    }
}
