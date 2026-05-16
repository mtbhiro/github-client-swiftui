import SwiftUI

struct RepositoryRow: View {
    let repository: GitHubRepo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: String(describing: repository.fullName))
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

    @ViewBuilder
    private var avatar: some View {
        if let url = repository.owner.avatarUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty:
                    ProgressView()
                case .failure:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.tertiary)
                @unknown default:
                    Color.clear
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 40, height: 40)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
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
