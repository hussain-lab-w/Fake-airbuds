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
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Circle().fill(LinearGradient(colors: [Color.cyan.opacity(0.9), Color.blue.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connected")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(displayedRoute)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .background(
                    LinearGradient(colors: [Color(red: 0.12, green: 0.2, blue: 0.38).opacity(0.97), Color(red: 0.16, green: 0.12, blue: 0.34).opacity(0.97)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.32), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: .black.opacity(0.32), radius: 18, y: 9)
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
