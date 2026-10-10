import CoreGraphics
import Foundation
import ImageIO

/// A decoded, downsampled bitmap. `CGImage` is immutable, so sharing it across actors is safe.
nonisolated final class DecodedImage: @unchecked Sendable {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// Identifies a decoded image: the same URL decoded for very different sizes is cached separately.
nonisolated struct ImageRequestKey: Hashable, Sendable {
    let url: URL
    let maxPixelSize: Int

    /// Buckets the requested size so small layout differences reuse the same decode.
    init(url: URL, pointSize: CGSize, scale: CGFloat) {
        self.url = url
        let longest = max(pointSize.width, pointSize.height) * max(scale, 1)
        let bucket: CGFloat = 128
        maxPixelSize = max(Int((longest / bucket).rounded(.up) * bucket), Int(bucket))
    }
}

/// Synchronous memory cache so cells re-entering the screen show their image on the first frame.
nonisolated final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    // NSCache is documented as thread-safe.
    private let cache: NSCache<KeyBox, DecodedImage> = {
        let cache = NSCache<KeyBox, DecodedImage>()
        cache.totalCostLimit = 96 << 20
        return cache
    }()

    func image(for key: ImageRequestKey) -> DecodedImage? {
        cache.object(forKey: KeyBox(key))
    }

    func insert(_ image: DecodedImage, for key: ImageRequestKey) {
        let cost = image.cgImage.bytesPerRow * image.cgImage.height
        cache.setObject(image, forKey: KeyBox(key), cost: cost)
    }

    private final class KeyBox: NSObject {
        let key: ImageRequestKey
        init(_ key: ImageRequestKey) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }
}

nonisolated enum ImagePipelineError: Error {
    case badResponse(Int)
    case undecodable
}

/// Loads remote artwork once per URL and size: de-duplicates concurrent requests,
/// caches bytes on disk (URLCache) and decoded bitmaps in memory, and downsamples with ImageIO
/// so large CDN images never decode at full resolution.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let session: URLSession
    private let memory: ImageMemoryCache
    private var inFlight: [ImageRequestKey: Task<DecodedImage, any Error>] = [:]

    init(memory: ImageMemoryCache = .shared) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        self.memory = memory
    }

    func image(for key: ImageRequestKey) async throws -> DecodedImage {
        if let cached = memory.image(for: key) {
            return cached
        }
        if let running = inFlight[key] {
            return try await running.value
        }
        let session = session
        let task = Task<DecodedImage, any Error> {
            try await Self.fetch(key, session: session)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let image = try await task.value
        memory.insert(image, for: key)
        return image
    }

    @concurrent
    private static func fetch(_ key: ImageRequestKey, session: URLSession) async throws -> DecodedImage {
        let (data, response) = try await session.data(from: key.url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw ImagePipelineError.badResponse(status)
        }
        try Task.checkCancellation()
        return try downsample(data, maxPixelSize: key.maxPixelSize)
    }

    private nonisolated static func downsample(_ data: Data, maxPixelSize: Int) throws -> DecodedImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ImagePipelineError.undecodable
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw ImagePipelineError.undecodable
        }
        return DecodedImage(cgImage: image)
    }
}
