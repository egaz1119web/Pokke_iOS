import SwiftUI
import XCTest

/// アイコンのパス解釈。ここが止まると画面全体が描けなくなるので、
/// 実際に使っている難しい形のパスを通しておく。
final class SVGPathTests: XCTestCase {

    func testConsecutiveDecimalsAreSeparateNumbers() {
        // SVGの "1.1.9" は「1.1 と 0.9」の2つ。1つの数として読むと解釈できず、
        // パーサが同じ位置を読み続けて画面が固まる（Utensilsアイコンで実際に起きた）
        let path = SVGPath.parse("M0 0c0 1.1.9 2 2 2")

        XCTAssertFalse(path.isEmpty)
        XCTAssertFalse(path.boundingRect.isNull)
    }

    func testEveryCollectionIconParsesIntoAShape() {
        // 12種すべて。1つでも空なら選択ダイアログに絵が出ない
        for icon in CollectionIcons.all {
            let path = SVGPath.parse(Self.iconData[icon]!)
            XCTAssertFalse(path.isEmpty, icon)
        }
    }

    func testArcsProduceACircle() {
        // 円は "a r,r 0 1,0 2r,0" を2つ繋いだ形で書いてある
        let path = SVGPath.parse("M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0")
        let bounds = path.boundingRect

        XCTAssertEqual(bounds.minX, 2, accuracy: 0.01)
        XCTAssertEqual(bounds.maxX, 22, accuracy: 0.01)
        XCTAssertEqual(bounds.minY, 2, accuracy: 0.01)
        XCTAssertEqual(bounds.maxY, 22, accuracy: 0.01)
    }

    /// 円弧の向き（sweep-flag）を取り違えると、ハートのように弧が一部だけの絵が崩れる
    func testPartialArcsKeepTheirIntendedShape() {
        let heart = SVGPath.parse(Self.iconData["heart"]!)
        let bounds = heart.boundingRect

        XCTAssertEqual(bounds.minX, 2, accuracy: 0.5)
        XCTAssertEqual(bounds.maxX, 22, accuracy: 0.5)
        XCTAssertEqual(bounds.minY, 3, accuracy: 0.5)
        XCTAssertEqual(bounds.maxY, 21, accuracy: 0.5)
    }

    /// 円弧を含む形は1本の線として繋がっていること。
    /// 別のパスとして作って継ぎ足すと、そこで線が途切れて絵が崩れる
    func testArcsStayInTheSameSubpath() {
        var moves = 0
        SVGPath.parse(Self.iconData["heart"]!).cgPath.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { moves += 1 }
        }

        XCTAssertEqual(moves, 1)
    }

    func testRelativeAndAbsoluteCommandsAgree() {
        let absolute = SVGPath.parse("M5 12H19")
        let relative = SVGPath.parse("m5 12h14")

        XCTAssertEqual(absolute.boundingRect, relative.boundingRect)
    }

    func testGarbageStopsInsteadOfLooping() {
        // 解釈できない字が残っていても戻ってくること（無限ループ防止）
        XCTAssertTrue(SVGPath.parse("M0 0 ???").boundingRect.isEmpty)
        XCTAssertTrue(SVGPath.parse("").isEmpty)
    }

    /// `Lucide` はアプリ本体のターゲットにあるので、検証したいパスだけ写している
    private static let iconData: [String: String] = [
        "bookmark": "m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2Z",
        "utensils": "M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7",
        "gamepad": "M17.32 5H6.68a4 4 0 0 0-3.978 3.59c-.006.052-.01.101-.017.152C2.604 9.416 2 14.456 2 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.414-1.414A2 2 0 0 1 9.828 16h4.344a2 2 0 0 1 1.414.586L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.545-.604-6.584-.685-7.258-.007-.05-.011-.1-.017-.151A4 4 0 0 0 17.32 5z",
        "bulb": "M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5",
        "headphones": "M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 18 0v7a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3",
        "plane": "M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z",
        "bag": "M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z",
        "clap": "M20.2 6 3 11l-.9-2.4c-.3-1.1.3-2.2 1.3-2.5l13.5-4c1.1-.3 2.2.3 2.5 1.3Z",
        "briefcase": "M2 8a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2Z",
        "paw": "M9 10a5 5 0 0 1 5 5v3.5a3.5 3.5 0 0 1-6.84 1.045Q6.52 17.48 4.46 16.84A3.5 3.5 0 0 1 5.5 10Z",
        "star": "M11.05 2.6a1 1 0 0 1 1.9 0l1.9 4.6 4.96.4a1 1 0 0 1 .59 1.8l-3.78 3.24 1.15 4.85a1 1 0 0 1-1.54 1.12L12 16l-4.23 2.6a1 1 0 0 1-1.54-1.11l1.15-4.85-3.78-3.24a1 1 0 0 1 .59-1.8l4.96-.4Z",
        "heart": "M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z",
    ]
}
