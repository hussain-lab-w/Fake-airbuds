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
                        .font(.system(size: 34, weight: .medium))
                        .symbolEffect(.pulse, options: .repeating)
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("تم الاتصال")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(displayedRoute)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(radius: 12)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: routeName) { _, newValue in showRoute(newValue) }
        .onAppear { if !routeName.isEmpty && routeName != "لا يوجد مسار" { showRoute(routeName) } }
    }

    private func showRoute(_ name: String) {
        guard !name.isEmpty, name != "لا يوجد مسار", name != displayedRoute else { return }
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
            content.title = "تم الاتصال بجهاز صوتي"
            content.body = name
            content.sound = .default
            let request = UNNotificationRequest(identifier: "ew27-route-\(UUID().uuidString)", content: content, trigger: nil)
            center.add(request)
        }
    }
}
