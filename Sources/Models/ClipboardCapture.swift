import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum ItemKind: String, Codable, CaseIterable, Sendable {
    case text
    case link
    case code
    case image

    var isImage: Bool { self == .image }

    var displayName: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .code: "Code"
        case .image: "Image"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        }
    }
}

enum ImageFormat: String, Codable, Sendable {
    case png, jpeg, gif, tiff, heic, bmp, unknown

    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .gif: .gif
        case .tiff: .tiff
        case .heic: UTType("public.heic") ?? .image
        case .bmp: .bmp
        case .unknown: .image
        }
    }

    var fileExtension: String {
        switch self {
        case .unknown: "dat"
        case .jpeg: "jpg"
        default: rawValue
        }
    }

    var displayName: String {
        self == .unknown ? "Image" : rawValue.uppercased()
    }

    static func from(utType: UTType) -> ImageFormat {
        switch utType {
        case .png: .png
        case .jpeg: .jpeg
        case .gif: .gif
        case .tiff: .tiff
        case .bmp: .bmp
        default: utType.identifier == "public.heic" ? .heic : .unknown
        }
    }
}

struct SourceApp: Sendable, Hashable {
    let bundleID: String?
    let name: String?
}

/// Снимок содержимого буфера — обычное значение, живёт до записи в стор.
/// Sendable, чтобы безопасно уходить в actor'ы обработки изображений.
struct ClipboardCapture: Sendable {
    enum Payload: Sendable {
        case text(String)
        case image(data: Data, format: ImageFormat)
    }

    let payload: Payload
    let source: SourceApp?
    let capturedAt: Date

    var contentHash: String {
        switch payload {
        case .text(let text): ContentHash.of(text)
        case .image(let data, _): ContentHash.of(data)
        }
    }

    var byteSize: Int {
        switch payload {
        case .text(let text): text.utf8.count
        case .image(let data, _): data.count
        }
    }
}

/// Результат сохранения изображения на диск.
struct StoredImage: Sendable {
    let fileName: String
    let format: ImageFormat
    let byteSize: Int
    let pixelSize: CGSize
}
