import SwiftUI

struct RepositoryRow: View {
    let repository: GitHubRepo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: repository.fullName.description)
                    .font(.headline)
                    .lineLimit(1)

                if let description = repository.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label("\(repository.stargazersCount)", systemImage: "star")
                    if let language = repository.language {
                        Label(language, systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var avatar: some View {
        AvatarImageView(url: repository.owner.avatarUrl, size: 40)
    }
}

#Preview {
    List {
        RepositoryRow(repository: .sampleSwift)
        RepositoryRow(repository: .sampleAlamofire)
        RepositoryRow(repository: .sampleVapor)
    }
    .listStyle(.plain)
}
