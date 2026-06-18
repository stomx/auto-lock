import SwiftUI
import AppKit
import AutoLockCore
import AutoLockKit

/// Standalone device-picker screen, hosted by `PickerWindow`. Extracted from
/// MenuView.swift; shares design tokens via `DesignSystem.swift`.
struct DevicePickerView: View {
    @ObservedObject var scanner: BLEScanner
    @ObservedObject var settings: AutoLockKit.Settings
    let onClose: () -> Void
    @State private var nameOverride: String = ""
    @State private var hideUnknown: Bool = true

    var body: some View {
        // Compute the filtered/sorted list once per render — it feeds both the
        // count badge and the ForEach below.
        let devices = sortedDevices
        return VStack(alignment: .leading, spacing: 14) {
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
                    Text("\(devices.count)개 감지됨")
                        .font(AppFont.pretendard(13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(devices, id: \.id) { device in
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
