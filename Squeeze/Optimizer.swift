import Foundation
import ImageIO
import CoreGraphics

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[Squeeze] " + message + "\n").utf8))
}

enum OutputFormat: String, CaseIterable {
    case webp, avif, jpeg, png

    var title: String {
        switch self {
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        }
    }

    var fileExtension: String {
        switch self {
        case .webp: return "webp"
        case .avif: return "avif"
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }

    var isLossy: Bool { self != .png }

    var imageIOType: String? {
        switch self {
        case .avif: return "public.avif"
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .webp: return nil
        }
    }
}

enum Destination: Equatable {
    case subfolder
    case replace
    case folder(URL)
}

struct OptimizeOptions {
    var format = OutputFormat.webp
    var quality = 80
    var maxEdge = 1920
    var destination = Destination.subfolder
    var pattern = NamePlanner.defaultPattern
    var startNumber = 1
}

struct PixelSize: Equatable {
    var width: Int
    var height: Int
    var longEdge: Int { max(width, height) }
    var text: String { "\(width)×\(height)" }
}

struct FileReport {
    let source: URL
    var output: URL?
    var originalBytes = 0
    var newBytes = 0
    var originalSize: PixelSize?
    var newSize: PixelSize?
    var error: String?

    var succeeded: Bool { error == nil }
}

struct BatchReport {
    var files: [FileReport]
    var cancelled: Bool
    var duration: TimeInterval

    var succeeded: [FileReport] { files.filter(\.succeeded) }
    var failed: [FileReport] { files.filter { !$0.succeeded } }
    var originalBytes: Int { succeeded.reduce(0) { $0 + $1.originalBytes } }
    var newBytes: Int { succeeded.reduce(0) { $0 + $1.newBytes } }
    var outputs: [URL] { succeeded.compactMap(\.output) }

    var summary: String {
        let done = succeeded
        var text = "\(done.count) \(done.count == 1 ? "image" : "images")"
        if !done.isEmpty {
            text += ", \(Format.bytes(originalBytes)) → \(Format.bytes(newBytes)) (\(Format.change(from: originalBytes, to: newBytes)))"
        }
        if !failed.isEmpty { text += ", \(failed.count) failed" }
        if cancelled { text = "Cancelled · " + text }
        return text
    }
}

struct OptimizeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Format {
    static func bytes(_ count: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(count)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return "\(count) B" }
        return String(format: "%.1f %@", value, units[index])
    }

    static func change(from original: Int, to new: Int) -> String {
        guard original > 0 else { return "0 %" }
        let percent = Int(((Double(new) / Double(original)) - 1) * 100).magnitude
        return new <= original ? "−\(percent) %" : "+\(percent) %"
    }

    static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.1f s", interval)
    }
}

enum ImageCollector {
    static let extensions: Set<String> = ["jpg", "jpeg", "jpe", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "avif", "bmp"]
    static let outputFolderName = "optimized"

    static func isImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    static func accepts(_ url: URL) -> Bool {
        isDirectory(url) || isImage(url)
    }

    static func collect(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        func add(_ url: URL) {
            let key = url.standardizedFileURL.path.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(url)
        }
        for url in urls {
            if isDirectory(url) {
                for file in filesInFolder(url) { add(file) }
            } else if isImage(url) {
                add(url)
            }
        }
        return result
    }

