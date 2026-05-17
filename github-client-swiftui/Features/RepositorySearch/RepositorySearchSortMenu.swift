import SwiftUI

struct RepositorySearchSortMenu: View {
    let current: RepositorySearchSort
    let onChange: (RepositorySearchSort) -> Void

    var body: some View {
        Menu {
            Section("ソートキー") {
                Button {
                    onChange(.init(key: .stars, order: current.order))
                } label: {
                    label(for: .stars)
                }
                Button {
                    onChange(.init(key: .updated, order: current.order))
                } label: {
                    label(for: .updated)
                }
            }
            Section("並び順") {
                Button {
                    onChange(.init(key: current.key, order: .desc))
                } label: {
                    label(for: .desc)
                }
                Button {
                    onChange(.init(key: current.key, order: .asc))
                } label: {
                    label(for: .asc)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(summary)
            }
            .font(.subheadline)
        }
        .accessibilityLabel("ソート切替")
    }

    private var summary: String {
        let arrow = current.order == .asc ? "↑" : "↓"
        return "\(current.key.rawValue) \(arrow)"
    }

    @ViewBuilder
    private func label(for key: RepositorySearchSortKey) -> some View {
        HStack {
            Text(key == .stars ? "スター数" : "最終更新")
            if current.key == key {
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func label(for order: RepositorySearchSortOrder) -> some View {
        HStack {
            Text(order == .desc ? "降順" : "昇順")
            if current.order == order {
                Image(systemName: "checkmark")
            }
        }
    }
}
