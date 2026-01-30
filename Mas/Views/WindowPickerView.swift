import SwiftUI

struct WindowPickerView: View {
    let windows: [ScreenCaptureService.WindowInfo]
    let onSelect: (ScreenCaptureService.WindowInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("キャプチャするウィンドウを選択")
                .font(.headline)
                .padding()

            Divider()

            if windows.isEmpty {
                VStack {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("利用可能なウィンドウがありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                        ForEach(windows) { window in
                            WindowThumbnailView(window: window) {
                                onSelect(window)
                                dismiss()
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("キャンセル") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
    }
}

struct WindowThumbnailView: View {
    let window: ScreenCaptureService.WindowInfo
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: "macwindow")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.ownerName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !window.name.isEmpty {
                        Text(window.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
