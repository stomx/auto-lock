import Foundation
import AppKit
import AutoLockKit
import AutoLockCore
import AutoLockSystemAdapters

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
        case "logging":
            runLogging()
        case "lock":
            runLock(rest)
        case "update":
            runUpdate(rest)
        case "self-update":
            runSelfUpdate(rest)
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
          logging        구조화 로그 기록·영구 저장 경로 자체 점검           [비파괴]
          lock [--yes]   화면을 즉시 잠금 (--yes 필수)                     [⚠️ 파괴적]
          update [옵션]  업데이트 파이프라인 E2E 점검 (조회→비교→다운로드→검증)  [비파괴]
                         --current <버전>  현재 버전을 가장해 "가능" 경로 강제 (예: 0.0.1)
                         --download        DMG 다운로드 + SHA256 검증까지 수행
                         --open            검증 후 DMG 열기(mount) 까지 (GUI)
          self-update [옵션]  자가교체 파이프라인 점검 (ZIP 조회→검증→압축해제→교체스크립트)
                         --current <버전>  현재 버전 가장
                         --feed <url>      릴리스 피드 출처 변경
                         --dry-run         교체 스크립트 생성까지만(실제 교체 안 함)  [비파괴, 기본]
                         --apply           실제 번들 교체 + 재시작                   [⚠️ 파괴적]
          help           이 도움말 출력

        release 빌드 실행 예시:
          .build/release/AutoLock diagnose scan 15
          .build/release/AutoLock diagnose wake
          .build/release/AutoLock diagnose overlay 5
          .build/release/AutoLock diagnose lock-status
          .build/release/AutoLock diagnose logging
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
            print("❌ 실패 — 통합 로그를 확인하세요: log show --last 5m --predicate 'subsystem == \"com.local.autolock\"' --info")
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
        switch ScreenLocker.screenLockState() {
        case .locked:
            print("🔒 현재 화면이 잠겨 있습니다. (isScreenLocked = true)")
        case .unlocked:
            print("🔓 현재 화면이 잠겨 있지 않습니다. (isScreenLocked = false)")
        case .unknown:
            print("⚠️ macOS 세션에서 현재 화면 잠금 상태를 확인할 수 없습니다.")
            exit(1)
        }
        exit(0)
    }

    // MARK: - logging (비파괴)

    private static func runLogging() {
        let event = AppLog.record(
            .system,
            code: "diagnostic_log_probe",
            outcome: .success,
            message: "구조화 진단 로그 자체 점검"
        )
        let database = AppLog.logDatabaseURL
        guard AppLog.isPersistentStoreAvailable,
              AppLog.containsPersistedEvent(id: event.id) else {
            print("❌ 통합 로그는 호출했지만 SQLite 영구 저장을 확인하지 못했습니다.")
            print("   DB: \(database.path)")
            if let failure = AppLog.persistentStoreFailure {
                print("   원인: \(failure)")
            }
            exit(1)
        }
        print("✅ 구조화 로그와 SQLite 영구 저장이 정상입니다.")
        print("   세션: \(event.sessionID)")
        print("   DB: \(database.path)")
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
            print("❌ 화면 잠금 실패 — 통합 로그를 확인하세요: log show --last 5m --predicate 'subsystem == \"com.local.autolock\"' --info")
            exit(1)
        }
    }

    // MARK: - update (비파괴: --download 시 임시폴더로만 받음)

    /// 업데이트 파이프라인을 실제 GitHub/네트워크/DMG에 대해 끝까지 점검한다.
    /// 제품 코드의 GitHubUpdateClient / DownloadClient / UpdateController를 그대로
    /// 사용하므로 진짜 E2E다. 기본은 조회+버전비교까지(비파괴), --download 면 DMG
    /// 다운로드+SHA256 검증, --open 이면 mount 까지.
    private static func runUpdate(_ args: [String]) {
        let doDownload = args.contains("--download") || args.contains("--open")
        let doOpen = args.contains("--open")
        // --current / --feed 파싱은 self-update와 공유하는 순수 로직이라
        // AutoLockCore.DiagnoseArgs로 추출돼 단위 테스트된다.
        let defaultCurrent = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let common: DiagnoseArgs.CommonOptions
        switch DiagnoseArgs.parseCommon(args, defaultCurrent: defaultCurrent) {
        case .ok(let opts): common = opts
        case .failure(let message):
            print(message)
            exit(2)
        }
        let current = common.currentVersion
        let feedURL = common.feedURL

        print("🔎 업데이트 점검 — 현재 버전 가정: v\(common.currentRaw)")
        print("   피드: \(feedURL?.absoluteString ?? "github.com/stomx/auto-lock (releases/latest)")\n")

        // --open 이 아니면 실제 mount 부작용을 피하려고 열기를 가로채는 더미 opener.
        let opener: DMGOpening = doOpen ? SystemDMGOpener() : NoOpDMGOpener()
        let checker = feedURL.map { GitHubUpdateClient(feedURL: $0) } ?? GitHubUpdateClient()
        let controller = UpdateController(
            currentVersion: current,
            checker: checker,
            downloader: DownloadClient(),
            opener: opener
        )

        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            // 1) 조회 + 비교
            await controller.check()
            switch controller.state {
            case .upToDate:
                print("✅ 최신 버전입니다 (업데이트 없음).")
                done.signal()
            case .failed(let reason):
                print("❌ 확인 실패: \(reason)")
                exitCode = 1
                done.signal()
            case .available(let release):
                print("⬆️  새 버전 발견: \(release.tag)")
                print("   DMG: \(release.dmgFileName)")
                print("   체크섬: \(release.checksumsURL?.absoluteString ?? "(없음)")")
                guard doDownload else {
                    print("\n(다운로드/검증까지 보려면 --download, 열기까지는 --open)")
                    done.signal()
                    return
                }
                // 2) 다운로드 + SHA256 검증 (+ --open 시 mount)
                print("\n⬇️  다운로드 + SHA256 검증\(doOpen ? " + DMG 열기" : "") 진행…")
                await controller.downloadAndOpen()
                switch controller.state {
                case .opened(let r):
                    print("✅ 다운로드·검증 통과. \(r.dmgFileName)\(doOpen ? " 를 열었습니다(mount)." : " 준비 완료.")")
                case .failed(let reason):
                    print("❌ 다운로드/검증 실패: \(reason)")
                    exitCode = 1
                default:
                    print("⚠️ 예상치 못한 상태: \(controller.state)")
                    exitCode = 1
                }
                done.signal()
            default:
                print("⚠️ 예상치 못한 상태: \(controller.state)")
                exitCode = 1
                done.signal()
            }
        }
        // 메인 RunLoop을 돌려 async 작업이 진행되게 한다(CLI는 메인 스레드 동기 흐름).
        while done.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        exit(exitCode)
    }

    // MARK: - self-update (기본 비파괴 dry-run: 교체 스크립트 생성까지만)

    /// 자가교체 파이프라인을 제품 코드(GitHubUpdateClient / SelfUpdateInstaller)로
    /// 점검한다. 기본은 --dry-run: ZIP 조회→검증→압축해제→교체 스크립트 생성까지만
    /// 하고 실제 번들 교체/재시작은 하지 않는다(임시 디렉터리를 타깃으로 둠).
    /// --apply 면 실제 실행 중인 번들을 교체하고 재시작한다(파괴적).
    private static func runSelfUpdate(_ args: [String]) {
        let apply = args.contains("--apply")
        let dryRun = !apply   // 기본 dry-run

        // runUpdate와 공유하는 --current / --feed 파싱(AutoLockCore.DiagnoseArgs).
        let defaultCurrent = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let common: DiagnoseArgs.CommonOptions
        switch DiagnoseArgs.parseCommon(args, defaultCurrent: defaultCurrent) {
        case .ok(let opts): common = opts
        case .failure(let message):
            print(message)
            exit(2)
        }
        let current = common.currentVersion
        let feedURL = common.feedURL

        // dry-run은 실제 앱 번들 대신 임시 타깃을 둬서 staging이 temp로 가게 한다.
        let targetBundle: URL = dryRun
            ? FileManager.default.temporaryDirectory.appendingPathComponent("AutoLock-selfupdate-dryrun.app")
            : Bundle.main.bundleURL
        if dryRun {
            // canSelfUpdate의 쓰기가능 검사를 통과하도록 임시 타깃을 만들어 둔다.
            try? FileManager.default.createDirectory(at: targetBundle, withIntermediateDirectories: true)
        }

        print("🔎 자가교체 점검 (\(apply ? "⚠️ APPLY — 실제 교체" : "dry-run")) — 현재 버전 가정: v\(common.currentRaw)")
        print("   피드: \(feedURL?.absoluteString ?? "github.com/stomx/auto-lock (releases/latest)")")
        print("   타깃 번들: \(targetBundle.path)\n")

        let installer = SelfUpdateInstaller(bundleURL: targetBundle, dryRun: dryRun)
        let checker = feedURL.map { GitHubUpdateClient(feedURL: $0) } ?? GitHubUpdateClient()
        let controller = UpdateController(
            currentVersion: current,
            checker: checker,
            downloader: DownloadClient(),
            opener: SystemDMGOpener(),
            selfUpdater: installer
        )

        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await controller.check()
            switch controller.state {
            case .upToDate:
                print("✅ 최신 버전입니다 (업데이트 없음).")
                done.signal()
            case .failed(let reason):
                print("❌ 확인 실패: \(reason)")
                exitCode = 1
                done.signal()
            case .available(let release):
                print("⬆️  새 버전 발견: \(release.tag)")
                print("   ZIP: \(release.zipFileName ?? "(없음 — 자가교체 불가)")")
                print("   체크섬: \(release.checksumsURL?.absoluteString ?? "(없음)")")
                guard installer.canSelfUpdate(release) else {
                    print("\n⚠️ 이 위치에서는 자가교체 불가(ZIP 없음 / 쓰기 불가 / translocation).")
                    print("   → 실제 앱에서는 DMG 수동 설치로 폴백합니다.")
                    done.signal()
                    return
                }
                print("\n⬇️  ZIP 다운로드 + SHA256 검증 + 압축해제 + 교체 스크립트 생성\(apply ? " + 실제 교체·재시작" : "")…")
                await controller.downloadAndInstall()
                switch controller.state {
                case .installing:
                    // dry-run: installer가 스크립트 생성까지만 하고 종료하지 않아
                    // 상태가 .installing에 머문다. apply였다면 여기 도달 전에
                    // NSApp.terminate로 종료됐을 것.
                    if dryRun {
                        print("✅ dry-run 통과 — 다운로드·검증·압축해제·교체 스크립트 생성 완료.")
                        print("   (실제 교체/재시작은 생략. staging·스크립트는 타깃 옆 임시폴더에 남음)")
                    } else {
                        print("✅ 교체 진행 중 (앱이 곧 종료·재시작됩니다).")
                    }
                case .failed(let reason):
                    print("❌ 자가교체 실패: \(reason)")
                    exitCode = 1
                default:
                    print("⚠️ 예상치 못한 상태: \(controller.state)")
                    exitCode = 1
                }
                done.signal()
            default:
                print("⚠️ 예상치 못한 상태: \(controller.state)")
                exitCode = 1
                done.signal()
            }
        }
        while done.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        exit(exitCode)
    }

    /// runUpdate의 async 클로저에서 설정하는 종료 코드. 메인 스레드 전용.
    private static var exitCode: Int32 = 0

    // MARK: - 헬퍼

    private static func stateDescription(_ state: BluetoothPowerState) -> String {
        switch state {
        case .unknown: return "unknown(미확정)"
        case .resetting: return "resetting(재설정중)"
        case .unsupported: return "unsupported(미지원)"
        case .unauthorized: return "unauthorized(권한없음)"
        case .poweredOff: return "poweredOff(꺼짐)"
        case .poweredOn: return "poweredOn(켜짐)"
        }
    }
}

/// `diagnose update`에서 실제 DMG mount 부작용 없이 다운로드·검증까지만 확인할 때
/// 쓰는 더미 opener. open()은 경로만 출력하고 아무 것도 mount하지 않는다.
@MainActor
private struct NoOpDMGOpener: DMGOpening {
    func open(_ fileURL: URL) throws {
        print("   (열기 생략) 검증된 파일: \(fileURL.path)")
    }
}
