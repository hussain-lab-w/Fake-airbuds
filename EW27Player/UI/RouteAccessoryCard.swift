import SwiftUI
import UserNotifications

struct RouteAccessoryCard: View {
    let routeName: String
    @State private var visible = false
    @State private var displayedRoute = ""

    var body: some View {
        Group {
            if visible {
                HStack(spacing: 14) {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 30, weight: .semibold))
                        .symbolEffect(.pulse, options: .repeating)
                        .foregroundStyle(EW27Design.primaryText)
                        .padding(12)
                        .background(Circle().fill(LinearGradient(colors: [Color.cyan.opacity(0.9), Color.blue.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connected")
                            .font(.headline)
                            .foregroundStyle(EW27Design.primaryText)
                        Text(displayedRoute)
                            .font(.subheadline)
                            .foregroundStyle(EW27Design.primaryText.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .liquidGlass(prominent: true, tint: EW27Design.accent.opacity(0.18))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: routeName) { _, newValue in showRoute(newValue) }
        .onAppear { if !routeName.isEmpty && routeName != AudioPlayer.noRoute { showRoute(routeName) } }
    }

    private func showRoute(_ name: String) {
        guard !name.isEmpty, name != AudioPlayer.noRoute, name != displayedRoute else { return }
        displayedRoute = name
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { visible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeOut(duration: 0.3)) { visible = false }
        }
        guard UIApplication.shared.applicationState != .active else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Connected to an audio device"
            content.body = name
            content.sound = .default
            let request = UNNotificationRequest(identifier: "ew27-route-\(UUID().uuidString)", content: content, trigger: nil)
            center.add(request)
        }
    }
}
