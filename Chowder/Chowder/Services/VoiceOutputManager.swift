import Foundation
import AVFoundation

@Observable
final class VoiceOutputManager: NSObject, AVSpeechSynthesizerDelegate {
    var isEnabled = false
    var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var queue: [String] = []

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Toggle TTS on/off. When disabled, stops any current speech.
    func toggle() {
        isEnabled.toggle()
        if !isEnabled {
            stop()
        }
    }

    /// Speak a message. If already speaking, queues it.
    func speak(_ text: String) {
        guard isEnabled, !text.isEmpty else { return }

        // Strip markdown formatting for cleaner speech
        let cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")

        if synthesizer.isSpeaking {
            queue.append(cleaned)
        } else {
            speakNow(cleaned)
        }
    }

    /// Stop all speech and clear the queue.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        queue.removeAll()
        isSpeaking = false
    }

    private func speakNow(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Use a high-quality voice if available
        if let voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en") {
            utterance.voice = voice
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .duckOthers)
            try session.setActive(true)
        } catch {
            print("[VoiceOutput] Audio session error: \(error)")
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let next = queue.first {
            queue.removeFirst()
            speakNow(next)
        } else {
            isSpeaking = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
