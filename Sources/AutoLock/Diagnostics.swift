import Foundation
import AppKit
import CoreBluetooth
import AutoLockKit
import AutoLockCore

/// 진단 서브커맨드 모음. 실기기에서 시스템 API(BLE 스캔, 디스플레이 깨우기,
/// 카운트다운 오버레이, 화면 잠금 상태/잠금)를 격리 실행해 "기능이 실제로
/// 동작하는지"를 사람이 눈/콘솔로 확인하기 위한 도구다. 제품 로직과 무관하며
/// 부수효과만 발생시킨다.
///
/// MainActor 격리: BLEScanner/CountdownOverlay/NSApplication 등 메인 액터 전용
/// 객체를 직접 다루고, 진입점(main.swift 최상위)도 메인에서 호출하므로 전체를
/// main actor로 둔다. 덕분에 산재하던 `MainActor.assumeIsolated`도 제거된다.
@MainActor
enum Diagnostics {
    /// 진단 진입점. main.swift에서 "diagnose" 이후 인자를 받아 호출된다.
    /// 각 서브커맨드는 내부에서 exit()를 호출하므로 이 함수는 정상적으로 반환하지 않는다.
    static func run(_ args: [String]) {
        let sub = args.first ?? "help"
        let rest = Array(args.dropFirst())

        switch sub {
        case "scan":
            runScan(rest)
        case "wake":
            runWake()
        case "overlay":
            runOverlay(rest)
        case "lock-status":
            runLockStatus()
        case "lock":
            runLock(rest)
        case "help", "-h", "--help":
            printUsage()
            exit(0)
        default:
            print("❌ 알 수 없는 서브커맨드: \(sub)\n")
            printUsage()
            exit(2)
        }
    }

    // MARK: - 사용법

    private static func printUsage() {
        print("""
        AutoLock 진단 도구 — 실기기에서 시스템 기능을 격리 실행해 확인합니다.

        사용법:
          AutoLock diagnose <서브커맨드> [옵션]

        서브커맨드:
          scan [초]      BLE 스캔으로 주변 기기를 N초간 탐색 (기본 10초)  [비파괴]
          wake           디스플레이 깨우기 호출                            [비파괴]
          overlay [초]   화면 중앙 카운트다운 오버레이 표시 (기본 5초)     [비파괴]
          lock-status    현재 화면 잠금 상태 출력                          [비파괴]
          lock [--yes]   화면을 즉시 잠금 (--yes 필수)                     [⚠️ 파괴적]
          help           이 도움말 출력

        release 빌드 실행 예시:
          .build/release/AutoLock diagnose scan 15
          .build/release/AutoLock diagnose wake
          .build/release/AutoLock diagnose overlay 5
          .build/release/AutoLock diagnose lock-status
          .build/release/AutoLock diagnose lock --yes
        """)
    }

    // MARK: - scan (비파괴)

    private static func runScan(_ args: [String]) {
        let seconds = args.first.flatMap { TimeInterval($0) } ?? 10
        print("🔍 BLE 스캔 시작 — \(Int(seconds))초간 주변 기기를 탐색합니다.")
        print("   (CoreBluetooth 콜백 수신을 위해 메인 RunLoop을 구동합니다.)\n")

        let scanner = BLEScanner()
        scanner.startScanning()

        // CoreBluetooth는 RunLoop이 돌아야 콜백을 받는다. 1초 단위로 끊어서
        // 돌리며 매 초마다 현재 상태/발견 기기 스냅샷을 출력해 RSSI 변화를
        // 실시간으로 볼 수 있게 한다.
        let deadline = Date().addingTimeInterval(seconds)
        var tick = 0
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            tick += 1
            printScanSnapshot(scanner: scanner, elapsed: tick, total: Int(seconds))
        }

        // Snapshot BEFORE stopping: stopScanning() now clears the discovered
        // device map (so a re-enabled scanner can't act on stale entries), which
        // would otherwise zero out this diagnostic's results.
        let devices = Array(scanner.devices.values)
        scanner.stopScanning()

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("스캔 종료. 블루투스 상태: \(stateDescription(scanner.bluetoothState))")
        print("발견 기기 수: \(devices.count)개")

        if scanner.bluetoothState == .unauthorized {
            print("❌ 블루투스 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > Bluetooth 에서 AutoLock을 허용하세요.")
            exit(1)
        }
        if scanner.bluetoothState == .poweredOff {
            print("❌ 블루투스가 꺼져 있습니다. 켜고 다시 시도하세요.")
            exit(1)
        }

