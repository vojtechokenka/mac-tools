import Foundation
import ImageIO
import CoreGraphics
import Quartz
import PDFKit

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

enum PDFResolution: String, CaseIterable {
    case dpi150 = "150", dpi100 = "100", dpi72 = "72", keep

    var title: String { self == .keep ? "Keep" : "\(rawValue) dpi" }
    var dpi: Int? { Int(rawValue) }
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
    var pdfDpi = PDFResolution.dpi150
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
    var pageCount: Int?
    var noGain = false
    var error: String?

    var succeeded: Bool { error == nil }
    var isPDF: Bool { ImageCollector.isPDF(source) }

    var detail: String {
        var text = "\(Format.bytes(originalBytes)) → \(Format.bytes(newBytes)) (\(Format.change(from: originalBytes, to: newBytes)))"
        if let pageCount { text = "\(pageCount) \(pageCount == 1 ? "page" : "pages"), " + text }
        if noGain { text += " (no gain)" }
        return text
    }
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
        var text = Format.count(done.count, images: !files.contains { $0.isPDF })
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
        if index == 1 { return String(format: "%.0f KB", value) }
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

    static func count(_ number: Int, images: Bool) -> String {
        let noun = images ? "image" : "file"
        return "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}

enum ImageCollector {
    static let extensions: Set<String> = ["jpg", "jpeg", "jpe", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "avif", "bmp"]
    static let outputFolderName = "optimized"

    static func isImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    static func isSupported(_ url: URL) -> Bool {
        isImage(url) || isPDF(url)
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    static func accepts(_ url: URL) -> Bool {
        isDirectory(url) || isSupported(url)
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
            } else if isSupported(url) {
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
            if isSupported(url) { files.append(url) }
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

    static func preview(files: [URL], pattern: String, start: Int, format: OutputFormat) -> String {
        let names = files.isEmpty ? sampleNames : files.map { $0.deletingPathExtension().lastPathComponent }
        let extensions = files.isEmpty ? sampleNames.map { _ in format.fileExtension } : files.map { ImageCollector.isPDF($0) ? "pdf" : format.fileExtension }
        let bases = baseNames(for: names, pattern: pattern, start: start)
        return zip(bases, extensions).prefix(2).map { "\($0).\($1)" }.joined(separator: ", ")
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

enum PDFCompressor {
    static func filter(quality: Int, maxPixels: Int?) throws -> QuartzFilter {
        var image: [String: Any] = [
            "Compression Quality": Double(min(max(quality, 1), 100)) / 100,
            "ImageCompression": "ImageJPEGCompress",
        ]
        if let maxPixels {
            image["ImageScaleSettings"] = ["ImageScaleFactor": 1.0, "ImageSizeMax": maxPixels, "ImageSizeMin": 128, "ImageScaleInterpolate": true]
        }
        let properties: [AnyHashable: Any] = [
            "Domains": ["Applications": true],
            "FilterType": 1,
            "Name": "Squeeze",
            "FilterData": ["ColorSettings": ["ImageSettings": image]],
        ]
        guard let filter = QuartzFilter(properties: properties) else { throw OptimizeError("Could not create PDF filter") }
        return filter
    }

    static func maxPixels(in document: PDFDocument, dpi: Int) -> Int {
        var longest: CGFloat = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let box = page.bounds(for: .cropBox)
            longest = max(longest, box.width, box.height)
        }
        return max(Int((longest / 72 * CGFloat(dpi)).rounded()), 128)
    }

    static func rotationTransform(_ page: PDFPage) -> CGAffineTransform {
        let box = page.bounds(for: .cropBox)
        switch ((page.rotation % 360) + 360) % 360 {
        case 90: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: box.width)
        case 180: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: box.width, ty: box.height)
        case 270: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: box.height, ty: 0)
        default: return .identity
        }
    }

    static func open(_ source: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: source) else { throw OptimizeError("Not a readable PDF") }
        if document.isEncrypted || document.isLocked {
            log("\(source.lastPathComponent): encrypted PDF (locked: \(document.isLocked)), skipped")
            throw OptimizeError("Encrypted PDF skipped")
        }
        guard document.pageCount > 0, document.page(at: 0) != nil else { throw OptimizeError("PDF has no pages") }
        return document
    }

    static func compress(_ document: PDFDocument, to output: URL, resolution: PDFResolution, quality: Int) throws -> Int {
        let pageCount = document.pageCount
        guard let first = document.page(at: 0) else { throw OptimizeError("PDF has no pages") }
        let filter = try filter(quality: quality, maxPixels: resolution.dpi.map { maxPixels(in: document, dpi: $0) })
        var mediaBox = first.bounds(for: .cropBox)
        let info: [CFString: Any] = [kCGPDFContextTitle: "", kCGPDFContextAuthor: "", kCGPDFContextSubject: "", kCGPDFContextKeywords: "", kCGPDFContextCreator: ""]
        guard let context = CGContext(output as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
            throw OptimizeError("Could not create PDF output")
        }
        filter.apply(to: context)
        let transforms = (0..<pageCount).map { index -> CGAffineTransform in
            guard let page = document.page(at: index) else { return .identity }
            let crop = page.bounds(for: .cropBox)
            return CGAffineTransform(translationX: -crop.minX, y: -crop.minY).concatenating(rotationTransform(page))
        }
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let swapped = page.rotation % 180 != 0
            var box = CGRect(x: 0, y: 0, width: swapped ? bounds.height : bounds.width, height: swapped ? bounds.width : bounds.height)
            let transform = rotationTransform(page)
            page.rotation = 0
            let pageInfo = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.saveGState()
            context.concatenate(transform)
            page.draw(with: .cropBox, to: context)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        try copyLinks(from: document, to: output, transforms: transforms)
        return pageCount
    }

    static func copyLinks(from document: PDFDocument, to output: URL, transforms: [CGAffineTransform]) throws {
        let links = (0..<document.pageCount).map { document.page(at: $0)?.annotations.filter { $0.type == "Link" } ?? [] }
        guard links.contains(where: { !$0.isEmpty }) || document.outlineRoot != nil else { return }
        guard let copy = PDFDocument(url: output) else { throw OptimizeError("Could not reopen PDF output") }
        func remap(_ destination: PDFDestination?) -> PDFDestination? {
            guard let destination, let page = destination.page else { return nil }
            let index = document.index(for: page)
            guard index < transforms.count, let target = copy.page(at: index) else { return nil }
            let point = destination.point
            let unspecified = point.x == kPDFDestinationUnspecifiedValue || point.y == kPDFDestinationUnspecifiedValue
            return PDFDestination(page: target, at: unspecified ? point : point.applying(transforms[index]))
        }
        var count = 0
        for (index, annotations) in links.enumerated() {
            guard let target = copy.page(at: index) else { continue }
            for annotation in annotations {
                let link = PDFAnnotation(bounds: annotation.bounds.applying(transforms[index]), forType: .link, withProperties: nil)
                link.border = annotation.border
                link.url = annotation.url
                if let destination = remap(annotation.destination) { link.destination = destination }
                target.addAnnotation(link)
                count += 1
            }
        }
        func copyOutline(_ source: PDFOutline) -> PDFOutline {
            let outline = PDFOutline()
            outline.label = source.label
            if let destination = remap(source.destination) { outline.destination = destination }
            if let action = source.action as? PDFActionURL, let url = action.url { outline.action = PDFActionURL(url: url) }
            for child in 0..<source.numberOfChildren {
                if let item = source.child(at: child) { outline.insertChild(copyOutline(item), at: child) }
            }
            return outline
        }
        if let root = document.outlineRoot { copy.outlineRoot = copyOutline(root) }
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".squeeze-\(UUID().uuidString).pdf")
        guard copy.write(to: temporary) else {
            try? FileManager.default.removeItem(at: temporary)
            throw OptimizeError("Could not write PDF links")
        }
        _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
        log("\(document.documentURL?.lastPathComponent ?? output.lastPathComponent): restored \(count) link(s)\(document.outlineRoot == nil ? "" : " and outline")")
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
                let candidate = directory.appendingPathComponent(name).appendingPathExtension(ImageCollector.isPDF(source) ? "pdf" : options.format.fileExtension)
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
        if ImageCollector.isPDF(job.source) { return processPDF(job, options: options) }
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

    private static func processPDF(_ job: Job, options: OptimizeOptions) -> FileReport {
        var report = FileReport(source: job.source)
        report.originalBytes = fileSize(job.source)
        let manager = FileManager.default
        let directory = job.output.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".squeeze-\(UUID().uuidString).pdf")
        do {
            let document = try PDFCompressor.open(job.source)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            report.pageCount = try PDFCompressor.compress(document, to: temporary, resolution: options.pdfDpi, quality: options.quality)
            let newBytes = fileSize(temporary)
            report.noGain = newBytes >= report.originalBytes
            if report.noGain && options.destination == .replace {
                try? manager.removeItem(at: temporary)
                report.newBytes = report.originalBytes
                log("\(job.source.lastPathComponent): no gain, original kept")
                return report
            }
            try move(temporary, job: job, options: options)
            report.output = job.output
            report.newBytes = newBytes
        } catch {
            try? manager.removeItem(at: temporary)
            report.error = error.localizedDescription
            log("\(job.source.lastPathComponent): \(error.localizedDescription)")
        }
        return report
    }

