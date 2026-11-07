import SwiftUI

struct LyricsView: View {
    let title: String
    let artist: String
    let lyrics: String?

    @AppStorage("ew27.lyrics.fontSize.v1") private var fontSize = 22.0

    private var stanzas: [String] {
        let normalized = (lyrics ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasLyrics: Bool {
        !(lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                HStack {
                    Label("Lyrics", systemImage: "quote.bubble")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Spacer()
                    Button("A−") { fontSize = max(14, fontSize - 2) }
                        .disabled(fontSize <= 14)
                        .accessibilityLabel("Decrease lyrics text size")
                    Button("A+") { fontSize = min(30, fontSize + 2) }
                        .disabled(fontSize >= 30)
                        .accessibilityLabel("Increase lyrics text size")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.cyan)
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if hasLyrics {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(stanzas.enumerated()), id: \.offset) { _, stanza in
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(stanza.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, rawLine in
                                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !line.isEmpty {
                                        if line.hasPrefix("[") && line.hasSuffix("]") {
                                            Text(line.uppercased())
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .tracking(1.2)
                                                .foregroundStyle(.cyan)
                                        } else {
                                            Text(rawLine)
                                                .font(.system(size: CGFloat(fontSize), weight: .semibold, design: .rounded))
                                                .lineSpacing(8)
                                                .foregroundStyle(.white.opacity(0.92))
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.09),
                            .init(color: .white, location: 0.91),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            } else {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("No lyrics in this file")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