        if devices.isEmpty {
            print("❌ 발견된 기기가 없습니다.")
            exit(1)
        } else {
            print("✅ 발견 성공.")
            exit(0)
        }
    }

    private static func printScanSnapshot(scanner: BLEScanner, elapsed: Int, total: Int) {
        let devices = scanner.devices.values.sorted { $0.smoothedRssi > $1.smoothedRssi }
        print("[\(elapsed)/\(total)초] 상태=\(stateDescription(scanner.bluetoothState)) 스캔중=\(scanner.isScanning) 기기=\(devices.count)개")
        // lastSeen이 monotonic 인스턴트이므로 age도 같은 클럭으로 계산해야 한다.
        let now = MonotonicClock.now()
        for device in devices {
            let age = now.timeIntervalSince(device.lastSeen)
            let rssi = String(format: "%.1f", device.smoothedRssi)
            let ageStr = String(format: "%.1f", age)
            print("   • \(device.name)  | RSSI \(rssi) dBm | \(ageStr)초 전 | \(device.id.uuidString)")
        }
    }

    // MARK: - wake (비파괴)

    private static func runWake() {
        print("💡 디스플레이 깨우기를 호출합니다 (DisplayWaker.wake)...")
        let ok = DisplayWaker.wake()
        if ok {
            print("✅ 성공 — IOPMAssertionDeclareUserActivity 반환 성공.")
            exit(0)
        } else {
            print("❌ 실패 — 콘솔 로그(NSLog)를 확인하세요.")
            exit(1)
        }
    }

    // MARK: - overlay (비파괴)

    private static func runOverlay(_ args: [String]) {
        let seconds = args.first.flatMap { TimeInterval($0) } ?? 5
        print("🖥  화면 중앙에 \(Int(seconds))초 카운트다운 오버레이를 표시합니다.")
        print("   화면 한가운데에 숫자가 나타나는지 눈으로 확인하세요.\n")

        // NSPanel을 표시하려면 NSApplication이 구동되어야 한다. accessory 모드로
        // 띄워 Dock 아이콘 없이 패널만 보이게 한다.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // CountdownOverlay measures its deadline against MonotonicClock, so the
        // overlay deadline must use the same clock. The RunLoop wait, however,
        // is a real-time wait and stays on the wall clock.
        let overlayDeadline = MonotonicClock.now().addingTimeInterval(seconds)
        // Diagnostics 전체가 @MainActor라 CountdownOverlay 싱글톤을 직접 호출한다.
        CountdownOverlay.shared.show(until: overlayDeadline)

        RunLoop.main.run(until: Date().addingTimeInterval(seconds))

        CountdownOverlay.shared.hide()
        print("✅ 오버레이 종료.")
        exit(0)
    }

    // MARK: - lock-status (비파괴)

    private static func runLockStatus() {
        let locked = ScreenLocker.isScreenLocked()
        if locked {
            print("🔒 현재 화면이 잠겨 있습니다. (isScreenLocked = true)")
        } else {
            print("🔓 현재 화면이 잠겨 있지 않습니다. (isScreenLocked = false)")
        }
        exit(0)
    }

    // MARK: - lock (파괴적)

    private static func runLock(_ args: [String]) {
        guard args.contains("--yes") else {
            print("⚠️ 이 명령은 즉시 화면을 잠급니다. 확인하려면 `diagnose lock --yes` 로 실행하세요.")
            exit(2)
        }

        print("🔒 3초 후 화면을 잠급니다...")
        for remaining in stride(from: 3, through: 1, by: -1) {
            print("   \(remaining)...")
            Thread.sleep(forTimeInterval: 1)
        }

        let ok = ScreenLocker.lock()
        if ok {
            print("✅ 화면 잠금 호출 성공 (SACLockScreenImmediate).")
            exit(0)
        } else {
            print("❌ 화면 잠금 실패 — 콘솔 로그(NSLog)를 확인하세요.")
            exit(1)
        }
    }

    // MARK: - 헬퍼

    private static func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown(미확정)"
        case .resetting: return "resetting(재설정중)"
        case .unsupported: return "unsupported(미지원)"
        case .unauthorized: return "unauthorized(권한없음)"
        case .poweredOff: return "poweredOff(꺼짐)"
        case .poweredOn: return "poweredOn(켜짐)"
        @unknown default: return "알수없음(\(state.rawValue))"
        }
    }
}
