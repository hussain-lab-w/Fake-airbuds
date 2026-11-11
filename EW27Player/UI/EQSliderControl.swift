import SwiftUI

struct EQSliderControl: View {
    @ObservedObject var player: AudioPlayer
    let index: Int?
    let title: String
    @State private var localValue: Float = 0
    @State private var editing = false

    private var currentValue: Float {
        if let index { return player.eqGains.indices.contains(index) ? player.eqGains[index] : 0 }
        return player.preamp
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .onTapGesture(count: 2) { localValue = 0; apply(0); player.commitEQSettings() }
                Spacer()
                Text(String(format: "%+.1f dB", localValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan.opacity(0.82))
            }
            Slider(value: Binding(get: { localValue }, set: { value in localValue = value; apply(value) }), in: -12...12, onEditingChanged: { value in
                editing = value
                if !value { player.commitEQSettings() }
            })
            .tint(.cyan)
        }
        .onAppear { localValue = currentValue }
        .onChange(of: currentValue) { _, value in if !editing { localValue = value } }
    }

    private func apply(_ value: Float) {
        if let index { player.setBandGain(index: index, gain: value) }
        else { player.setPreamp(value) }
    }
}