    private static func filesInFolder(_ folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if isDirectory(url) {
                if url.lastPathComponent == outputFolderName { enumerator.skipDescendants() }
                continue
            }
            if isImage(url) { files.append(url) }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

enum NamePlanner {
    static let defaultPattern = "opt-{name}"
    static let sampleNames = ["photo", "image"]

    static func baseNames(for names: [String], pattern: String, start: Int) -> [String] {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        let effective = trimmed.isEmpty ? "{name}" : trimmed
        let first = max(start, 0)
        let last = first + max(names.count - 1, 0)
        let digits = String(last).count
        return names.enumerated().map { index, name in
            var result = effective.replacingOccurrences(of: "{name}", with: name)
            result = result.replacingOccurrences(of: "{n}", with: padded(first + index, digits))
            result = result.replacingOccurrences(of: "{n-}", with: padded(last - index, digits))
            return sanitized(result, fallback: name)
        }
    }

    static func preview(names: [String], pattern: String, start: Int, format: OutputFormat) -> String {
        let bases = baseNames(for: names.isEmpty ? sampleNames : names, pattern: pattern, start: start)
        return bases.prefix(2).map { "\($0).\(format.fileExtension)" }.joined(separator: ", ")
    }

    private static func padded(_ number: Int, _ digits: Int) -> String {
        let text = String(number)
        return String(repeating: "0", count: max(digits - text.count, 0)) + text
    }

    private static func sanitized(_ name: String, fallback: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? fallback : cleaned
    }
}

struct Bitmap {
    let context: CGContext
    let width: Int
    let height: Int
    let hasAlpha: Bool

    var size: PixelSize { PixelSize(width: width, height: height) }
}

enum ImageDecoder {
    static func sourceSize(_ source: CGImageSource) -> PixelSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return PixelSize(width: width, height: height)
    }

    static func decode(_ url: URL, maxEdge: Int, flattenOnWhite: Bool) throws -> (original: PixelSize, bitmap: Bitmap) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let original = sourceSize(source) else {
            throw OptimizeError("Not a readable image")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let sourceHasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let target = maxEdge > 0 ? min(maxEdge, original.longEdge) : original.longEdge
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw OptimizeError("Could not decode image")
        }
        let imageHasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: imageHasAlpha = false
        default: imageHasAlpha = true
        }
        let hasAlpha = (sourceHasAlpha || imageHasAlpha) && !flattenOnWhite
        let width = image.width
        let height = image.height
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alphaInfo.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw OptimizeError("Could not create bitmap")
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if hasAlpha {
            context.clear(rect)
        } else {
            context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 1, 1, 1])!)
            context.fill(rect)
        }
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return (original, Bitmap(context: context, width: width, height: height, hasAlpha: hasAlpha))
    }
}

enum Encoder {
    static func encode(_ bitmap: Bitmap, format: OutputFormat, quality: Int) throws -> Data {
        switch format {
        case .webp: return try encodeWebP(bitmap, quality: quality)
        case .avif, .jpeg, .png: return try encodeImageIO(bitmap, format: format, quality: quality)
        }
    }

    private static func encodeImageIO(_ bitmap: Bitmap, format: OutputFormat, quality: Int) throws -> Data {
        guard let type = format.imageIOType, let image = bitmap.context.makeImage() else {
            throw OptimizeError("Could not create image")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
            throw OptimizeError("\(format.title) encoding is not available on this Mac")
        }
        var properties: [CFString: Any] = [:]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(min(max(quality, 1), 100)) / 100
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw OptimizeError("\(format.title) encoding failed")
        }
        switch format {
        case .jpeg: return MetadataStripper.stripJPEG(data as Data)
        case .png: return MetadataStripper.stripPNG(data as Data)
        default: return data as Data
        }
    }

    private static func encodeWebP(_ bitmap: Bitmap, quality: Int) throws -> Data {
        var config = WebPConfig()
        let preset = bitmap.hasAlpha ? WEBP_PRESET_PICTURE : WEBP_PRESET_PHOTO
        guard WebPConfigPreset(&config, preset, Float(min(max(quality, 1), 100))) != 0 else {
            throw OptimizeError("WebP configuration failed")
        }
        config.method = 4
        config.use_sharp_yuv = 1
        config.thread_level = 1
        guard WebPValidateConfig(&config) != 0 else {
            throw OptimizeError("WebP configuration is invalid")
        }
        guard let data = bitmap.context.data else {
            throw OptimizeError("Bitmap has no pixel data")
        }
        let stride = bitmap.context.bytesPerRow
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        if bitmap.hasAlpha { unpremultiply(pixels, width: bitmap.width, height: bitmap.height, stride: stride) }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else {
            throw OptimizeError("WebP picture setup failed")
        }
        defer { WebPPictureFree(&picture) }
        picture.width = Int32(bitmap.width)
        picture.height = Int32(bitmap.height)
        picture.use_argb = 1
        let imported = bitmap.hasAlpha
            ? WebPPictureImportRGBA(&picture, pixels, Int32(stride))
            : WebPPictureImportRGBX(&picture, pixels, Int32(stride))
        guard imported != 0 else {
            throw OptimizeError("WebP could not import pixels")
        }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite
        let encoded = withUnsafeMutablePointer(to: &writer) { pointer -> Int32 in
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        guard encoded != 0, let bytes = writer.mem else {
            throw OptimizeError("WebP encoding failed (code \(picture.error_code.rawValue))")
        }
        return Data(bytes: bytes, count: writer.size)
    }

    private static func unpremultiply(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, stride: Int) {
        for y in 0..<height {
            let row = pixels + y * stride
            for x in 0..<width {
                let offset = x * 4
                let alpha = Int(row[offset + 3])
                guard alpha != 0, alpha != 255 else { continue }
                for channel in 0..<3 {
                    row[offset + channel] = UInt8(min(255, (Int(row[offset + channel]) * 255 + alpha / 2) / alpha))
                }
            }
        }
    }
}

