import Foundation
import Darwin

enum WebMCodec: String, Equatable {
    case vp8
    case vp9

    var ffmpegDecoder: String {
        switch self {
        case .vp8:
            return "libvpx"
        case .vp9:
            return "libvpx-vp9"
        }
    }
}

struct WebMProbeResult: Equatable {
    let codec: WebMCodec
    let hasAlpha: Bool
    let videoStreamIndex: Int

    init(
        codec: WebMCodec,
        hasAlpha: Bool,
        videoStreamIndex: Int = 0
    ) {
        self.codec = codec
        self.hasAlpha = hasAlpha
        self.videoStreamIndex = videoStreamIndex
    }
}

enum WebMPreparationError: LocalizedError, Equatable {
    case missingInput
    case unreadableInput
    case invalidContainer
    case unsupportedCodec
    case helperMissing
    case helperNotExecutable
    case insufficientDiskSpace
    case alreadyStarted
    case cancelled
    case timedOut
    case outputTooLarge
    case conversionFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "The selected WebM file no longer exists."
        case .unreadableInput:
            return "Reframer cannot read the selected WebM file."
        case .invalidContainer:
            return "The selected file is not a valid WebM container."
        case .unsupportedCodec:
            return "This WebM video does not contain a supported VP8 or VP9 track."
        case .helperMissing:
            return "Reframer’s bundled WebM decoder is missing."
        case .helperNotExecutable:
            return "Reframer’s bundled WebM decoder cannot be executed."
        case .insufficientDiskSpace:
            return "WebM preparation needs at least 2 GB of available temporary disk space."
        case .alreadyStarted:
            return "This WebM preparation session has already started."
        case .cancelled:
            return "WebM preparation was cancelled."
        case .timedOut:
            return "WebM preparation stopped because the decoder stopped making progress."
        case .outputTooLarge:
            return "The prepared WebM exceeded Reframer’s 64 GB temporary-file safety limit."
        case .conversionFailed:
            return "The WebM video could not be decoded."
        case .invalidOutput:
            return "The WebM decoder did not produce a playable intermediate."
        }
    }
}

enum ProcessTerminationSignal: Equatable {
    case none
    case terminate
    case kill
}

struct ProcessTerminationEscalation {
    let gracePeriod: TimeInterval
    private var requestedAt: Date?
    private var didKill = false

    init(gracePeriod: TimeInterval = 2) {
        self.gracePeriod = max(0, gracePeriod)
    }

    mutating func signal(
        shouldStop: Bool,
        now: Date
    ) -> ProcessTerminationSignal {
        guard shouldStop, !didKill else { return .none }
        guard let requestedAt else {
            self.requestedAt = now
            return .terminate
        }
        guard now.timeIntervalSince(requestedAt) >= gracePeriod else {
            return .none
        }
        didKill = true
        return .kill
    }
}

struct ProcessProgressWatchdog {
    let stallTimeout: TimeInterval
    let maximumRuntime: TimeInterval

    private let startedAt: Date
    private var lastProgressAt: Date
    private var lastOutputBytes: Int64

    init(
        startedAt: Date,
        initialOutputBytes: Int64 = 0,
        stallTimeout: TimeInterval,
        maximumRuntime: TimeInterval
    ) {
        self.startedAt = startedAt
        lastProgressAt = startedAt
        lastOutputBytes = max(0, initialOutputBytes)
        self.stallTimeout = max(0, stallTimeout)
        self.maximumRuntime = max(0, maximumRuntime)
    }

    mutating func hasTimedOut(
        now: Date,
        outputBytes: Int64
    ) -> Bool {
        if outputBytes > lastOutputBytes {
            lastOutputBytes = outputBytes
            lastProgressAt = now
        }
        return now.timeIntervalSince(startedAt) >= maximumRuntime
            || now.timeIntervalSince(lastProgressAt) >= stallTimeout
    }
}

enum WebMProbe {
    private struct TrackProbe {
        let isVideo: Bool
        let codec: WebMCodec?
        let hasAlpha: Bool
    }

    private struct ElementHeader {
        let id: UInt64
        let dataOffset: UInt64
        let size: UInt64?

