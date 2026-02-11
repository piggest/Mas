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
    @State private var selectedCategory: String? = nil
    @State private var selectedIDs: Set<UUID> = []
    @State private var lastSelectedID: UUID?
    @State private var showBulkDeleteConfirm = false
    @State private var showNewCategoryInput = false
    @State private var newCategoryName = ""
    @State private var pendingCategoryTargetIDs: Set<UUID> = []

    private var filteredEntries: [ScreenshotHistoryEntry] {
        var entries = viewModel.historyEntries
        if showFavoritesOnly {
            entries = entries.filter { $0.isFavorite == true }
        }
        if let category = selectedCategory {
            if category == "__uncategorized__" {
                entries = entries.filter { $0.category == nil }
            } else {
                entries = entries.filter { $0.category == category }
            }
        }
        return entries
    }

    var body: some View {
        VStack(spacing: 0) {
            // フィルターバー
            if !viewModel.historyEntries.isEmpty {
                HStack {
                    if selectedIDs.isEmpty {
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

                        // カテゴリフィルタメニュー
                        categoryFilterMenu
                    } else {
                        Button(action: { selectedIDs.removeAll() }) {
                            Text("選択解除")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(masuSub)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)

                        Button(action: { showBulkDeleteConfirm = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                Text("\(selectedIDs.count)件を削除")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        // 一括カテゴリ設定メニュー
                        bulkCategoryMenu
                    }
                    Spacer()
                    Text("\(selectedIDs.isEmpty ? "\(filteredEntries.count)件" : "\(selectedIDs.count)/\(filteredEntries.count)件選択")")
                        .font(.system(size: 11))
                        .foregroundColor(masuSub)
                    Button(action: { openSaveFolder() }) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundColor(masuSub)
                    }
                    .buttonStyle(.plain)
                    .help("保存フォルダを開く")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .alert("\(selectedIDs.count)件をライブラリから削除", isPresented: $showBulkDeleteConfirm) {
                    Button("削除", role: .destructive) {
                        viewModel.removeHistoryEntries(ids: selectedIDs)
                        selectedIDs.removeAll()
                    }
                    Button("キャンセル", role: .cancel) { }
                } message: {
                    Text("選択した\(selectedIDs.count)件をライブラリから削除しますか？\nファイル自体は削除されません。")
                }
            }

            if viewModel.historyEntries.isEmpty {
                HStack {
                    Spacer()
                    Button(action: { openSaveFolder() }) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundColor(masuSub)
                    }
                    .buttonStyle(.plain)
                    .help("保存フォルダを開く")
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
                } else if selectedCategory != nil {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "tag")
                            .font(.system(size: 36))
                            .foregroundColor(masuEdge)
                        Text("該当するエントリはありません")
                            .font(.body)
                            .foregroundColor(masuText)
                        Spacer()
                    }
                } else {
                    emptyState
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            let windowInfo = viewModel.editorWindows.first { info in
                                info.screenshot.savedURL?.path == entry.filePath
                            }
                            let isSelected = selectedIDs.contains(entry.id)
                            HistoryEntryRow(entry: entry, isOpen: windowInfo != nil, isPinned: windowInfo?.windowController.window?.level == .floating, isSelected: isSelected, hasSelection: !selectedIDs.isEmpty, categories: viewModel.getCategories(), onFavorite: {
                                viewModel.toggleFavorite(id: entry.id)
                            }, onTap: {
                                if let info = windowInfo {
                                    viewModel.closeEditorWindow(info)
                                } else {
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
                            }, onSetCategory: { category in
                                viewModel.setCategory(id: entry.id, category: category)
                            }, onNewCategory: {
                                pendingCategoryTargetIDs = [entry.id]
                                newCategoryName = ""
                                showNewCategoryInput = true
                            }, onCommandTap: {
                                if selectedIDs.contains(entry.id) {
                                    selectedIDs.remove(entry.id)
                                } else {
                                    selectedIDs.insert(entry.id)
                                }
                                lastSelectedID = entry.id
                            }, onShiftTap: {
                                guard let lastID = lastSelectedID else {
                                    selectedIDs.insert(entry.id)
                                    lastSelectedID = entry.id
                                    return
                                }
                                let entries = filteredEntries
                                guard let lastIndex = entries.firstIndex(where: { $0.id == lastID }),
                                      let currentIndex = entries.firstIndex(where: { $0.id == entry.id }) else {
                                    selectedIDs.insert(entry.id)
                                    lastSelectedID = entry.id
                                    return
                                }
                                let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
                                for i in range {
                                    selectedIDs.insert(entries[i].id)
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
        .alert("新規カテゴリ", isPresented: $showNewCategoryInput) {
            TextField("カテゴリ名", text: $newCategoryName)
            Button("追加") {
                let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                viewModel.setCategories(ids: pendingCategoryTargetIDs, category: name)
                pendingCategoryTargetIDs.removeAll()
            }
            Button("キャンセル", role: .cancel) {
                pendingCategoryTargetIDs.removeAll()
            }
        } message: {
            Text("新しいカテゴリ名を入力してください")
        }
    }

    // MARK: - カテゴリフィルタメニュー

    private var categoryFilterMenu: some View {
        Menu {
            Button(action: { selectedCategory = nil }) {
                if selectedCategory == nil {
                    Label("すべて", systemImage: "checkmark")
                } else {
                    Text("すべて")
                }
            }
            Divider()
            let categories = viewModel.getCategories()
            ForEach(categories, id: \.self) { cat in
                Button(action: { selectedCategory = cat }) {
                    if selectedCategory == cat {
                        Label(cat, systemImage: "checkmark")
                    } else {
                        Text(cat)
                    }
                }
            }
            if !categories.isEmpty {
                Divider()
            }
            Button(action: { selectedCategory = "__uncategorized__" }) {
                if selectedCategory == "__uncategorized__" {
                    Label("未分類", systemImage: "checkmark")
                } else {
                    Text("未分類")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                if let cat = selectedCategory {
                    Text(cat == "__uncategorized__" ? "未分類" : cat)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundColor(selectedCategory != nil ? masuBorder : masuSub)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selectedCategory != nil ? masuBorder.opacity(0.15) : Color.clear)
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - 一括カテゴリ設定メニュー

    private var bulkCategoryMenu: some View {
        Menu {
            let categories = viewModel.getCategories()
            ForEach(categories, id: \.self) { cat in
                Button(cat) {
                    viewModel.setCategories(ids: selectedIDs, category: cat)
                }
            }
            if !categories.isEmpty {
                Divider()
            }
            Button("新規カテゴリ…") {
                pendingCategoryTargetIDs = selectedIDs
                newCategoryName = ""
                showNewCategoryInput = true
            }
            Divider()
            Button("カテゴリを外す") {
                viewModel.setCategories(ids: selectedIDs, category: nil)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                Text("カテゴリ")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(masuSub)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(masuBorder.opacity(0.15))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func openSaveFolder() {
        let url = FileStorageService().getSaveFolder()
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            // フォルダが存在しなければ作成してから開く
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(masuEdge.opacity(0.6))
            Text("ライブラリは空です")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(masuText)
            Text("スクリーンショットを撮影すると\nここに表示されます")
                .font(.system(size: 13))
                .foregroundColor(masuSub)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Label("⌘ + Shift + 3 — 全画面", systemImage: "display")
                Label("⌘ + Shift + 4 — 範囲選択", systemImage: "crop")
                Label("⌘ + Shift + 5 — 枠を表示", systemImage: "rectangle.dashed")
            }
            .font(.system(size: 11))
            .foregroundColor(masuSub.opacity(0.8))
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(masuInner.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(masuBorder.opacity(0.3), lineWidth: 1)
                    )
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

struct HistoryEntryRow: View {
    static let thumbnailCache = NSCache<NSString, NSImage>()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    let entry: ScreenshotHistoryEntry
    var isOpen: Bool = false
    var isPinned: Bool = false
    var isSelected: Bool = false
    var hasSelection: Bool = false
    var categories: [String] = []
    var onFavorite: (() -> Void)?
    let onTap: () -> Void
    let onDelete: () -> Void
    var onFlash: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onSetCategory: ((String?) -> Void)?
    var onNewCategory: (() -> Void)?
    var onCommandTap: (() -> Void)?
    var onShiftTap: (() -> Void)?

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

                HStack(spacing: 6) {
                    Text(formattedDate)
                        .font(.system(size: 11))
                        .foregroundColor(masuSub)
                    if let category = entry.category {
                        Text(category)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(masuEdge)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(masuBorder.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                Text("\(entry.width) × \(entry.height)")
                    .font(.system(size: 11))
                    .foregroundColor(masuSub)
            }

            Spacer()

            if !hasSelection {
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
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
        }
        .padding(10)
        .background(
            isSelected
                ? Color.blue.opacity(0.12)
                : (isOpen
                    ? Color(red: 0.95, green: 0.88, blue: 0.70)
                    : (isHovering ? masuBorder.opacity(0.35) : masuInner))
        )
        // 内枠
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.blue : (isOpen ? Color(red: 0.80, green: 0.55, blue: 0.10) : masuBorder), lineWidth: isSelected ? 2.5 : (isOpen ? 2.5 : 1.5))
        )
        .cornerRadius(6)
        // 外枠との間にスペース
        .padding(3)
        // 外枠
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.blue.opacity(0.8) : (isOpen ? Color(red: 0.80, green: 0.55, blue: 0.10).opacity(0.8) : masuBorder.opacity(0.7)), lineWidth: isSelected ? 2.5 : (isOpen ? 2.5 : 1.5))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            TapGesture().modifiers(.shift).onEnded {
                onShiftTap?()
            }
        )
        .simultaneousGesture(
            TapGesture().modifiers(.command).onEnded {
                onCommandTap?()
            }
        )
        .onTapGesture {
            if hasSelection {
                onCommandTap?()
            } else {
                onTap()
            }
        }
        .contextMenu {
            Button("エディタで開く") { onTap() }
            Button("Finderで表示") { showInFinder() }
            Divider()
            Menu("カテゴリ設定") {
                ForEach(categories, id: \.self) { cat in
                    Button(action: { onSetCategory?(cat) }) {
                        if entry.category == cat {
                            Label(cat, systemImage: "checkmark")
                        } else {
                            Text(cat)
                        }
                    }
                }
                if !categories.isEmpty {
                    Divider()
                }
                Button("新規カテゴリ…") { onNewCategory?() }
                if entry.category != nil {
                    Divider()
                    Button("カテゴリを外す") { onSetCategory?(nil) }
                }
            }
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
        Self.dateFormatter.string(from: entry.timestamp)
    }

    private func loadThumbnail() {
        let cacheKey = entry.filePath as NSString
        if let cached = Self.thumbnailCache.object(forKey: cacheKey) {
            thumbnail = cached
            return
        }
        let filePath = entry.filePath
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: filePath)
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
            Self.thumbnailCache.setObject(resized, forKey: cacheKey)
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
