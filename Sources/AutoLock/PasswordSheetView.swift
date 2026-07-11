import SwiftUI

/// Standalone password-entry screen for the auto-unlock feature, hosted by
/// `PasswordWindow`. Extracted from MenuView.swift; shares design tokens via
/// `DesignSystem.swift`. `ASCIISecureField` lives in `PasswordWindow.swift`.
struct PasswordSheetView: View {
    let hasPassword: Bool
    let onSave: (String) -> Bool
    let onDelete: () -> Bool
    let onCancel: () -> Void

    @State private var password: String = ""
    @State private var errorMessage: String?
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

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.pretendard(12, weight: .medium))
                    .foregroundStyle(Palette.crimson)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if hasPassword {
                    Button("저장된 암호 삭제") {
                        if !onDelete() { errorMessage = "Keychain에서 암호를 삭제하지 못했습니다." }
                    }
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
                Button("저장") {
                    if !onSave(password) { errorMessage = "AutoLock 전용 접근 제어를 만들지 못해 암호를 저장하지 않았습니다." }
                }
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
