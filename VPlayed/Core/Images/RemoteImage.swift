import SwiftUI

/// Artwork loaded through `ImagePipeline`, sized to the space it is given.
/// Shows a neutral frame while loading and an image glyph if the URL is missing or fails.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center
    var showsFailureIcon = true

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            RemoteImageContent(
                url: url,
                size: proxy.size,
                scale: displayScale,
                contentMode: contentMode,
                alignment: alignment,
                showsFailureIcon: showsFailureIcon
            )
        }
    }
}

private struct RemoteImageContent: View {
    let url: URL?
    let size: CGSize
    let scale: CGFloat
    let contentMode: ContentMode
    let alignment: Alignment
    let showsFailureIcon: Bool

    @State private var loaded: (key: ImageRequestKey, image: DecodedImage)?
    @State private var failedKey: ImageRequestKey?

    private var key: ImageRequestKey? {
        guard let url, size.width > 0, size.height > 0 else { return nil }
        return ImageRequestKey(url: url, pointSize: size, scale: scale)
    }

    var body: some View {
        let key = key
        let image = key.flatMap { key in
            loaded?.key == key ? loaded?.image : ImageMemoryCache.shared.image(for: key)
        }

        ZStack(alignment: alignment) {
            if let image {
                Image(decorative: image.cgImage, scale: scale)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: size.width, height: size.height, alignment: alignment)
            } else if showsFailureIcon, url == nil || (key != nil && failedKey == key) {
                Theme.Palette.neutral700
                Image(systemName: "photo")
                    .font(.system(size: min(32, size.height * 0.3)))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: alignment)
        .clipped()
        .task(id: key) {
            guard let key, image == nil else { return }
            do {
                let decoded = try await ImagePipeline.shared.image(for: key)
                loaded = (key, decoded)
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { failedKey = key }
            }
        }
    }
}
