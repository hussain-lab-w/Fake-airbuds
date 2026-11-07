import SwiftUI
import MediaPlayer

struct QueueView: View {
    @ObservedObject var player: AudioPlayer

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.persistentID) { index, item in
                    Button { player.jumpToQueue(index: index) } label: {
                        HStack {
                            Image(systemName: index == player.currentIndex ? "speaker.wave.2.fill" : "music.note")
                                .foregroundStyle(index == player.currentIndex ? .cyan : .secondary)
                            VStack(alignment: .leading) {
                                Text(item.title ?? "Untitled")
                                Text(item.artist ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { player.removeFromQueue(at: $0) }
                .onMove { player.moveQueue(from: $0, to: $1) }
            }
            .navigationTitle("Up Next")
            .toolbar { EditButton() }
        }
    }
}
