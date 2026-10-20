import SwiftUI

@main
struct GreeBarApp: App {
    @StateObject private var controller = ACController()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
        } label: {
            Image(systemName: controller.menuBarSymbol)
            if let text = controller.menuBarText {
                Text(text)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
