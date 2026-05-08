import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.settingsPath) {
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
        .environment(AppCoordinator())
}
