import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text("設定")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsView()
}
