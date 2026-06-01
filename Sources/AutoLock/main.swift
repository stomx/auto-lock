import Foundation

// 진입점 분기.
// 첫 인자가 "diagnose"면 GUI를 띄우지 않고 진단 서브커맨드를 실행한 뒤 종료한다
// (Diagnostics.run 내부에서 exit() 호출). 그 외에는 평소대로 메뉴바 앱을 기동한다.
// SwiftUI App 프로토콜은 static func main()을 자동 제공하므로 수동 호출이 가능하다.
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "diagnose" {
    Diagnostics.run(Array(args.dropFirst()))
} else {
    AutoLockApp.main()
}
