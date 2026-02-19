import AVFoundation
import Foundation

@MainActor
final class TranscriptionSoundPlayer {
    static let shared = TranscriptionSoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]

    private init() {}

    func playStartSound() {
        let selected = SettingsStore.shared.transcriptionStartSound
        guard let soundName = selected.soundFileName else { return }
        self.play(soundName: soundName)
    }

    private func play(soundName: String) {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "m4a") else {
            DebugLogger.shared.error("Missing sound resource: \(soundName).m4a", source: "TranscriptionSoundPlayer")
            return
        }

        do {
            let player: AVAudioPlayer
            if let existing = self.players[soundName] {
                player = existing
            } else {
                player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                self.players[soundName] = player
            }

            player.currentTime = 0
            player.play()
        } catch {
            DebugLogger.shared.error(
                "Failed to play sound \(soundName).m4a: \(error.localizedDescription)",
                source: "TranscriptionSoundPlayer"
            )
        }
    }
}
