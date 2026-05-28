import SwiftUI
import AppKit
import CoreBluetooth

// MARK: - Design tokens

private enum Palette {
    /// NSColor lets us hand off appearance resolution to AppKit so SwiftUI
    /// re-renders automatically when the system flips between light and dark.
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkMatch = appearance.bestMatch(from: [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark,
            ])
            return darkMatch != nil ? dark : light
        })
    }

    static let bg = dynamic(
        light: NSColor(red: 0.962, green: 0.970, blue: 0.945, alpha: 1),
        dark: NSColor(red: 0.055, green: 0.075, blue: 0.063, alpha: 1)
    )
    static let surface = dynamic(
        light: NSColor.white,
        dark: NSColor(red: 0.082, green: 0.106, blue: 0.090, alpha: 1)
    )
    static let surfaceHi = dynamic(
        light: NSColor(red: 0.985, green: 0.990, blue: 0.975, alpha: 1),
        dark: NSColor(red: 0.110, green: 0.137, blue: 0.118, alpha: 1)
    )
    static let stroke = dynamic(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let strokeHi = dynamic(
        light: NSColor.black.withAlphaComponent(0.18),
        dark: NSColor.white.withAlphaComponent(0.14)
    )
    /// Brand accent. Light variant is darker so it stays readable on white;
    /// dark variant keeps the high-energy neon.
    static let lime = dynamic(
        light: NSColor(red: 0.32, green: 0.60, blue: 0.10, alpha: 1),
        dark: NSColor(red: 0.65, green: 1.0, blue: 0.24, alpha: 1)
    )
    static let amber = dynamic(
        light: NSColor(red: 0.78, green: 0.50, blue: 0.04, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.78, blue: 0.30, alpha: 1)
    )
    static let crimson = dynamic(
        light: NSColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.36, blue: 0.36, alpha: 1)
    )
    static let dim = dynamic(
        light: NSColor.black.withAlphaComponent(0.40),
        dark: NSColor.white.withAlphaComponent(0.42)
    )
    static let muted = dynamic(
        light: NSColor.black.withAlphaComponent(0.62),
        dark: NSColor.white.withAlphaComponent(0.62)
    )
    static let label = dynamic(
        light: NSColor.black.withAlphaComponent(0.92),
        dark: NSColor.white.withAlphaComponent(0.92)
    )
    /// Foreground for elements painted on top of `lime` (e.g. LOCK NOW).
    /// Light lime is dark-green so we paint white; dark lime is neon so we paint black.
    static let onLime = dynamic(light: NSColor.white, dark: NSColor.black)
}

private enum AppFont {
    static func pretendard(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Pretendard", size: max(size, 13)).weight(weight)
    }
}

// MARK: - Reusable surfaces

private struct Surface<Content: View>: View {
    var elevated: Bool = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(elevated ? Palette.surfaceHi : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(elevated ? Palette.strokeHi : Palette.stroke, lineWidth: 0.5)
            )
    }
}

private struct Caption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFont.pretendard(13, weight: .semibold))
            .foregroundStyle(Palette.dim)
    }
}

// MARK: - Menu

