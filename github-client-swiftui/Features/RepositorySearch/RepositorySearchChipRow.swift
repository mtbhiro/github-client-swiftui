import SwiftUI

struct RepositorySearchChipRow: View {
    let chips: [RepositorySearchChip]
    let onRemove: (RepositorySearchChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    HStack(spacing: 4) {
                        Text(chip.label)
                            .font(.caption)
                        Button {
                            onRemove(chip)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("条件を削除: \(chip.label)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color(.tertiarySystemBackground))
                    )
                    .overlay(
                        Capsule().stroke(Color(.separator), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