        func endOffset(limitedBy parentEnd: UInt64) throws -> UInt64 {
            guard dataOffset <= parentEnd else {
                throw WebMPreparationError.invalidContainer
            }
            guard let size else { return parentEnd }
            guard size <= parentEnd - dataOffset else {
                throw WebMPreparationError.invalidContainer
            }
            return dataOffset + size
        }
    }

    private static let ebmlID: UInt64 = 0x1A45DFA3
    private static let docTypeID: UInt64 = 0x4282
    private static let segmentID: UInt64 = 0x18538067
    private static let tracksID: UInt64 = 0x1654AE6B
    private static let trackEntryID: UInt64 = 0xAE
    private static let trackTypeID: UInt64 = 0x83
    private static let codecID: UInt64 = 0x86
    private static let videoID: UInt64 = 0xE0
    private static let alphaModeID: UInt64 = 0x53C0

    private static let maximumHeaderBytes: UInt64 = 1_048_576
    private static let maximumTracksBytes: UInt64 = 64 * 1_048_576

    static func inspect(_ url: URL) throws -> WebMProbeResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WebMPreparationError.missingInput
        }
        guard FileManager.default.isReadableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            throw WebMPreparationError.unreadableInput
        }
        defer { try? handle.close() }

        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0 else {
            throw WebMPreparationError.invalidContainer
        }
        let fileEnd = UInt64(fileSize)

        var cursor: UInt64 = 0
        let ebml = try readElementHeader(
            from: handle,
            at: cursor,
            parentEnd: fileEnd
        )
        guard ebml.id == ebmlID,
              let ebmlSize = ebml.size,
              ebmlSize <= maximumHeaderBytes else {
            throw WebMPreparationError.invalidContainer
        }
        let ebmlEnd = try ebml.endOffset(limitedBy: fileEnd)
        guard try documentType(in: ebml, end: ebmlEnd, handle: handle)
                == "webm" else {
            throw WebMPreparationError.invalidContainer
        }
        cursor = ebmlEnd

        var rootElementCount = 0
        while cursor < fileEnd, rootElementCount < 256 {
            rootElementCount += 1
            let element = try readElementHeader(
                from: handle,
                at: cursor,
                parentEnd: fileEnd
            )
            let elementEnd = try element.endOffset(limitedBy: fileEnd)
            if element.id == segmentID {
                return try inspectSegment(
                    element,
                    end: elementEnd,
                    handle: handle
                )
            }
            guard elementEnd > cursor else {
                throw WebMPreparationError.invalidContainer
            }
            cursor = elementEnd
        }
        throw WebMPreparationError.invalidContainer
    }

    private static func documentType(
        in header: ElementHeader,
        end: UInt64,
        handle: FileHandle
    ) throws -> String? {
        var cursor = header.dataOffset
        var elementCount = 0
        while cursor < end, elementCount < 128 {
            elementCount += 1
            let element = try readElementHeader(
                from: handle,
                at: cursor,
                parentEnd: end
            )
            let elementEnd = try element.endOffset(limitedBy: end)
            if element.id == docTypeID {
                return try readString(
                    from: handle,
                    element: element,
                    maximumBytes: 32
                ).lowercased()
            }
            guard elementEnd > cursor else {
                throw WebMPreparationError.invalidContainer
            }
            cursor = elementEnd
        }
        return nil
    }

    private static func inspectSegment(
        _ segment: ElementHeader,
        end: UInt64,
        handle: FileHandle
    ) throws -> WebMProbeResult {
        var cursor = segment.dataOffset
        var elementCount = 0
        while cursor < end, elementCount < 100_000 {
            elementCount += 1
            let element = try readElementHeader(
                from: handle,
                at: cursor,
                parentEnd: end
            )
            let elementEnd = try element.endOffset(limitedBy: end)
            if element.id == tracksID {
                guard elementEnd - element.dataOffset <= maximumTracksBytes else {
                    throw WebMPreparationError.invalidContainer
                }
                return try inspectTracks(
                    element,
                    end: elementEnd,
                    handle: handle
                )
            }
            guard elementEnd > cursor else {
                throw WebMPreparationError.invalidContainer
            }
            cursor = elementEnd
        }
        throw WebMPreparationError.unsupportedCodec
    }

    private static func inspectTracks(
        _ tracks: ElementHeader,
        end: UInt64,
        handle: FileHandle
    ) throws -> WebMProbeResult {
        var cursor = tracks.dataOffset
        var elementCount = 0
        var videoStreamIndex = 0
        while cursor < end, elementCount < 10_000 {
            elementCount += 1
            let element = try readElementHeader(
                from: handle,
                at: cursor,
                parentEnd: end
            )
            let elementEnd = try element.endOffset(limitedBy: end)
            if element.id == trackEntryID {
                let track = try inspectTrackEntry(
                    element,
                    end: elementEnd,
                    handle: handle
                )
                if track.isVideo {
                    if let codec = track.codec {
                        return WebMProbeResult(
                            codec: codec,
                            hasAlpha: track.hasAlpha,
                            videoStreamIndex: videoStreamIndex
                        )
                    }
                    videoStreamIndex += 1
                }
            }
            guard elementEnd > cursor else {
                throw WebMPreparationError.invalidContainer
            }
            cursor = elementEnd
        }
        throw WebMPreparationError.unsupportedCodec
    }

    private static func inspectTrackEntry(
        _ trackEntry: ElementHeader,
        end: UInt64,
        handle: FileHandle
    ) throws -> TrackProbe {
        var cursor = trackEntry.dataOffset
        var trackType: UInt64?
        var codec: WebMCodec?
        var hasAlpha = false
        var elementCount = 0

        while cursor < end, elementCount < 512 {
            elementCount += 1
            let element = try readElementHeader(
                from: handle,
                at: cursor,
                parentEnd: end
            )
            let elementEnd = try element.endOffset(limitedBy: end)
            switch element.id {
            case trackTypeID:
                trackType = try readUnsignedInteger(
                    from: handle,
                    element: element
                )
            case codecID:
                switch try readString(
                    from: handle,
                    element: element,
                    maximumBytes: 64
                ) {
                case "V_VP8":
                    codec = .vp8
                case "V_VP9":
                    codec = .vp9
                default:
                    codec = nil
                }
            case videoID:
                hasAlpha = try videoHasAlpha(
                    element,
                    end: elementEnd,
                    handle: handle
                )
            default:
                break
            }
            guard elementEnd > cursor else {
                throw WebMPreparationError.invalidContainer
            }
            cursor = elementEnd
        }
        let isVideo = trackType == 1
        return TrackProbe(
            isVideo: isVideo,
            codec: isVideo ? codec : nil,
            hasAlpha: isVideo && hasAlpha
        )
    }

    private static func videoHasAlpha(
        _ video: ElementHeader,
        end: UInt64,
        handle: FileHandle
    ) throws -> Bool {
        var cursor = video.dataOffset
        var elementCount = 0
        while cursor < end, elementCount < 256 {
            elementCount += 1
            let element = try readElementHeader(
                from: handle,
                at: cursor,
                parentEnd: end
            )
            let elementEnd = try element.endOffset(limitedBy: end)
            if element.id == alphaModeID {
                return try readUnsignedInteger(
                    from: handle,
                    element: element
                ) == 1
            }
            guard elementEnd > cursor else {
                throw WebMPreparationError.invalidContainer
            }
            cursor = elementEnd
        }
        return false
    }

    private static func readElementHeader(
        from handle: FileHandle,
        at offset: UInt64,
        parentEnd: UInt64
    ) throws -> ElementHeader {
        guard offset < parentEnd else {
            throw WebMPreparationError.invalidContainer
        }
        let available = min(12, Int(parentEnd - offset))
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: available),
              !data.isEmpty else {
            throw WebMPreparationError.invalidContainer
        }
        let bytes = [UInt8](data)

        guard let idLength = vintLength(firstByte: bytes[0], maximum: 4),
              idLength < bytes.count else {
            throw WebMPreparationError.invalidContainer
        }
        var id: UInt64 = 0
        for byte in bytes[0..<idLength] {
            id = (id << 8) | UInt64(byte)
        }

        let sizeIndex = idLength
        guard let sizeLength = vintLength(
            firstByte: bytes[sizeIndex],
            maximum: 8
        ),
        sizeIndex + sizeLength <= bytes.count else {
            throw WebMPreparationError.invalidContainer
        }
        let marker = UInt8(0x80 >> (sizeLength - 1))
        var size = UInt64(bytes[sizeIndex] & (marker - 1))
        if sizeLength > 1 {
            for byte in bytes[(sizeIndex + 1)..<(sizeIndex + sizeLength)] {
                size = (size << 8) | UInt64(byte)
            }
        }
        let unknownValue = (UInt64(1) << UInt64(7 * sizeLength)) - 1
        let headerLength = idLength + sizeLength
        let dataOffset = offset + UInt64(headerLength)
        guard dataOffset <= parentEnd else {
            throw WebMPreparationError.invalidContainer
        }
        return ElementHeader(
            id: id,
            dataOffset: dataOffset,
            size: size == unknownValue ? nil : size
        )
    }

    private static func vintLength(
        firstByte: UInt8,
        maximum: Int
    ) -> Int? {
        guard firstByte != 0 else { return nil }
        var marker: UInt8 = 0x80
        for length in 1...maximum {
            if firstByte & marker != 0 {
                return length
            }
            marker >>= 1
        }
        return nil
    }

    private static func readUnsignedInteger(
        from handle: FileHandle,
        element: ElementHeader
    ) throws -> UInt64 {
        guard let size = element.size, (1...8).contains(size) else {
            throw WebMPreparationError.invalidContainer
        }
        let data = try readData(
            from: handle,
            offset: element.dataOffset,
            count: Int(size)
        )
        return data.reduce(UInt64(0)) {
            ($0 << 8) | UInt64($1)
        }
    }

    private static func readString(
        from handle: FileHandle,
        element: ElementHeader,
        maximumBytes: Int
    ) throws -> String {
        guard let size = element.size,
              size > 0,
              size <= UInt64(maximumBytes) else {
            throw WebMPreparationError.invalidContainer
        }
        let data = try readData(
            from: handle,
            offset: element.dataOffset,
            count: Int(size)
        )
        guard let value = String(data: data, encoding: .utf8) else {
            throw WebMPreparationError.invalidContainer
        }
        return value
    }

    private static func readData(
        from handle: FileHandle,
        offset: UInt64,
        count: Int
    ) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count),
              data.count == count else {
            throw WebMPreparationError.invalidContainer
        }
        return data
    }
}

