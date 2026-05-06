import SwiftUI

struct MyPageView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text("マイページ")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("マイページ")
        }
    }
}

#Preview {
    MyPageView()
}
