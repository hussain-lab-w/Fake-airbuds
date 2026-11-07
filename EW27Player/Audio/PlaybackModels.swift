import Foundation
import SwiftUI

@MainActor
final class PlaybackClock: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

@MainActor
final class SpeedState: ObservableObject {
    @Published var displayed: Float = 1
}

@MainActor
final class SpectrumModel: ObservableObject {
    @Published var bars = Array(repeating: Float.zero, count: 32)
}
