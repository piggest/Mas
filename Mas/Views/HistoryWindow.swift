import SwiftUI
import AppKit

// 升の木の色パレット
private let masuBg = Color(red: 0.92, green: 0.86, blue: 0.74)       // 全体背景（ベージュ）
private let masuInner = Color(red: 0.97, green: 0.94, blue: 0.88)    // カード内側（薄いクリーム）
private let masuBorder = Color(red: 0.75, green: 0.60, blue: 0.30)   // 枠線（ゴールド）
private let masuEdge = Color(red: 0.55, green: 0.42, blue: 0.25)     // 外枠（濃い茶）
private let masuText = Color(red: 0.30, green: 0.22, blue: 0.12)     // テキスト（こげ茶）
private let masuSub = Color(red: 0.45, green: 0.35, blue: 0.22)      // サブテキスト
private let masuBgInactive = Color(red: 0.88, green: 0.84, blue: 0.78) // 非アクティブ背景（くすんだベージュ）

struct HistoryWindow: View {
    @ObservedObject var viewModel: CaptureViewModel
    @State private var isWindowActive = true
    @State private var showFavoritesOnly = false

    private var filteredEntries: [ScreenshotHistoryEntry] {
        if showFavoritesOnly {
            return viewModel.historyEntries.filter { $0.isFavorite == true }
        }
        return viewModel.historyEntries
    }

    var body: some View {
        VStack(spacing: 0) {
            // フィルターバー
            if !viewModel.historyEntries.isEmpty {
                HStack {
                    Button(action: { showFavoritesOnly.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                                .font(.system(size: 12))
                            Text(showFavoritesOnly ? "お気に入り" : "すべて")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(showFavoritesOnly ? Color(red: 0.85, green: 0.65, blue: 0.10) : masuSub)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(showFavoritesOnly ? Color(red: 0.85, green: 0.65, blue: 0.10).opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(filteredEntries.count)件")
                        .font(.system(size: 11))
                        .foregroundColor(masuSub)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            if filteredEntries.isEmpty {
                if showFavoritesOnly {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "star")
                            .font(.system(size: 36))
                            .foregroundColor(masuEdge)
                        Text("お気に入りはありません")
                            .font(.body)
                            .foregroundColor(masuText)
                        Spacer()
                    }
                } else {
                    emptyState
                }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            let windowInfo = viewModel.editorWindows.first { info in
                                info.screenshot.savedURL?.path == entry.filePath
                            }
                            HistoryEntryRow(entry: entry, isOpen: windowInfo != nil, isPinned: windowInfo?.windowController.window?.level == .floating, onFavorite: {
                                viewModel.toggleFavorite(id: entry.id)
                            }, onTap: {
                                if let info = windowInfo {
                                    // 表示中 → 非表示
                                    viewModel.closeEditorWindow(info)
                                } else {
                                    // 非表示 → 表示
                                    viewModel.openFromHistory(entry)
                                }
                            }, onDelete: {
                                viewModel.removeHistoryEntry(id: entry.id)
                            }, onFlash: {
                                viewModel.flashEditorWindow(for: entry)
                            }, onTogglePin: {
                                if let window = windowInfo?.windowController.window {
                                    window.level = window.level == .floating ? .normal : .floating
                                    viewModel.objectWillChange.send()
                                    NotificationCenter.default.post(name: .windowPinChanged, object: window)
                                }
                            })
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(isWindowActive ? masuBg : masuBgInactive)
        .frame(minWidth: 280, minHeight: 200)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window.title == "ライブラリ" {
                isWindowActive = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window.title == "ライブラリ" {
                isWindowActive = false
            }
        }
    }


    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundColor(masuEdge)
            Text("ライブラリは空です")
                .font(.body)
                .foregroundColor(masuText)
            Text("スクリーンショットを撮影すると\nここに表示されます")
                .font(.caption)
                .foregroundColor(masuSub)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

struct HistoryEntryRow: View {
    let entry: ScreenshotHistoryEntry
    var isOpen: Bool = false
    var isPinned: Bool = false
    var onFavorite: (() -> Void)?
    let onTap: () -> Void
    let onDelete: () -> Void
    var onFlash: (() -> Void)?
    var onTogglePin: (() -> Void)?

    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var showDeleteConfirm = false

    var body: some View {
        // 外枠
        HStack(spacing: 12) {
            // サムネイル
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(masuBg)
                        .frame(width: 120, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(masuSub)
                        )
                }
            }
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(masuEdge.opacity(0.5), lineWidth: 1)
            )

            // 情報
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Button(action: { onFavorite?() }) {
                        Image(systemName: entry.isFavorite == true ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(entry.isFavorite == true ? Color(red: 0.85, green: 0.65, blue: 0.10) : masuSub.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    Text(entry.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(masuText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isOpen {
                        Text("表示中")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(masuBorder)
                            .cornerRadius(3)
                    }
                }

                Text(formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(masuSub)

                Text("\(entry.width) × \(entry.height)")
                    .font(.system(size: 11))
                    .foregroundColor(masuSub)
            }

            Spacer()

            VStack(spacing: 8) {
                if isOpen {
                    Button(action: { onTogglePin?() }) {
                        Image(systemName: isPinned ? "pin.fill" : "pin.slash")
                            .font(.system(size: 18))
                            .foregroundColor(isPinned ? masuBorder : masuSub)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onFlash?() }) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18))
                            .foregroundColor(masuBorder)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(masuSub)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            isOpen
                ? Color(red: 0.95, green: 0.88, blue: 0.70)
                : (isHovering ? masuBorder.opacity(0.35) : masuInner)
        )
        // 内枠
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOpen ? Color(red: 0.80, green: 0.55, blue: 0.10) : masuBorder, lineWidth: isOpen ? 2.5 : 1.5)
        )
        .cornerRadius(6)
        // 外枠との間にスペース
        .padding(3)
        // 外枠
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isOpen ? Color(red: 0.80, green: 0.55, blue: 0.10).opacity(0.8) : masuBorder.opacity(0.7), lineWidth: isOpen ? 2.5 : 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("エディタで開く") { onTap() }
            Button("Finderで表示") { showInFinder() }
            Divider()
            Button("ライブラリから削除", role: .destructive) { onDelete() }
        }
        .alert("ライブラリから削除", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) { onDelete() }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("「\(entry.fileName)」をライブラリから削除しますか？\nファイル自体は削除されません。")
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: entry.timestamp)
    }

    private func loadThumbnail() {
        let url = URL(fileURLWithPath: entry.filePath)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = NSImage(contentsOf: url) else { return }
            let maxSize: CGFloat = 160
            let ratio = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
            let newSize = NSSize(
                width: image.size.width * ratio,
                height: image.size.height * ratio
            )
            let resized = NSImage(size: newSize)
            resized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .copy,
                       fraction: 1.0)
            resized.unlockFocus()
            DispatchQueue.main.async {
                self.thumbnail = resized
            }
        }
    }

    private func showInFinder() {
        let url = URL(fileURLWithPath: entry.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
