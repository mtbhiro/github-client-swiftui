import SwiftUI

struct AvatarImageView: View {
    let url: URL?
    var size: CGFloat = 40
    var shape: AvatarShape = .circle

    enum AvatarShape {
        case circle
        case roundedRect(cornerRadius: CGFloat)
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        placeholder
                    case .failure:
                        fallbackIcon
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(shapeView)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Color(.systemGray5)
    }

    private var fallbackIcon: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.tertiary)
    }

    private var shapeView: AnyShape {
        switch shape {
        case .circle:
            AnyShape(Circle())
        case let .roundedRect(cornerRadius):
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AvatarImageView(url: nil)
        AvatarImageView(url: nil, size: 48, shape: .roundedRect(cornerRadius: 8))
    }
}