    private static func move(_ temporary: URL, job: Job, options: OptimizeOptions) throws {
        let manager = FileManager.default
        let replacesItself = options.destination == .replace && job.output.standardizedFileURL.path.lowercased() == job.source.standardizedFileURL.path.lowercased()
        if replacesItself {
            try manager.trashItem(at: job.source, resultingItemURL: nil)
            try manager.moveItem(at: temporary, to: job.output)
        } else {
            try manager.moveItem(at: temporary, to: job.output)
            if options.destination == .replace {
                try manager.trashItem(at: job.source, resultingItemURL: nil)
            }
        }
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
            case "--pdf-dpi":
                guard let value = next(argument), let resolution = PDFResolution(rawValue: value.lowercased()) else { return usage() }
                options.pdfDpi = resolution
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
            print("No images or PDFs found")
            return 1
        }
        let optimizer = Optimizer(callbackQueue: DispatchQueue(label: "cz.vojtechokenka.squeeze.cli"))
        let done = DispatchSemaphore(value: 0)
        var batch: BatchReport?
        print("\(Format.count(files.count, images: !files.contains { ImageCollector.isPDF($0) })) → \(options.format.title), quality \(options.quality), max edge \(options.maxEdge == 0 ? "unchanged" : "\(options.maxEdge) px"), PDF images \(options.pdfDpi.title.lowercased()), pattern \(options.pattern)")
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
            if file.isPDF {
                print("\(name)  \(file.detail)  → \(file.output?.path ?? "kept original")")
                continue
            }
            let sizes = "\(file.originalSize?.text ?? "?") → \(file.newSize?.text ?? "?")"
            print("\(name)  \(sizes)  \(file.detail)  → \(file.output?.path ?? "?")")
        }
        print("Total: \(report.summary), \(Format.seconds(report.duration))")
        return report.failed.isEmpty ? 0 : 1
    }

    private static func usage() -> Int32 {
        print("usage: Squeeze --cli [--format webp|avif|jpeg|png] [--quality 1-100] [--width px] [--pdf-dpi 150|100|72|keep] [--out dir | --replace | --subfolder] [--pattern \"opt-{name}\"] [--start n] files…")
        return 2
    }
}
