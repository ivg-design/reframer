import AVFoundation
import UniformTypeIdentifiers

struct VideoTrackSelectionCandidate: Equatable {
    let isEnabled: Bool
    let isPlayable: Bool
    let isDecodable: Bool
    let hasSamples: Bool
    let displaySize: CGSize

    var isUsable: Bool {
        isPlayable
            && isDecodable
            && hasSamples
            && displaySize.width.isFinite
            && displaySize.height.isFinite
            && displaySize.width > 0
            && displaySize.height > 0
    }
}

struct SelectedVideoTrack {
    let track: AVAssetTrack
    let trackID: CMPersistentTrackID
    let nominalFrameRate: Double
    let displaySize: CGSize
}

/// A playback-only composition whose sole enabled video track is the source
/// track selected during preflight. Core Image's convenience composition API
/// always filters the first enabled video track, so presenting the original
/// multi-track asset would otherwise let filtering diverge from metadata and
/// frame navigation.
struct PreparedPlaybackAsset {
    let asset: AVMutableComposition
    let selectedVideoTrackID: CMPersistentTrackID
}

enum VideoPreflightError: LocalizedError {
    case unsupportedExtension(String)
    case missingFile
    case unreadableFile
    case notPlayable
    case protectedContent
    case noVideoTrack
    case invalidDuration
    case invalidVideoDimensions
    case playbackTrackUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let ext):
            return ext.isEmpty
                ? "Choose an MP4, M4V, or MOV video."
                : ".\(ext.uppercased()) is not supported. Choose an MP4, M4V, or MOV video."
        case .missingFile:
            return "The selected video no longer exists."
        case .unreadableFile:
            return "Reframer cannot read the selected video. Check its file permissions."
        case .notPlayable:
            return "AVFoundation cannot play this file's video codec or media data."
        case .protectedContent:
            return "Protected video cannot be used as a reference overlay."
        case .noVideoTrack:
            return "The selected file does not contain a playable video track."
        case .invalidDuration:
            return "The selected video does not have a valid duration."
        case .invalidVideoDimensions:
            return "The selected video does not have valid display dimensions."
        case .playbackTrackUnavailable:
            return "The selected video track could not be prepared for playback."
        }
    }
}

struct VideoFormats {
    static let supportedExtensions = ["mp4", "m4v", "mov"]

    static let supportedTypes: [UTType] = {
        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        if let m4v = UTType("com.apple.m4v-video") {
            types.append(m4v)
        }
        return types
    }()