/// Runs the bundled, network-disabled FFmpeg helper out of process. WebM is
/// converted to a temporary ProRes 4444 movie so the existing AVFoundation
/// path preserves alpha and retains exact indexing, filters, audio, and every
/// established playback control.
final class WebMPreparationSession {
    typealias Completion = (Result<URL, Error>) -> Void

    private static let queue = DispatchQueue(
        label: "com.reframer.webm-preparation",
        qos: .userInitiated
    )

    let inputURL: URL
    let outputURL: URL
    let helperURL: URL

    private let lock = NSLock()
    private var process: Process?
    private var didStart = false
    private var didComplete = false
    private var wasCancelled = false
    private var suddenTerminationDisabled = false
    private var resourceLease: SecurityScopedURLLease?
    private let stallTimeout: TimeInterval
    private let maximumRuntime: TimeInterval

    init(
        inputURL: URL,
        helperURL: URL = WebMPreparationSession.bundledHelperURL(),
        outputDirectory: URL = WebMPreparationSession.outputDirectory(),
        stallTimeout: TimeInterval = 5 * 60,
        maximumRuntime: TimeInterval = 12 * 60 * 60
    ) {
        self.inputURL = inputURL
        self.helperURL = helperURL
        self.stallTimeout = max(0, stallTimeout)
        self.maximumRuntime = max(0, maximumRuntime)
        outputURL = outputDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
    }