enum MetadataStripper {
    private static let droppedPNGChunks: Set<String> = ["eXIf", "iCCP", "tEXt", "zTXt", "iTXt", "tIME"]

    static func stripJPEG(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return data }
        var output = [UInt8]()
        output.reserveCapacity(bytes.count)
        output.append(contentsOf: bytes[0..<2])
        var index = 2
        while index + 4 <= bytes.count, bytes[index] == 0xFF {
            let marker = bytes[index + 1]
            if marker == 0xDA { break }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                output.append(contentsOf: bytes[index..<index + 2])
                index += 2
                continue
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let end = index + 2 + length
            guard length >= 2, end <= bytes.count else { return data }
            let payload = bytes[(index + 4)..<end]
            let isExif = marker == 0xE1 && payload.starts(with: Array("Exif".utf8))
            let isXMP = marker == 0xE1 && payload.starts(with: Array("http://ns.adobe.com/xap/1.0/".utf8))
            let isICC = marker == 0xE2 && payload.starts(with: Array("ICC_PROFILE".utf8))
            let isPhotoshop = marker == 0xED
            let isComment = marker == 0xFE
            if !(isExif || isXMP || isICC || isPhotoshop || isComment) {
                output.append(contentsOf: bytes[index..<end])
            }
            index = end
        }
        output.append(contentsOf: bytes[index...])
        return Data(output)
    }

    static func stripPNG(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 8 else { return data }
        var output = [UInt8]()
        output.reserveCapacity(bytes.count)
        output.append(contentsOf: bytes[0..<8])
        var index = 8
        while index + 12 <= bytes.count {
            let length = Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let end = index + 12 + length
            guard end <= bytes.count else { return data }
            let type = String(decoding: bytes[(index + 4)..<(index + 8)], as: UTF8.self)
            if !droppedPNGChunks.contains(type) {
                output.append(contentsOf: bytes[index..<end])
            }
            index = end
        }
        output.append(contentsOf: bytes[index...])
        return Data(output)
    }
}

final class Optimizer {
    struct Job {
        let source: URL
        let output: URL
    }

    private let queue = OperationQueue()
    private let callbackQueue: DispatchQueue
    private let lock = NSLock()
    private(set) var isRunning = false

    init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
        queue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        queue.qualityOfService = .userInitiated
    }

    static func outputDirectory(for source: URL, destination: Destination) -> URL {
        switch destination {
        case .subfolder: return source.deletingLastPathComponent().appendingPathComponent(ImageCollector.outputFolderName, isDirectory: true)
        case .replace: return source.deletingLastPathComponent()
        case .folder(let url): return url
        }
    }

    static func plan(files: [URL], options: OptimizeOptions) -> [Job] {
        let names = NamePlanner.baseNames(for: files.map { $0.deletingPathExtension().lastPathComponent }, pattern: options.pattern, start: options.startNumber)
        var used = Set<String>()
        var jobs: [Job] = []
        for (source, base) in zip(files, names) {
            let directory = outputDirectory(for: source, destination: options.destination)
            let sourceKey = source.standardizedFileURL.path.lowercased()
            var suffix = 1
            while true {
                let name = suffix == 1 ? base : "\(base)-\(suffix)"
                let candidate = directory.appendingPathComponent(name).appendingPathExtension(options.format.fileExtension)
                let key = candidate.standardizedFileURL.path.lowercased()
                let replacesItself = options.destination == .replace && key == sourceKey
                let taken = used.contains(key) || (!replacesItself && FileManager.default.fileExists(atPath: candidate.path))
                if !taken {
                    used.insert(key)
                    jobs.append(Job(source: source, output: candidate))
                    break
                }
                suffix += 1
            }
        }
        return jobs
    }

    static func process(_ job: Job, options: OptimizeOptions) -> FileReport {
        var report = FileReport(source: job.source)
        report.originalBytes = fileSize(job.source)
        do {
            let decoded = try ImageDecoder.decode(job.source, maxEdge: options.maxEdge, flattenOnWhite: options.format == .jpeg)
            report.originalSize = decoded.original
            report.newSize = decoded.bitmap.size
            let data = try Encoder.encode(decoded.bitmap, format: options.format, quality: options.quality)
            try write(data, job: job, options: options)
            report.output = job.output
            report.newBytes = data.count
        } catch {
            report.error = error.localizedDescription
            log("\(job.source.lastPathComponent): \(error.localizedDescription)")
        }
        return report
    }

    private static func write(_ data: Data, job: Job, options: OptimizeOptions) throws {
        let manager = FileManager.default
        let directory = job.output.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let replacesItself = options.destination == .replace && job.output.standardizedFileURL.path.lowercased() == job.source.standardizedFileURL.path.lowercased()
        if replacesItself {
            try manager.trashItem(at: job.source, resultingItemURL: nil)
            try data.write(to: job.output, options: .atomic)
        } else {
            try data.write(to: job.output, options: .atomic)
            if options.destination == .replace {
                try manager.trashItem(at: job.source, resultingItemURL: nil)
            }
        }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    func run(files: [URL], options: OptimizeOptions, progress: @escaping (Int, Int, FileReport) -> Void, completion: @escaping (BatchReport) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        let started = Date()
        let jobs = Self.plan(files: files, options: options)
        let total = jobs.count
        var results = [FileReport?](repeating: nil, count: total)
        var completed = 0
        let group = DispatchGroup()
        for (index, job) in jobs.enumerated() {
            group.enter()
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak operation, weak self] in
                guard let self, operation?.isCancelled != true else { return }
                let report = Self.process(job, options: options)
                self.lock.lock()
                results[index] = report
                completed += 1
                let count = completed
                self.lock.unlock()
                self.callbackQueue.async { progress(count, total, report) }
            }
            operation.completionBlock = { group.leave() }
            queue.addOperation(operation)
        }
        group.notify(queue: callbackQueue) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let files = results.compactMap { $0 }
            let cancelled = files.count < total
            self.lock.unlock()
            self.isRunning = false
            let report = BatchReport(files: files, cancelled: cancelled, duration: Date().timeIntervalSince(started))
            log("batch finished: \(report.summary) in \(Format.seconds(report.duration))")
            completion(report)
        }
    }

    func cancel() {
        queue.cancelAllOperations()
    }
}

