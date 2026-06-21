import AppKit
import AutoLockCore

/// Shows a one-time guidance alert when Bluetooth permission is missing.
/// macOS does not allow apps to grant their own TCC permissions, so the best
/// we can do is detect the unauthorized state and route the user straight to
/// the relevant Settings pane.
@MainActor
enum PermissionPrompt {
    static func presentIfNeeded(state: BluetoothPowerState) {
        switch state {
        case .unauthorized:
            showAlert(
                title: "Bluetooth 권한이 필요합니다",
                message: """
                AutoLock은 주변 기기와의 거리를 측정하기 위해 Bluetooth가 필요합니다.

                시스템 설정 → 개인정보 보호 및 보안 → Bluetooth 에서 AutoLock을 활성화해주세요.

                권한을 켠 후 메뉴바 토글로 다시 시작할 수 있습니다.
                """,
                primaryButton: "설정 열기",
                primaryURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
            )
        case .poweredOff:
            showAlert(
                title: "Bluetooth가 꺼져있습니다",
                message: "제어센터 또는 시스템 설정에서 Bluetooth를 켠 뒤 다시 시도해주세요.",
                primaryButton: "Bluetooth 설정 열기",
                primaryURL: "x-apple.systempreferences:com.apple.BluetoothSettings"
            )
        case .unsupported:
            showAlert(
                title: "이 Mac에서 Bluetooth Low Energy를 지원하지 않습니다",
                message: "AutoLock을 사용할 수 없습니다.",
                primaryButton: "확인",
                primaryURL: nil
            )
        default:
            break
        }
    }

    private static func showAlert(title: String,
                                  message: String,
                                  primaryButton: String,
                                  primaryURL: String?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: primaryButton)
        alert.addButton(withTitle: "나중에")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let urlString = primaryURL,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