    deinit {
        cancel()
    }

    func start(completion: @escaping Completion) {
        lock.lock()
        guard !didStart else {
            lock.unlock()
            DispatchQueue.main.async {
                completion(.failure(WebMPreparationError.alreadyStarted))
            }
            return
        }
        didStart = true
        ProcessInfo.processInfo.disableSuddenTermination()
        suddenTerminationDisabled = true
        guard !didComplete, !wasCancelled else {
            lock.unlock()
            complete(.failure(WebMPreparationError.cancelled), completion)
            return
        }
        resourceLease = SecurityScopedURLLease(url: inputURL)
        lock.unlock()

        Self.queue.async { [self] in
            do {
                let probe = try WebMProbe.inspect(inputURL)
                try validateHelper()
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let maximumOutputBytes = try maximumOutputBytes()
                try? FileManager.default.removeItem(at: outputURL)
                try? FileManager.default.removeItem(at: workingOutputURL)

                let inputHandle: FileHandle
                do {
                    inputHandle = try FileHandle(forReadingFrom: inputURL)
                } catch {
                    throw WebMPreparationError.unreadableInput
                }
                defer { try? inputHandle.close() }

                let process = Process()
                process.executableURL = helperURL
                process.arguments = Self.helperArguments(
                    for: probe,
                    outputURL: workingOutputURL
                )
                // The parent opens the security-scoped file and passes the
                // already-authorized descriptor to the sandboxed helper.
                // Child processes cannot independently use the parent's
                // PowerBox path extension.
                process.standardInput = inputHandle
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                lock.lock()
                guard !wasCancelled else {
                    lock.unlock()
                    finish(.failure(WebMPreparationError.cancelled), completion)
                    return
                }
                self.process = process
                do {
                    // Holding the lock across launch closes the narrow race
                    // where cancel() could observe a not-yet-running process.
                    try process.run()
                } catch {
                    self.process = nil
                    lock.unlock()
                    throw error
                }
                lock.unlock()

                var exceededOutputLimit = false
                var timedOut = false
                var terminationEscalation = ProcessTerminationEscalation()
                let processStartedAt = Date()
                var progressWatchdog = ProcessProgressWatchdog(
                    startedAt: processStartedAt,
                    stallTimeout: stallTimeout,
                    maximumRuntime: maximumRuntime
                )
                while process.isRunning {
                    lock.lock()
                    let cancelled = wasCancelled
                    lock.unlock()
                    let outputBytes = Self.fileSize(at: workingOutputURL)
                    if outputBytes > maximumOutputBytes {
                        exceededOutputLimit = true
                    }
                    if progressWatchdog.hasTimedOut(
                        now: Date(),
                        outputBytes: outputBytes
                    ) {
                        timedOut = true
                    }
                    switch terminationEscalation.signal(
                        shouldStop: cancelled
                            || exceededOutputLimit
                            || timedOut,
                        now: Date()
                    ) {
                    case .none:
                        break
                    case .terminate:
                        process.terminate()
                    case .kill:
                        kill(process.processIdentifier, SIGKILL)
                    }
                    if process.isRunning {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
                process.waitUntilExit()

                let finalWorkingBytes = Self.fileSize(at: workingOutputURL)
                if progressWatchdog.hasTimedOut(
                    now: Date(),
                    outputBytes: finalWorkingBytes
                ) {
                    timedOut = true
                }
                if finalWorkingBytes > maximumOutputBytes {
                    exceededOutputLimit = true
                }

                lock.lock()
                self.process = nil
                let cancelled = wasCancelled
                lock.unlock()

                if cancelled {
                    finish(.failure(WebMPreparationError.cancelled), completion)
                } else if exceededOutputLimit {
                    finish(
                        .failure(WebMPreparationError.outputTooLarge),
                        completion
                    )
                } else if timedOut {
                    finish(
                        .failure(WebMPreparationError.timedOut),
                        completion
                    )
                } else if process.terminationReason != .exit
                            || process.terminationStatus != 0 {
                    finish(
                        .failure(WebMPreparationError.conversionFailed),
                        completion
                    )
                } else {
                    let values = try workingOutputURL.resourceValues(
                        forKeys: [.isRegularFileKey, .fileSizeKey]
                    )
                    let finalOutputBytes = Int64(values.fileSize ?? 0)
                    guard values.isRegularFile == true,
                          finalOutputBytes > 0 else {
                        throw WebMPreparationError.invalidOutput
                    }
                    guard finalOutputBytes <= maximumOutputBytes else {
                        throw WebMPreparationError.outputTooLarge
                    }
                    try FileManager.default.moveItem(
                        at: workingOutputURL,
                        to: outputURL
                    )
                    finish(.success(outputURL), completion)
                }
            } catch {
                finish(.failure(error), completion)
            }
        }
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let runningProcess = process
        lock.unlock()
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    func cancelAndWait(timeout: TimeInterval = 2) {
        cancel()
        lock.lock()
        let runningProcess = process
        lock.unlock()
        guard let runningProcess, runningProcess.isRunning else { return }

        let deadline = Date().addingTimeInterval(max(0, timeout))
        while runningProcess.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if runningProcess.isRunning {
            kill(runningProcess.processIdentifier, SIGKILL)
        }
        runningProcess.waitUntilExit()
    }

    private func validateHelper() throws {
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            throw WebMPreparationError.helperMissing
        }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw WebMPreparationError.helperNotExecutable
        }
    }

    private var workingOutputURL: URL {
        outputURL.appendingPathExtension("partial")
    }

    private func maximumOutputBytes() throws -> Int64 {
        let values = try outputURL.deletingLastPathComponent().resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let minimumCapacity: Int64 = 2 * 1_024 * 1_024 * 1_024
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < minimumCapacity {
            throw WebMPreparationError.insufficientDiskSpace
        }
        let hardLimit: Int64 = 64 * 1_024 * 1_024 * 1_024
        let reserve: Int64 = 1 * 1_024 * 1_024 * 1_024
        guard let available = values.volumeAvailableCapacityForImportantUsage
        else {
            return hardLimit
        }
        return min(hardLimit, max(0, available - reserve))
    }

    private static func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return 0
        }
        return Int64(size)
    }

    static func helperArguments(
        for probe: WebMProbeResult,
        outputURL: URL
    ) -> [String] {
        let videoSpecifier = "v:\(probe.videoStreamIndex)"
        let inputVideo = "0:\(videoSpecifier)"
        var arguments = [
            "-hide_banner",
            "-nostdin",
            "-loglevel", "error",
            "-y",
            "-c:\(videoSpecifier)", probe.codec.ffmpegDecoder,
            "-i", "pipe:0",
            "-map_metadata", "-1",
            "-map_chapters", "-1"
        ]
        if probe.hasAlpha {
            arguments += [
                "-filter_complex",
                """
                [\(inputVideo)]split[base][alphasrc];[base]format=yuv444p10le[base10];[alphasrc]alphaextract,scale=in_range=full:out_range=full,setrange=tv[alpha10];[base10][alpha10]mergeplanes=format=yuva444p10le:map0s=0:map0p=0:map1s=0:map1p=1:map2s=0:map2p=2:map3s=1:map3p=0[out]
                """,
                "-map", "[out]",
                "-alpha_bits", "16",
                "-pix_fmt", "yuva444p10le"
            ]
        } else {
            arguments += [
                "-map", inputVideo,
                "-pix_fmt", "yuv444p10le"
            ]
        }
        arguments += [
            "-map", "0:a:0?",
            "-c:v", "prores_ks",
            "-profile:v", "4",
            "-vendor", "apl0",
            "-c:a", "pcm_s16le",
            "-movflags", "+faststart",
            "-f", "mov",
            outputURL.path
        ]
        return arguments
    }

    private func finish(_ result: Result<URL, Error>, _ completion: @escaping Completion) {
        complete(result, completion)
    }

    private func complete(
        _ result: Result<URL, Error>,
        _ completion: @escaping Completion
    ) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        let resolvedResult: Result<URL, Error> = wasCancelled
            ? .failure(WebMPreparationError.cancelled)
            : result
        didComplete = true
        process = nil
        resourceLease = nil
        let shouldEnableSuddenTermination = suddenTerminationDisabled
        suddenTerminationDisabled = false
        lock.unlock()

        if shouldEnableSuddenTermination {
            ProcessInfo.processInfo.enableSuddenTermination()
        }
        if case .failure = resolvedResult {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: workingOutputURL)
        }
        DispatchQueue.main.async {
            completion(resolvedResult)
        }
    }

    static func bundledHelperURL(bundle: Bundle = .main) -> URL {
        bundle.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("reframer-ffmpeg")
    }

    static func outputDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Reframer", isDirectory: true)
            .appendingPathComponent("PreparedWebM", isDirectory: true)
    }

    static func removeStaleOutputs() {
        try? FileManager.default.removeItem(at: outputDirectory())
    }
}
