import CoreGraphics
import SwiftUI

/// SVGの `d` 属性を `Path` に変換する。
///
/// アイコンをライブラリで持たず、Android版と同じパスデータを写して使うため
/// （[Lucide] のコメント参照）、その文字列を解釈する最小限の実装を置いている。
/// 対応コマンドは M/L/H/V/C/S/Q/T/A/Z（大文字＝絶対、小文字＝相対）。
enum SVGPath {

    static func parse(_ d: String) -> Path {
        // SwiftUIの Path ではなく CGMutablePath に積む。円弧を別のパスとして作って
        // 継ぎ足すと、そこで図形が分断されてしまう（線が途切れ、Zの閉じ先もずれる）
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        // S / T の反射に使う直前の制御点
        var lastControl: CGPoint?
        var lastCommand: Character = " "

        var scanner = TokenScanner(d)
        while let command = scanner.nextCommand() {
            let relative = command.isLowercase
            let op = Character(command.uppercased())

            // 引数が続く限り同じコマンドを繰り返す（"M" の後続は "L" 扱い）
            repeat {
                // 解釈できない字が残っていると同じ位置を読み続けてしまう。
                // 1周して1文字も進まなかったら打ち切る
                let before = scanner.position
                switch op {
                case "M":
                    guard let p = scanner.point(relativeTo: relative ? current : .zero) else { break }
                    path.move(to: p)
                    current = p
                    subpathStart = p
                    lastControl = nil
                    // 2組目以降は暗黙の L
                    while let next = scanner.point(relativeTo: relative ? current : .zero) {
                        path.addLine(to: next)
                        current = next
                    }
                case "L":
                    guard let p = scanner.point(relativeTo: relative ? current : .zero) else { break }
                    path.addLine(to: p)
                    current = p
                    lastControl = nil
                case "H":
                    guard let x = scanner.number() else { break }
                    let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
                    path.addLine(to: p)
                    current = p
                    lastControl = nil
                case "V":
                    guard let y = scanner.number() else { break }
                    let p = CGPoint(x: current.x, y: relative ? current.y + y : y)
                    path.addLine(to: p)
                    current = p
                    lastControl = nil
                case "C":
                    let origin = relative ? current : .zero
                    guard let c1 = scanner.point(relativeTo: origin),
                          let c2 = scanner.point(relativeTo: origin),
                          let end = scanner.point(relativeTo: origin) else { break }
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                    lastControl = c2
                case "S":
                    let origin = relative ? current : .zero
                    guard let c2 = scanner.point(relativeTo: origin),
                          let end = scanner.point(relativeTo: origin) else { break }
                    let c1 = reflected(lastControl, around: current, active: "CS".contains(lastCommand.uppercased()))
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                    lastControl = c2
                case "Q":
                    let origin = relative ? current : .zero
                    guard let c = scanner.point(relativeTo: origin),
                          let end = scanner.point(relativeTo: origin) else { break }
                    path.addQuadCurve(to: end, control: c)
                    current = end
                    lastControl = c
                case "T":
                    let origin = relative ? current : .zero
                    guard let end = scanner.point(relativeTo: origin) else { break }
                    let c = reflected(lastControl, around: current, active: "QT".contains(lastCommand.uppercased()))
                    path.addQuadCurve(to: end, control: c)
                    current = end
                    lastControl = c
                case "A":
                    guard let rx = scanner.number(), let ry = scanner.number(),
                          let rotation = scanner.number(),
                          let largeArc = scanner.number(), let sweep = scanner.number(),
                          let endRaw = scanner.point(relativeTo: .zero) else { break }
                    let end = relative
                        ? CGPoint(x: current.x + endRaw.x, y: current.y + endRaw.y)
                        : endRaw
                    appendArc(
                        to: path,
                        from: current,
                        to: end,
                        rx: rx,
                        ry: ry,
                        rotationDegrees: rotation,
                        largeArc: largeArc != 0,
                        sweep: sweep != 0
                    )
                    current = end
                    lastControl = nil
                case "Z":
                    path.closeSubpath()
                    current = subpathStart
                    lastControl = nil
                default:
                    break
                }
                lastCommand = command
                if scanner.position == before { break }
            } while op != "Z" && op != "M" && scanner.hasNumberNext
        }
        return Path(path)
    }

    private static func reflected(_ control: CGPoint?, around current: CGPoint, active: Bool) -> CGPoint {
        guard active, let control else { return current }
        return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    /// 端点指定の円弧を中心指定へ変換して追加する（SVG仕様 F.6.5 のとおり）
    private static func appendArc(
        to path: CGMutablePath,
        from start: CGPoint,
        to end: CGPoint,
        rx rxIn: CGFloat,
        ry ryIn: CGFloat,
        rotationDegrees: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        if start == end { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            path.addLine(to: end)
            return
        }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2, dy2 = (start.y - end.y) / 2
        let x1 = cosPhi * dx2 + sinPhi * dy2
        let y1 = -sinPhi * dx2 + cosPhi * dy2

        // 半径が小さすぎて端点を結べない場合は広げる
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cx1 = coefficient * rx * y1 / ry
        let cy1 = -coefficient * ry * x1 / rx

        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

        let startAngle = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        let endAngle = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx)
        var delta = endAngle - startAngle
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // 楕円＋回転はそのまま描けないので、単位円の円弧に変換してから戻す
        let transform = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: phi)
            .scaledBy(x: rx, y: ry)
        path.addArc(
            center: .zero,
            radius: 1,
            startAngle: startAngle,
            endAngle: startAngle + delta,
            clockwise: delta < 0,
            transform: transform
        )
    }
}

/// パス文字列を「コマンド1文字」と「数値」に切り分ける
private struct TokenScanner {
    private let chars: [Character]
    private var index = 0

    init(_ text: String) {
        chars = Array(text)
    }

    /// 読み進めた位置。進んでいないことの検出に使う
    var position: Int { index }

    private mutating func skipSeparators() {
        while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" || chars[index] == "\t" {
            index += 1
        }
    }

    mutating func nextCommand() -> Character? {
        skipSeparators()
        guard index < chars.count else { return nil }
        let c = chars[index]
        guard c.isLetter else { return nil }
        index += 1
        return c
    }

    /// 次のトークンが数値か（同じコマンドを繰り返すかの判定に使う）
    var hasNumberNext: Bool {
        var i = index
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        guard i < chars.count else { return false }
        let c = chars[i]
        return c.isNumber || c == "-" || c == "+" || c == "."
    }

    mutating func number() -> CGFloat? {
        skipSeparators()
        var text = ""
        if index < chars.count, chars[index] == "-" || chars[index] == "+" {
            text.append(chars[index])
            index += 1
        }
        // 小数点は1つまで。SVGでは "1.1.9" が「1.1 と 0.9」の2つを意味するので、
        // まとめて読むと数として解釈できずパースが止まってしまう
        var seenDot = false
        while index < chars.count {
            let c = chars[index]
            if c.isNumber {
                text.append(c)
                index += 1
            } else if c == "." {
                if seenDot { break }
                seenDot = true
                text.append(c)
                index += 1
            } else if c == "e" || c == "E" {
                seenDot = true
                text.append(c)
                index += 1
                if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                    text.append(chars[index])
                    index += 1
                }
            } else {
                break
            }
        }
        guard let value = Double(text) else { return nil }
        return CGFloat(value)
    }

    mutating func point(relativeTo origin: CGPoint) -> CGPoint? {
        let saved = index
        guard let x = number(), let y = number() else {
            index = saved
            return nil
        }
        return CGPoint(x: origin.x + x, y: origin.y + y)
    }
}
