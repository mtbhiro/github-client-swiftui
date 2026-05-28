import SwiftUI

struct ErrorStateView: View {
    let icon: String
    let message: String
    var detail: String?
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(message)
                .multilineTextAlignment(.center)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let retryAction {
                Button("再試行", action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Network Error") {
    ErrorStateView(
        icon: "wifi.exclamationmark",
        message: "通信に失敗しました",
        retryAction: {}
    )
}

#Preview("Generic Error") {
    ErrorStateView(
        icon: "exclamationmark.triangle",
        message: "リポジトリの取得に失敗しました",
        retryAction: {}
    )
}
