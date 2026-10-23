import Foundation
import AVFoundation
import AudioToolbox
import UserNotifications

/// The alarm sound the user picked. Applies to reminders, the vibration alert screen and the system alarm.
enum AlarmSound: String, CaseIterable, Identifiable {
    case standard
    case vibration
    case loud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "الصوت الافتراضي"
        case .vibration: return "صوت الاهتزاز"
        case .loud: return "صوت المنبّه العالي"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "نغمة الإشعارات العادية"
        case .vibration: return "منبّه مع اهتزاز"
        case .loud: return "صوت قوي ما تفوّته"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "bell"
        case .vibration: return "iphone.radiowaves.left.and.right"
        case .loud: return "speaker.wave.3.fill"
        }
    }

    /// File name inside the app bundle (nil = system default).
    var fileName: String? {
        switch self {
        case .standard: return nil
        case .vibration: return "alarm_vibration.caf"
        case .loud: return "alarm_loud.caf"
        }
    }

    var notificationSound: UNNotificationSound {
        if let f = fileName {
            return UNNotificationSound(named: UNNotificationSoundName(f))
        }
        return .default
    }

    static var current: AlarmSound {
        AlarmSound(rawValue: UserDefaults.standard.string(forKey: "basma.sound") ?? "") ?? .standard
    }
}

/// Plays the chosen sound (preview in settings, looping while the alert screen is open).
final class SoundPlayer: ObservableObject {
    static let shared = SoundPlayer()

    @Published var previewing: AlarmSound?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(_ sound: AlarmSound, loop: Bool) {
        stop()

        guard let file = sound.fileName else {
            if !loop { AudioServicesPlaySystemSound(1007) }
            return
        }
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)

        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = loop ? -1 : 0
        player?.prepareToPlay()
        player?.play()

        if !loop {
            previewing = sound
            let length = player?.duration ?? 7
            timer = Timer.scheduledTimer(withTimeInterval: length + 0.2, repeats: false) { [weak self] _ in
                self?.stop()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        if previewing != nil { previewing = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
