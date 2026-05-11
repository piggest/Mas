import AppKit

class ClipboardService {

    func copyToClipboard(_ image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    func copyToClipboard(_ cgImage: CGImage) -> Bool {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        return copyToClipboard(nsImage)
    }

    /// 文字列をクリップボードへコピー（ファイルパス共有などに使う）。
    @discardableResult
    func copyToClipboard(string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}