enum CLI {
    static func run(_ arguments: [String]) -> Int32 {
        var options = OptimizeOptions()
        var inputs: [URL] = []
        var index = 0
        func next(_ flag: String) -> String? {
            index += 1
            guard index < arguments.count else {
                FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8))
                return nil
            }
            return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--format":
                guard let value = next(argument), let format = OutputFormat(rawValue: value.lowercased()) else { return usage() }
                options.format = format
            case "--width", "--max-edge":
                guard let value = next(argument), let number = Int(value) else { return usage() }
                options.maxEdge = number
            case "--quality":
                guard let value = next(argument), let number = Int(value) else { return usage() }
                options.quality = number
            case "--out":
                guard let value = next(argument) else { return usage() }
                options.destination = .folder(URL(fileURLWithPath: value, isDirectory: true))
            case "--pattern":
                guard let value = next(argument) else { return usage() }
                options.pattern = value
            case "--start":
                guard let value = next(argument), let number = Int(value) else { return usage() }
                options.startNumber = number
            case "--replace":
                options.destination = .replace
            case "--subfolder":
                options.destination = .subfolder
            case "--help", "-h":
                return usage()
            default:
                inputs.append(URL(fileURLWithPath: argument))
            }
            index += 1
        }
        let files = ImageCollector.collect(inputs)
        guard !files.isEmpty else {
            print("No images found")
            return 1
        }
        let optimizer = Optimizer(callbackQueue: DispatchQueue(label: "cz.vojtechokenka.squeeze.cli"))
        let done = DispatchSemaphore(value: 0)
        var batch: BatchReport?
        print("\(files.count) \(files.count == 1 ? "image" : "images") → \(options.format.title), quality \(options.quality), max edge \(options.maxEdge == 0 ? "unchanged" : "\(options.maxEdge) px"), pattern \(options.pattern)")
        optimizer.run(files: files, options: options, progress: { _, _, _ in }, completion: { report in
            batch = report
            done.signal()
        })
        done.wait()
        guard let report = batch else { return 1 }
        for file in report.files {
            let name = file.source.lastPathComponent
            if let error = file.error {
                print("\(name)  error: \(error)")
                continue
            }
            let sizes = "\(file.originalSize?.text ?? "?") → \(file.newSize?.text ?? "?")"
            let bytes = "\(Format.bytes(file.originalBytes)) → \(Format.bytes(file.newBytes)) (\(Format.change(from: file.originalBytes, to: file.newBytes)))"
            print("\(name)  \(sizes)  \(bytes)  → \(file.output?.path ?? "?")")
        }
        print("Total: \(report.summary), \(Format.seconds(report.duration))")
        return report.failed.isEmpty ? 0 : 1
    }

    private static func usage() -> Int32 {
        print("usage: Squeeze --cli [--format webp|avif|jpeg|png] [--quality 1-100] [--width px] [--out dir | --replace | --subfolder] [--pattern \"opt-{name}\"] [--start n] files…")
        return 2
    }
}
