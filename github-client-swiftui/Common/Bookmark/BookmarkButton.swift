import SwiftUI

struct BookmarkButton: View {
    let isBookmarked: Bool
    let action: () -> Void

    @State private var showConfirmation = false

    var body: some View {
        Button {
            if isBookmarked {
                showConfirmation = true
            } else {
                action()
            }
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .foregroundStyle(isBookmarked ? .yellow : .secondary)
                .font(.body)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .alert("ブックマークを削除", isPresented: $showConfirmation) {
            Button("削除", role: .destructive) {
                action()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("このブックマークを削除しますか？")
        }
    }
}
