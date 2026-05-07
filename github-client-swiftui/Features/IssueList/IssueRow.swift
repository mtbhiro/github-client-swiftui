import SwiftUI

struct IssueRow: View {
    let issue: GitHubIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stateIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if !issue.labels.isEmpty {
                    labelsView
                }

                HStack(spacing: 8) {
                    Text("#\(issue.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(issue.user.login)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if issue.commentsCount > 0 {
                        Label("\(issue.commentsCount)", systemImage: "bubble.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var stateIcon: some View {
        Group {
            if issue.isPullRequest {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(issue.state == .open ? .green : .purple)
            } else {
                Image(systemName: issue.state == .open
                    ? "circle.circle"
                    : "checkmark.circle.fill")
                    .foregroundStyle(issue.state == .open ? .green : .purple)
            }
        }
        .font(.body)
    }

    private var labelsView: some View {
        HStack(spacing: 4) {
            ForEach(issue.labels.prefix(3)) { label in
                Text(label.name)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: label.color).opacity(0.2))
                    .foregroundStyle(Color(hex: label.color))
                    .clipShape(Capsule())
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    List {
        IssueRow(issue: .sampleOpen)
        IssueRow(issue: .sampleClosed)
        IssueRow(issue: .samplePullRequest)
    }
    .listStyle(.plain)
}
