import SwiftUI
import AppKit
import AutoLockCore
import AutoLockKit
import AutoLockSystemAdapters

// Design tokens (Palette/AppFont) and reusable views (Surface, Caption,
// ParameterDial, DotPulse, GhostButtonStyle) now live in DesignSystem.swift.
// DevicePickerView and PasswordSheetView are in their own files.

// MARK: - Menu

struct MenuView: View {
    @ObservedObject var controller: ProximityController
    @ObservedObject private var scanner: BLEScanner
    @ObservedObject private var settings: AutoLockKit.Settings
    @ObservedObject private var updateController: UpdateController
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var helpExpanded: Bool = false
    @State private var hasPassword: Bool = KeychainStore.hasPassword()
    @State private var hasAccessibility: Bool = UnlockTrigger.hasAccessibility()
    @State private var keychainError: String?
    /// Re-checks the AX trust on a cadence so the badge flips green the moment
    /// the user grants Accessibility in System Settings. `AXIsProcessTrustedWithOptions`
    /// is cheap (microseconds) so polling while the menu is open is fine. We do
    /// NOT poll the Keychain here — `hasPassword` changes only via this app's own
    /// password sheet, which refreshes the flag directly in its completion handler.
    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    init(controller: ProximityController, scanner: BLEScanner, updateController: UpdateController) {
        self.controller = controller
        self.scanner = scanner
        self.settings = controller.settings
        self.updateController = updateController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            heroCard
            diagnosticsCard
            devicesCard
            optionsCard
            helpCard
            footer
            updateRow
            versionLabel
        }
        .padding(14)
        .frame(width: 360)
        .background(Palette.bg)
        .onAppear {
            AppLog.record(
                .ui,
                code: "main_menu_opened",
                outcome: .observed,
                message: "메인 상태 화면 열림"
            )
            controller.evaluate()
        }
        .onDisappear {
            AppLog.record(
                .ui,
                code: "main_menu_closed",
                outcome: .observed,
                message: "메인 상태 화면 닫힘"
            )
        }
        .onReceive(permissionTimer) { _ in
            let ax = UnlockTrigger.hasAccessibility()
            if ax != hasAccessibility { hasAccessibility = ax }
        }
        .alert(
            "Keychain 오류",
            isPresented: Binding(
                get: { keychainError != nil },
                set: { if !$0 { keychainError = nil } }
            )
        ) {
            Button("확인", role: .cancel) { keychainError = nil }
        } message: {
            Text(keychainError ?? "저장된 암호를 처리하지 못했습니다.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(stateAccent.opacity(0.14))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(stateAccent.opacity(0.5), lineWidth: 0.5)
                Image(systemName: controller.menuBarIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(stateAccent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("AutoLock")
                    .font(AppFont.pretendard(17, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Text(bluetoothStateText)
                    .font(AppFont.pretendard(13, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()

            Toggle("", isOn: $settings.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Palette.lime)
        }
    }

    // MARK: Hero – signal readout (no meter, just numbers)

    private var heroCard: some View {
        Surface(elevated: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Caption(text: "상태")
                        HStack(spacing: 8) {
                            Circle()
                                .fill(stateAccent)
                                .frame(width: 7, height: 7)
                                .shadow(color: stateAccent.opacity(0.7), radius: 4)
                            Text(stateLabel)
                                .font(AppFont.pretendard(16, weight: .semibold))
                                .foregroundStyle(Palette.label)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(rssiBigText)
                                .font(AppFont.pretendard(34, weight: .bold))
                                .foregroundStyle(stateAccent)
                                .monospacedDigit()
                            Text("dBm")
                                .font(AppFont.pretendard(13, weight: .medium))
                                .foregroundStyle(Palette.muted)
                                .padding(.bottom, 4)
                        }
                        Text(metaText)
                            .font(AppFont.pretendard(13, weight: .medium))
                            .foregroundStyle(Palette.dim)
                    }
                }

                if let message = statusMessage(for: controller.status) {
                    Text(message)
                        .font(AppFont.pretendard(13, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Operational diagnostics

    private var diagnosticsCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Caption(text: "동작 진단")
                    Spacer()
                    Button("진단 DB") {
                        let database = AppLog.logDatabaseURL
                        if FileManager.default.fileExists(atPath: database.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([database])
                        } else {
                            NSWorkspace.shared.open(database.deletingLastPathComponent())
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .help(AppLog.logDatabaseURL.path)
                }

                HStack(spacing: 8) {
                    diagnosticBadge(
                        icon: settings.trackedDevices.isEmpty ? "link.badge.plus" : "link",
                        label: settings.trackedDevices.isEmpty ? "미연동" : "연동됨",
                        color: settings.trackedDevices.isEmpty ? Palette.amber : Palette.lime
                    )
                    diagnosticBadge(
                        icon: screenStateIcon,
                        label: screenStateLabel,
                        color: screenStateColor
                    )
                    diagnosticBadge(
                        icon: settings.enabled ? "wave.3.right" : "pause.fill",
                        label: settings.enabled ? "감시 중" : "감시 꺼짐",
                        color: settings.enabled ? Palette.lime : Palette.dim
                    )
                }

                if let event = controller.recentEvents.first {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: eventIcon(event))
                            .foregroundStyle(eventColor(event))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.message)
                                .font(AppFont.pretendard(13, weight: .medium))
                                .foregroundStyle(Palette.label)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(eventTime(event.timestamp)) · \(event.code)")
                                .font(AppFont.pretendard(11))
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.surfaceHi)
                    )
                } else {
                    Text("아직 기록된 동작이 없습니다")
                        .font(AppFont.pretendard(13))
                        .foregroundStyle(Palette.dim)
                }

                if let failure = AppLog.persistentStoreFailure {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                        Text("진단 DB 저장 오류: \(failure)")
                            .lineLimit(3)
                    }
                    .font(AppFont.pretendard(11, weight: .medium))
                    .foregroundStyle(Palette.crimson)
                }
            }
        }
    }

    private func diagnosticBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(AppFont.pretendard(11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(color.opacity(0.11))
        )
    }

    private var screenStateIcon: String {
        switch controller.screenLockState {
        case .unknown: return "questionmark.circle"
        case .unlocked: return "lock.open.fill"
        case .locked: return "lock.fill"
        }
    }

    private var screenStateLabel: String {
        switch controller.screenLockState {
        case .unknown: return "화면 확인 중"
        case .unlocked: return "화면 열림"
        case .locked: return "화면 잠김"
        }
    }

    private var screenStateColor: Color {
        switch controller.screenLockState {
        case .unknown: return Palette.dim
        case .unlocked: return Palette.lime
        case .locked: return Palette.amber
        }
    }

    private func eventIcon(_ event: DiagnosticEvent) -> String {
        switch event.outcome {
        case .failure: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .skipped: return "forward.fill"
        case .observed: return "info.circle.fill"
        }
    }

    private func eventColor(_ event: DiagnosticEvent) -> Color {
        switch event.level {
        case .error: return Palette.crimson
        case .warning: return Palette.amber
        case .info:
            return event.outcome == .success ? Palette.lime : Palette.muted
        }
    }

    private func eventTime(_ date: Date) -> String {
        Self.eventTimeFormatter.string(from: date)
    }

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: Devices

    private var devicesCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Caption(text: "등록된 디바이스")
                    Spacer()
                    Button(settings.trackedDevices.isEmpty ? "추가" : "교체") {
                        PickerWindow.show(scanner: scanner, settings: settings)
                    }
                    .buttonStyle(GhostButtonStyle())
                }

                if settings.trackedDevices.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(Palette.dim)
                        Text("등록된 디바이스가 없습니다")
                            .font(AppFont.pretendard(13))
                            .foregroundStyle(Palette.muted)
                    }
                } else {
                    ForEach(settings.trackedDevices) { device in
                        deviceRow(device)
                    }
                }
            }
        }
    }

    private func deviceRow(_ device: TrackedDevice) -> some View {
        let live = scanner.devices[device.id]
        return HStack(spacing: 10) {
            DotPulse(active: live != nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(AppFont.pretendard(14, weight: .medium))
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Text(device.id.uuidString.prefix(8).lowercased())
                    .font(AppFont.pretendard(13))
                    .tracking(0.5)
                    .foregroundStyle(Palette.dim)
            }
            Spacer()
            Button {
                settings.removeDevice(id: device.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.surfaceHi))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Options

    private var optionsCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Caption(text: "설정")

                optionToggle(
                    title: "로그인 시 자동 시작",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            let ok = LaunchAtLogin.setEnabled(newValue)
                            launchAtLogin = ok ? newValue : LaunchAtLogin.isEnabled
                        }
                    )
                )
                optionToggle(
                    title: "근접 시 화면 깨우기",
                    isOn: $settings.wakeOnProximity
                )
                optionToggle(
                    title: "근접 시 자동 잠금 해제",
                    isOn: Binding(
                        get: { settings.autoUnlock },
                        set: { enabled in
                            if enabled {
                                let migration = KeychainStore.migrateLegacyUnrestrictedItemIfNeeded()
                                if migration == .failed {
                                    keychainError = "이전 Keychain 암호의 보안 마이그레이션에 실패해 자동 잠금 해제를 켜지 않았습니다."
                                } else {
                                    if migration == .credentialRemoved { hasPassword = false }
                                    settings.autoUnlock = true
                                }
                            } else if KeychainStore.delete() {
                                settings.autoUnlock = false
                                hasPassword = false
                            } else {
                                keychainError = "자동 잠금 해제를 끄려면 저장된 로그인 암호를 삭제해야 합니다. Keychain 삭제에 실패해 설정을 유지했습니다."
                            }
                        }
                    )
                )

                if settings.autoUnlock {
                    autoUnlockSetupRow
                }

                Rectangle()
                    .fill(Palette.stroke)
                    .frame(height: 0.5)

                ParameterDial(
                    label: "거리 임계값",
                    valueText: "−\(settings.thresholdMagnitude) dBm",
                    binding: Binding(
                        get: { Double(settings.thresholdMagnitude) },
                        set: { settings.thresholdMagnitude = Int(($0 / 5).rounded()) * 5 }
                    ),
                    range: 40...100,
                    step: 5,
                    accent: Palette.lime
                )
                ParameterDial(
                    label: "무신호 허용 시간",
                    valueText: "\(settings.gracePeriodSeconds)초",
                    binding: Binding(
                        get: { Double(settings.gracePeriodSeconds) },
                        set: { settings.gracePeriodSeconds = Int($0.rounded()) }
                    ),
                    range: Double(LockSettingBounds.gracePeriodRange.lowerBound)...Double(LockSettingBounds.gracePeriodRange.upperBound),
                    step: Double(LockSettingBounds.gracePeriodStep),
                    accent: Palette.amber
                )
                ParameterDial(
                    label: "카운트다운 시간",
                    valueText: "\(settings.countdownSeconds)초",
                    binding: Binding(
                        get: { Double(settings.countdownSeconds) },
                        set: { settings.countdownSeconds = Int($0.rounded()) }
                    ),
                    range: Double(LockSettingBounds.countdownRange.lowerBound)...Double(LockSettingBounds.countdownRange.upperBound),
                    step: Double(LockSettingBounds.countdownStep),
                    accent: Palette.crimson
                )
            }
        }
    }

    private var autoUnlockSetupRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            setupStatusRow(
                title: "로그인 암호",
                ok: hasPassword,
                actionLabel: hasPassword ? "변경" : "설정",
                action: {
                    PasswordWindow.show {
                        hasPassword = KeychainStore.hasPassword()
                    }
                }
            )
            setupStatusRow(
                title: "접근성 권한",
                ok: hasAccessibility,
                actionLabel: hasAccessibility ? "확인" : "허용",
                action: {
                    UnlockTrigger.openAccessibilitySettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        hasAccessibility = UnlockTrigger.hasAccessibility()
                    }
                }
            )
            Text("암호는 macOS Keychain에 저장됩니다. 키 입력은 잠금 화면 보안 정책상 일부 환경에서 차단될 수 있어요.")
                .font(AppFont.pretendard(13))
                .foregroundStyle(Palette.dim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.surfaceHi)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.stroke, lineWidth: 0.5)
        )
    }

    private func setupStatusRow(title: String, ok: Bool, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Palette.lime : Palette.amber)
                .font(.system(size: 14))
            Text(title)
                .font(AppFont.pretendard(13))
                .foregroundStyle(Palette.label)
            Spacer()
            Button(actionLabel, action: action)
                .buttonStyle(GhostButtonStyle())
        }
    }

    private func optionToggle(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(AppFont.pretendard(14))
                .foregroundStyle(Palette.label)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(Palette.lime)
        }
    }

    // MARK: Help

    private var helpCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        helpExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Palette.dim)
                        Text("자동 해제는 어떻게 되나요?")
                            .font(AppFont.pretendard(13, weight: .medium))
                            .foregroundStyle(Palette.label)
                        Spacer()
                        Image(systemName: helpExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if helpExpanded {
                    Text("macOS는 앱이 직접 잠금을 해제할 수 없습니다. 가까워지면 화면을 깨워 Touch ID/암호 입력 창을 띄우고, 실제 해제는 Apple Watch Auto Unlock이나 Touch ID로 진행하세요.")
                        .font(AppFont.pretendard(13))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Lock") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("시스템 설정 열기")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(AppFont.pretendard(13, weight: .semibold))
                        .foregroundStyle(Palette.lime)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                controller.lockNow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("바로 잠금")
                        .font(AppFont.pretendard(13, weight: .bold))
                }
                .foregroundStyle(Palette.onLime)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.lime)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("종료")
                    .font(AppFont.pretendard(13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.stroke, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Update

    /// Update status row. Stays quiet when up to date / checking; surfaces a
    /// "new version" affordance when an update is available, progress while
    /// downloading, and a guidance line once the DMG is mounted.
    @ViewBuilder private var updateRow: some View {
        switch updateController.state {
        case .available(let release):
            Button {
                // 다운로드→검증→번들 교체→재실행까지 자동. 자가교체 불가 위치면
                // 컨트롤러가 .unsupported로 떨어뜨려 수동 안내를 보여준다.
                Task { await updateController.downloadAndInstall() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("새 버전 \(release.tag) — 업데이트")
                        .font(AppFont.pretendard(13, weight: .bold))
                }
                .foregroundStyle(Palette.onLime)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.lime)
                )
            }
            .buttonStyle(.plain)

        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("업데이트 다운로드 중…")
                    .font(AppFont.pretendard(13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Spacer()
            }

        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("앱을 교체하고 다시 시작합니다…")
                    .font(AppFont.pretendard(13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Spacer()
            }

        case .unsupported(let release):
            // 자가교체 불가(번들 쓰기 불가 / translocation). DMG 수동 설치로 폴백.
            VStack(alignment: .leading, spacing: 6) {
                Text("자동 교체를 할 수 없는 위치입니다")
                    .font(AppFont.pretendard(13, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Text("AutoLock을 Applications 폴더에 설치한 뒤 다시 시도하거나, 아래에서 직접 받으세요.")
                    .font(AppFont.pretendard(13))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("\(release.tag) DMG 받기") {
                    Task { await updateController.downloadAndOpen() }
                }
                .buttonStyle(GhostButtonStyle())
            }

        case .opened(let release):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(release.tag) 디스크 이미지를 열었습니다")
                    .font(AppFont.pretendard(13, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Text("AutoLock을 Applications 폴더로 드래그한 뒤 앱을 다시 실행하세요.")
                    .font(AppFont.pretendard(13))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .failed(let reason):
            HStack(spacing: 6) {
                Text("업데이트 확인 실패: \(reason)")
                    .font(AppFont.pretendard(13))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("다시 시도") { Task { await updateController.check() } }
                    .buttonStyle(GhostButtonStyle())
            }

        case .idle, .checking, .upToDate:
            EmptyView()
        }
    }

    private var versionLabel: some View {
        HStack {
            // 최신 상태일 때만 "최신 버전" 표시 — 조용한 기본값.
            if updateController.state == .upToDate {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dim)
            }
            Spacer()
            Button {
                Task { await updateController.check() }
            } label: {
                Text(Self.versionString)
                    .font(AppFont.pretendard(13))
                    .foregroundStyle(Palette.dim)
            }
            .buttonStyle(.plain)
            .help("클릭하면 업데이트를 확인합니다")
            Spacer()
        }
    }

    /// CFBundleShortVersionString + CFBundleVersion from Info.plist. Computed
    /// once at type init; the bundle metadata never changes during runtime.
    private static let versionString: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (build \(build))"
    }()

    // MARK: Helpers

    private var rssiBigText: String {
        if let r = controller.bestSeen?.rssi { return "\(Int(r))" }
        return "—"
    }

    private var metaText: String {
        if let age = controller.bestSeen?.age { return "\(Int(age))초 전" }
        return "신호 없음"
    }

    private var stateAccent: Color {
        guard settings.enabled else { return Palette.dim }
        switch controller.state {
        case .near: return Palette.lime
        case .borderline: return Palette.amber
        case .away: return Palette.crimson
        case .unknown: return Palette.dim
        }
    }

    private var stateLabel: String {
        guard settings.enabled else { return "대기" }
        switch controller.state {
        case .near: return "근접"
        case .borderline: return "잠금 대기"
        case .away: return "이탈"
        case .unknown: return "신호 대기"
        }
    }

    private var bluetoothStateText: String {
        switch scanner.bluetoothState {
        case .poweredOn: return scanner.isScanning ? "스캔 중" : "준비됨"
        case .poweredOff: return "블루투스 꺼짐"
        case .unauthorized: return "권한 없음"
        case .unsupported: return "미지원"
        case .resetting: return "재설정 중"
        case .unknown: return "초기화 중"
        }
    }

    /// Maps the controller's domain status to user-facing Korean text.
    /// Returning nil means "no status banner needed" (e.g. quietly watching).
    private func statusMessage(for status: ControllerStatus) -> String? {
        switch status {
        case .idle, .watching: return nil
        case .awaitingDevice: return "등록된 디바이스 없음"
        case .countdown(let reason, let secondsLeft):
            return "\(reasonText(reason)) — \(secondsLeft)초 후 잠금"
        case .instantLock(let reason):
            return "즉시 잠금: \(reasonText(reason))"
        case .lockRequested(let reason):
            return "잠금 요청 확인 중: \(reasonText(reason))"
        case .locked(let reason):
            return "잠금: \(reasonText(reason))"
        case .lockFailed(let reason):
            return "⚠️ 잠금 실패 (\(reasonText(reason))) — 재시도 중"
        }
    }

    private func reasonText(_ reason: LockReason) -> String {
        switch reason {
        case .signalStaleSeconds(let s): return "신호 끊김 \(s)초"
        case .signalWeak: return "신호 약함"
        case .signalCrashed: return "신호 급락"
        case .deviceUnseen: return "디바이스 미감지"
        case .userRequested: return "사용자 요청"
        }
    }
}
