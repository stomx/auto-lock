import SwiftUI
import Combine
import CoreBluetooth
import AutoLockKit
import AutoLockCore

struct AutoLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // 조립 루트: BLE 스캐너와 시스템 어댑터들을 생성해 컨트롤러에 주입한다.
    private let scanner: BLEScanner
    @StateObject private var controller: ProximityController
    @StateObject private var permissionObserver: PermissionObserver
    @StateObject private var updateController: UpdateController

    init() {
        let scanner = BLEScanner()
        self.scanner = scanner
        _controller = StateObject(wrappedValue: ProximityController(
            scanner: scanner,
            settings: AutoLockKit.Settings.shared,
            screenLocker: SystemScreenLocker(),
            overlay: SystemOverlay(),
            waker: SystemDisplayWaker(),
            unlocker: SystemUnlockTrigger()
        ))
        _permissionObserver = StateObject(wrappedValue: PermissionObserver(scanner: scanner))
        _updateController = StateObject(wrappedValue: UpdateController(
            currentVersion: Self.currentVersion,
            checker: GitHubUpdateClient(),
            downloader: DownloadClient(),
            opener: SystemDMGOpener()
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller, scanner: scanner, updateController: updateController)
                .task {
                    // 앱 시작 시 1회 자동 확인 (실패해도 조용히 무시 — 메뉴에 상태만 반영).
                    await updateController.check()
                }
        } label: {
            Image(systemName: controller.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    /// Running version parsed from the bundle, for the updater's comparison.
    /// Falls back to 0.0.0 so a malformed Info.plist never blocks launch.
    private static var currentVersion: SemanticVersion {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return SemanticVersion(short) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }
}

/// PermissionPrompt 와이어링. 라이브러리(AutoLockKit)는 executable의
/// PermissionPrompt에 의존할 수 없으므로, 조립 루트인 여기서 BLEScanner의
/// publisher를 직접 구독해 권한 안내를 띄운다. (이전엔 ProximityController가
/// 담당했지만 DI 리팩터링으로 구체 타입 의존을 executable로 옮겼다.)
@MainActor
final class PermissionObserver: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    private var permissionPromptShown = false

    init(scanner: BLEScanner) {
        scanner.$stateResolved
            .combineLatest(scanner.$bluetoothState)
            .sink { [weak self] resolved, state in
                guard let self, resolved, !self.permissionPromptShown else { return }
                if state == .unauthorized || state == .poweredOff || state == .unsupported {
                    self.permissionPromptShown = true
                    PermissionPrompt.presentIfNeeded(state: state)
                }
            }
            .store(in: &cancellables)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
