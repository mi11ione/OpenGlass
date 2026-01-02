import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Sandbox", systemImage: "square.on.square")
                }

            ShowcaseView()
                .tabItem {
                    Label("Showcase", systemImage: "sparkles.rectangle.stack")
                }

            ContainerView()
                .tabItem {
                    Label("Container", systemImage: "square.stack")
                }
        }
    }
}

#Preview {
    MainTabView()
}