struct MenuView: View {
    @ObservedObject var controller: ProximityController
    @ObservedObject private var scanner: BLEScanner
    @ObservedObject private var settings: Settings
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var helpExpanded: Bool = false
    @State private var hasPassword: Bool = KeychainStore.hasPassword()
    @State private var hasAccessibility: Bool = UnlockTrigger.hasAccessibility()
    /// Re-checks the AX trust + Keychain state on a cadence so the badges
    /// flip green the moment the user grants permission in System Settings.
    /// `AXIsProcessTrustedWithOptions` is cheap (microseconds) so polling
    /// while the menu is open is fine.
    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    init(controller: ProximityController) {
        self.controller = controller
        self.scanner = controller.scanner
        self.settings = controller.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            heroCard
            devicesCard
            optionsCard
            helpCard
            footer
            versionLabel
        }
        .padding(14)
        .frame(width: 360)
        .background(Palette.bg)
        .onReceive(permissionTimer) { _ in
            let ax = UnlockTrigger.hasAccessibility()
            if ax != hasAccessibility { hasAccessibility = ax }
            let pw = KeychainStore.hasPassword()
            if pw != hasPassword { hasPassword = pw }
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
                    isOn: $settings.autoUnlock
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
                        set: { settings.thresholdMagnitude = Int(($0 / 10).rounded()) * 10 }
                    ),
                    range: 40...100,
                    step: 10,
                    accent: Palette.lime
                )

                ParameterDial(
                    label: "신호 끊김 허용",
                    valueText: "\(settings.gracePeriodSeconds)초",
                    binding: Binding(
                        get: { Double(settings.gracePeriodSeconds) },
                        set: { settings.gracePeriodSeconds = Int($0.rounded()) }
                    ),
                    range: 15...60,
                    step: 1,
                    accent: Palette.amber
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
                _ = ScreenLocker.lock()
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

    private var versionLabel: some View {
        HStack {
            Spacer()
            Text(Self.versionString)
                .font(AppFont.pretendard(13))
                .foregroundStyle(Palette.dim)
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
        @unknown default: return "알 수 없음"
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
        case .locked(let reason):
            return "잠금: \(reasonText(reason))"
        }
    }

    private func reasonText(_ reason: LockReason) -> String {
        switch reason {
        case .signalStaleSeconds(let s): return "신호 끊김 \(s)초"
        case .signalWeak: return "신호 약함"
        case .signalCrashed: return "신호 급락"
        case .deviceUnseen: return "디바이스 미감지"
        }
    }
}

// MARK: - ParameterDial

private struct ParameterDial: View {
    let label: String
    let valueText: String
    let binding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(AppFont.pretendard(13))
                    .foregroundStyle(Palette.label)
                Spacer()
                Text(valueText)
                    .font(AppFont.pretendard(13, weight: .semibold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }
            Slider(value: binding, in: range, step: step)
                .controlSize(.small)
                .tint(accent)
        }
    }
}

// MARK: - DotPulse

private struct DotPulse: View {
    let active: Bool
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            if active {
                Circle()
                    .stroke(Palette.lime.opacity(0.6), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.4 : 0.8)
                    .opacity(pulse ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: pulse
                    )
            }
            Circle()
                .fill(active ? Palette.lime : Palette.dim.opacity(0.4))
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear { pulse = true }
    }
}

// MARK: - Button styles

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.pretendard(13, weight: .bold))
            .foregroundStyle(Palette.lime)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Palette.lime.opacity(0.5), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Device picker