    static let displayString = "MP4 • M4V • MOV"

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }

        // A non-existent URL (for example, before a save/open operation or in
        // a unit test) is validated by extension. Existing files also have
        // their declared type checked so renamed non-video files are rejected.
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return true
        }
        return isSupported(contentType: contentType)
    }

    static func isSupported(contentType: UTType) -> Bool {
        supportedTypes.contains { contentType.conforms(to: $0) }
    }

    /// Selects one video track for both player presentation and frame
    /// navigation. Container-enabled tracks win; a usable disabled track is a
    /// fallback for files whose enabled flags are malformed or absent.
    static func selectVideoTrack(in asset: AVAsset) async throws -> SelectedVideoTrack {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else {
            throw VideoPreflightError.noVideoTrack
        }

        var candidates: [VideoTrackSelectionCandidate] = []
        var evaluatedTracks: [SelectedVideoTrack?] = []
        candidates.reserveCapacity(tracks.count)
        evaluatedTracks.reserveCapacity(tracks.count)

        for track in tracks {
            do {
                async let isEnabled = track.load(.isEnabled)
                async let isPlayable = track.load(.isPlayable)
                async let isDecodable = track.load(.isDecodable)
                async let segments = track.load(.segments)
                async let naturalSize = track.load(.naturalSize)
                async let preferredTransform = track.load(.preferredTransform)
                async let nominalFrameRate = track.load(.nominalFrameRate)

                let values = try await (
                    isEnabled,
                    isPlayable,
                    isDecodable,
                    segments,
                    naturalSize,
                    preferredTransform,
                    nominalFrameRate
                )
                let displaySize = displaySize(
                    naturalSize: values.4,
                    preferredTransform: values.5
                )
                candidates.append(
                    VideoTrackSelectionCandidate(
                        isEnabled: values.0,
                        isPlayable: values.1,
                        isDecodable: values.2,
                        hasSamples: values.3.contains { !$0.isEmpty },
                        displaySize: displaySize
                    )
                )
                evaluatedTracks.append(
                    SelectedVideoTrack(
                        track: track,
                        trackID: track.trackID,
                        nominalFrameRate: Double(values.6),
                        displaySize: displaySize
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                candidates.append(
                    VideoTrackSelectionCandidate(
                        isEnabled: false,
                        isPlayable: false,
                        isDecodable: false,
                        hasSamples: false,
                        displaySize: .zero
                    )
                )
                evaluatedTracks.append(nil)
            }
        }

        guard let selectedIndex = preferredVideoTrackIndex(in: candidates),
              let selectedTrack = evaluatedTracks[selectedIndex] else {
            throw VideoPreflightError.noVideoTrack
        }
        return selectedTrack
    }

    static func preferredVideoTrackIndex(
        in candidates: [VideoTrackSelectionCandidate]
    ) -> Int? {
        candidates.firstIndex { $0.isEnabled && $0.isUsable }
            ?? candidates.firstIndex { $0.isUsable }
    }

    /// Returns the axis-aligned display bounds of a transformed video frame.
    /// Applying an affine transform directly to `CGSize` treats the dimensions
    /// as one vector and can collapse a valid rotated or sheared rectangle.
    static func displaySize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
            .size
    }

    /// Builds the asset consumed by AVPlayer and the Core Image filter
    /// pipeline. It contains exactly one enabled video track—the selected
    /// source track—and preserves every usable audio track with its enabled
    /// state, timing, language, and preferred volume.
    static func preparePlaybackAsset(
        from sourceAsset: AVAsset,
        selectedVideoTrack: SelectedVideoTrack
    ) async throws -> PreparedPlaybackAsset {
        try Task.checkCancellation()

        let composition = AVMutableComposition()
        composition.naturalSize = selectedVideoTrack.displaySize

        guard let playbackVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoPreflightError.playbackTrackUnavailable
        }

        let sourceVideoTimeRange: CMTimeRange
        let destinationVideoStart: CMTime
        do {
            let sourceTrack = selectedVideoTrack.track
            async let timeRange = sourceTrack.load(.timeRange)
            async let naturalTimeScale = sourceTrack.load(.naturalTimeScale)
            async let preferredTransform = sourceTrack.load(.preferredTransform)
            let values = try await (
                timeRange,
                naturalTimeScale,
                preferredTransform
            )
            try Task.checkCancellation()
            guard values.0.isValid,
                  values.0.start.isNumeric,
                  values.0.duration.isNumeric,
                  CMTimeCompare(values.0.duration, .zero) > 0 else {
                throw VideoPreflightError.playbackTrackUnavailable
            }

            sourceVideoTimeRange = values.0
            destinationVideoStart = max(values.0.start, .zero)
            try playbackVideoTrack.insertTimeRange(
                sourceVideoTimeRange,
                of: sourceTrack,
                at: destinationVideoStart
            )
            playbackVideoTrack.naturalTimeScale = values.1
            playbackVideoTrack.preferredTransform = values.2
            playbackVideoTrack.isEnabled = true
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VideoPreflightError {
            throw error
        } catch {
            throw VideoPreflightError.playbackTrackUnavailable
        }

        let sourceAudioTracks = try await sourceAsset.loadTracks(
            withMediaType: .audio
        )
        for sourceAudioTrack in sourceAudioTracks {
            try Task.checkCancellation()
            await copyUsableAudioTrack(
                sourceAudioTrack,
                into: composition,
                overlapping: sourceVideoTimeRange,
                videoDestinationStart: destinationVideoStart
            )
        }
        try Task.checkCancellation()

        return PreparedPlaybackAsset(
            asset: composition,
            selectedVideoTrackID: playbackVideoTrack.trackID
        )
    }

    private static func copyUsableAudioTrack(
        _ sourceTrack: AVAssetTrack,
        into composition: AVMutableComposition,
        overlapping sourceVideoTimeRange: CMTimeRange,
        videoDestinationStart: CMTime
    ) async {
        do {
            async let isEnabled = sourceTrack.load(.isEnabled)
            async let isPlayable = sourceTrack.load(.isPlayable)
            async let isDecodable = sourceTrack.load(.isDecodable)
            async let segments = sourceTrack.load(.segments)
            async let timeRange = sourceTrack.load(.timeRange)
            async let naturalTimeScale = sourceTrack.load(.naturalTimeScale)
            async let preferredVolume = sourceTrack.load(.preferredVolume)
            let values = try await (
                isEnabled,
                isPlayable,
                isDecodable,
                segments,
                timeRange,
                naturalTimeScale,
                preferredVolume
            )
            try Task.checkCancellation()
            guard values.1,
                  values.2,
                  values.3.contains(where: { !$0.isEmpty }),
                  values.4.isValid,
                  values.4.start.isNumeric,
                  values.4.duration.isNumeric,
                  CMTimeCompare(values.4.duration, .zero) > 0,
                  let playbackAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                return
            }

            let overlappingTimeRange = CMTimeRangeGetIntersection(
                values.4,
                otherRange: sourceVideoTimeRange
            )
            guard overlappingTimeRange.isValid,
                  !overlappingTimeRange.isEmpty,
                  overlappingTimeRange.start.isNumeric,
                  overlappingTimeRange.duration.isNumeric,
                  CMTimeCompare(overlappingTimeRange.duration, .zero) > 0 else {
                composition.removeTrack(playbackAudioTrack)
                return
            }
            let destinationStart = CMTimeAdd(
                videoDestinationStart,
                CMTimeSubtract(
                    overlappingTimeRange.start,
                    sourceVideoTimeRange.start
                )
            )
            guard destinationStart.isNumeric,
                  CMTimeCompare(destinationStart, .zero) >= 0 else {
                composition.removeTrack(playbackAudioTrack)
                return
            }

            do {
                try playbackAudioTrack.insertTimeRange(
                    overlappingTimeRange,
                    of: sourceTrack,
                    at: destinationStart
                )
            } catch {
                composition.removeTrack(playbackAudioTrack)
                return
            }

            playbackAudioTrack.naturalTimeScale = values.5
            playbackAudioTrack.preferredVolume = values.6
            playbackAudioTrack.isEnabled = values.0
            playbackAudioTrack.languageCode =
                (try? await sourceTrack.load(.languageCode)) ?? nil
            playbackAudioTrack.extendedLanguageTag =
                (try? await sourceTrack.load(.extendedLanguageTag)) ?? nil
        } catch {
            // A malformed or unsupported audio track must not prevent an
            // otherwise usable selected video track from loading.
        }
    }

    /// Validates the actual local asset before the UI declares it loaded.
    static func preflight(_ url: URL) async throws -> AVURLAsset {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw VideoPreflightError.unsupportedExtension(ext)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoPreflightError.missingFile
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw VideoPreflightError.unreadableFile
        }

        let asset = AVURLAsset(url: url)
        let isPlayable: Bool
        do {
            isPlayable = try await asset.load(.isPlayable)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoPreflightError.notPlayable
        }
        guard isPlayable else {
            throw VideoPreflightError.notPlayable
        }

        let hasProtectedContent: Bool
        do {
            hasProtectedContent = try await asset.load(.hasProtectedContent)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoPreflightError.notPlayable
        }
        guard !hasProtectedContent else {
            throw VideoPreflightError.protectedContent
        }

        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoPreflightError.notPlayable
        }
        guard !tracks.isEmpty else {
            throw VideoPreflightError.noVideoTrack
        }
        return asset
    }
}
