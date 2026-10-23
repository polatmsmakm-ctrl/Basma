import SwiftUI
import AudioToolbox

extension Notification.Name {
    /// Posted from notification actions so an open alert screen closes.
    static let basmaStopBuzz = Notification.Name("basmaStopBuzz")
}

/// Continuous vibration (while the app is open) for up to 40 seconds, until stopped.
final class AlertController: ObservableObject {
    static let shared = AlertController()

    @Published var activeKind: ReminderKind?
    @Published var remaining: Int = 0

    private var timer: Timer?
    private var stoppedAt: [String: Date] = [:]
    private let duration = 40

    init() {
        NotificationCenter.default.addObserver(forName: .basmaStopBuzz, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }
    }

    var enabled: Bool {
        (UserDefaults.standard.object(forKey: "basma.buzz") as? Bool) ?? true
    }

    func start(kind: ReminderKind, force: Bool = false) {
        guard force || enabled else { return }
        guard activeKind == nil else { return }
        if !force, let t = stoppedAt[kind.rawValue], Date().timeIntervalSince(t) < 90 { return }

        activeKind = kind
        remaining = duration
        UIApplication.shared.isIdleTimerDisabled = true
        vibrate()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remaining -= 1
            if self.remaining <= 0 {
                self.stop()
            } else {
                self.vibrate()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let k = activeKind {
            stoppedAt[k.rawValue] = Date()
            DoneStorage.stopBuzz(kindRaw: k.rawValue)
        }
        activeKind = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}

// MARK: - Full screen alert

struct AlertView: View {
    let kind: ReminderKind
    @EnvironmentObject var store: ReminderStore
    @ObservedObject private var alert = AlertController.shared
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppBackground()
            kind.tint.opacity(0.10).ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(kind.tint.opacity(0.16))
                        .frame(width: 220, height: 220)
                        .scaleEffect(pulse ? 1.2 : 0.9)
                    Circle()
                        .fill(kind.tint.opacity(0.26))
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulse ? 1.08 : 0.95)
                    Image(systemName: "touchid")
                        .font(.system(size: 84))
                        .foregroundColor(.white)
                }
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulse)

                Text("حان وقت")
                    .font(.title3)
                    .foregroundColor(Theme.muted)
                Text(kind.title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("الجوال يهتز • \(arNum(alert.remaining)) ث")
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)

                Spacer()

                Button {
                    haptic()
                    if !store.isDoneToday(kind) { store.toggleDone(kind) }
                    alert.stop()
                } label: {
                    Text("تمت البصمة ✓")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(kind.tint))
                        .foregroundColor(Color.black.opacity(0.85))
                }

                Button {
                    alert.stop()
                } label: {
                    Text("إيقاف الاهتزاز")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                        )
                        .foregroundColor(.white)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .onAppear { pulse = true }
    }
}