struct DevicePickerView: View {
    @ObservedObject var scanner: BLEScanner
    @ObservedObject var settings: Settings
    let onClose: () -> Void
    @State private var nameOverride: String = ""
    @State private var hideUnknown: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Caption(text: "디바이스 페어링")
                Text("신호 디바이스 선택")
                    .font(AppFont.pretendard(20, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Text("디바이스를 가까이 두고 신호가 잡히는지 확인하세요.")
                    .font(AppFont.pretendard(13))
                    .foregroundStyle(Palette.muted)
            }

            HStack {
                Toggle("이름 없는 항목 숨기기", isOn: $hideUnknown)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(AppFont.pretendard(13))
                    .tint(Palette.lime)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Palette.lime)
                        .frame(width: 6, height: 6)
                    Text("\(sortedDevices.count)개 감지됨")
                        .font(AppFont.pretendard(13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedDevices, id: \.id) { device in
                        Button {
                            let name = nameOverride.isEmpty ? device.name : nameOverride
                            settings.addDevice(TrackedDevice(id: device.id, name: name))
                            onClose()
                        } label: {
                            pickerRow(device)
                        }
                        .buttonStyle(.plain)
                        Rectangle()
                            .fill(Palette.stroke)
                            .frame(height: 0.5)
                    }
                }
            }
            .frame(height: 280)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Caption(text: "표시 이름 (선택)")
                TextField("기본 이름 사용", text: $nameOverride)
                    .textFieldStyle(.plain)
                    .font(AppFont.pretendard(13))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.stroke, lineWidth: 0.5)
                    )
            }

            HStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Text("닫기")
                        .font(AppFont.pretendard(13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Palette.stroke, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(Palette.bg)
    }

    private func pickerRow(_ device: DiscoveredDevice) -> some View {
        HStack(spacing: 12) {
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
            HStack(spacing: 4) {
                Circle()
                    .fill(barColor(for: device.smoothedRssi))
                    .frame(width: 6, height: 6)
                Text("\(Int(device.smoothedRssi)) dBm")
                    .font(AppFont.pretendard(13, weight: .semibold))
                    .foregroundStyle(barColor(for: device.smoothedRssi))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func barColor(for rssi: Double) -> Color {
        if rssi >= -65 { return Palette.lime }
        if rssi >= -80 { return Palette.amber }
        return Palette.crimson
    }

    private var sortedDevices: [DiscoveredDevice] {
        scanner.devices.values
            .filter { !hideUnknown || $0.name != "Unknown" }
            .sorted { $0.smoothedRssi > $1.smoothedRssi }
    }
}

// MARK: - Password sheet

struct PasswordSheetView: View {
    let hasPassword: Bool
    let onSave: (String) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var password: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Caption(text: hasPassword ? "암호 변경" : "암호 설정")
                Text("로그인 암호 저장")
                    .font(AppFont.pretendard(18, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Text("자동 잠금 해제용으로 macOS Keychain에 저장됩니다. 다른 곳으로 전송되지 않으며, 토글을 끄거나 삭제하면 즉시 제거됩니다.")
                    .font(AppFont.pretendard(13))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ASCIISecureField(text: $password, placeholder: "로그인 암호")
                .frame(height: 38)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 0.5)
                )

            HStack {
                if hasPassword {
                    Button("저장된 암호 삭제") { onDelete() }
                        .buttonStyle(.plain)
                        .font(AppFont.pretendard(13, weight: .medium))
                        .foregroundStyle(Palette.crimson)
                }
                Spacer()
                Button("취소") { onCancel() }
                    .buttonStyle(.plain)
                    .font(AppFont.pretendard(13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.stroke, lineWidth: 0.5)
                    )
                    .keyboardShortcut(.cancelAction)
                Button("저장") { onSave(password) }
                    .buttonStyle(.plain)
                    .font(AppFont.pretendard(13, weight: .bold))
                    .foregroundStyle(Palette.onLime)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(password.isEmpty ? Palette.lime.opacity(0.4) : Palette.lime)
                    )
                    .disabled(password.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(Palette.bg)
    }
}

// MARK: - ASCII-only secure text field

/// `NSSecureTextField` wrapper that:
///   1. Reports `allowsCharacterPicker = false` and disables marked text so
///      Korean/Japanese/Chinese IMEs cannot swallow keys for composition.
///   2. Auto-focuses and grabs first-responder once mounted, so the user can
///      start typing immediately when the window opens.
struct ASCIISecureField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = ASCIIOnlySecureTextField(string: text)
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont(name: "Pretendard", size: 14) ?? NSFont.systemFont(ofSize: 14)
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                text.wrappedValue = field.stringValue
            }
        }
    }
}

/// NSSecureTextField that constrains its field editor to ASCII input sources
/// (Roman/Latin), so Korean/Japanese/Chinese IMEs cannot intercept alphabet
/// keys for composition. AppKit honors `allowedInputSourceLocales` on the
/// field editor's inputContext and routes keystrokes through an ABC-only
/// input source while this responder is active, regardless of the user's
/// system-wide input source choice.
private final class ASCIIOnlySecureTextField: NSSecureTextField {
    override var allowsVibrancy: Bool { false }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if let editor = currentEditor() {
            editor.inputContext?.allowedInputSourceLocales = [
                NSAllRomanInputSourcesLocaleIdentifier
            ]
            (editor as? NSTextView)?.unmarkText()
            editor.inputContext?.discardMarkedText()
            editor.inputContext?.invalidateCharacterCoordinates()
        }
        return ok
    }
}
