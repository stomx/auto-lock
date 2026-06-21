import Foundation

/// `diagnose update` / `diagnose self-update`가 공유하는 공통 인자(`--current`,
/// `--feed`) 파싱을 담는 순수 값 타입. 시스템 부수효과(네트워크/파일/exit)와
/// 분리돼 있어 단위 테스트가 가능하다. Diagnostics는 이 결과를 받아 부작용만
/// 수행한다.
public enum DiagnoseArgs {
    /// `--current`/`--feed` 파싱 결과.
    public struct CommonOptions: Equatable {
        /// 비교 기준이 될 현재 버전. `--current <ver>`가 없으면 `defaultCurrent`.
        public let currentVersion: SemanticVersion
        /// 파싱에 쓰인 버전 원문(`--current` 값 또는 `defaultCurrent`). 진단
        /// 출력에 사용자가 입력한 그대로 표시하기 위해 정규화 전 문자열을 보존한다.
        public let currentRaw: String
        /// `--feed <url>`로 지정한 릴리스 피드 출처. 없으면 nil(기본 피드 사용).
        public let feedURL: URL?

        public init(currentVersion: SemanticVersion, currentRaw: String, feedURL: URL?) {
            self.currentVersion = currentVersion
            self.currentRaw = currentRaw
            self.feedURL = feedURL
        }
    }

    /// 파싱 결과 — 성공이면 옵션을, 실패면 사람이 읽을 에러 메시지를 담는다.
    /// 호출부(Diagnostics)는 `.failure`를 받으면 그 메시지를 출력하고 exit(2)한다.
    public enum Outcome: Equatable {
        case ok(CommonOptions)
        case failure(String)
    }

    /// `--current`/`--feed` 플래그를 파싱한다. 동작은 기존 Diagnostics의
    /// runUpdate/runSelfUpdate에 복붙돼 있던 로직과 동일하다:
    /// - `--current` 뒤에 값이 있으면 그 값을, 없으면(플래그가 마지막) `defaultCurrent`를 파싱.
    /// - 현재 버전 파싱 실패 시 `.failure`를 먼저 반환(피드보다 우선 검사).
    /// - `--feed` 뒤에 값이 있으면 URL로 파싱, 실패 시 `.failure`. 값이 없으면 nil.
    public static func parseCommon(_ args: [String], defaultCurrent: String) -> Outcome {
        var currentRaw = defaultCurrent
        if let i = args.firstIndex(of: "--current"), i + 1 < args.count {
            currentRaw = args[i + 1]
        }
        guard let current = SemanticVersion(currentRaw) else {
            return .failure("❌ --current 버전 파싱 실패: \(currentRaw)")
        }

        var feedURL: URL? = nil
        if let i = args.firstIndex(of: "--feed"), i + 1 < args.count {
            guard let u = URL(string: args[i + 1]) else {
                return .failure("❌ --feed URL 파싱 실패: \(args[i + 1])")
            }
            feedURL = u
        }

        return .ok(CommonOptions(currentVersion: current, currentRaw: currentRaw, feedURL: feedURL))
    }
}
