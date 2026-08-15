import XCTest
@testable import PTT

final class TelnetNegotiatorTests: XCTestCase {
    func testPlainDataPassesThroughUnchanged() {
        var negotiator = TelnetNegotiator()
        let result = negotiator.process(Array("hello".utf8))
        XCTAssertEqual(result.payload, Array("hello".utf8))
        XCTAssertTrue(result.reply.isEmpty)
    }

    func testWillOptionIsRefusedWithDont() {
        var negotiator = TelnetNegotiator()
        let iac: UInt8 = 255, will: UInt8 = 251
        let echoOption: UInt8 = 1
        let result = negotiator.process([iac, will, echoOption])
        XCTAssertEqual(result.reply, [iac, 254 /* DONT */, echoOption])
        XCTAssertTrue(result.payload.isEmpty)
    }

    func testDoOptionIsRefusedWithWont() {
        var negotiator = TelnetNegotiator()
        let iac: UInt8 = 255, doCmd: UInt8 = 253
        let option: UInt8 = 24
        let result = negotiator.process([iac, doCmd, option])
        XCTAssertEqual(result.reply, [iac, 252 /* WONT */, option])
    }

    func testIACSequenceIsStrippedFromPayloadAroundData() {
        var negotiator = TelnetNegotiator()
        let iac: UInt8 = 255, will: UInt8 = 251
        var bytes = Array("before".utf8)
        bytes.append(contentsOf: [iac, will, 3])
        bytes.append(contentsOf: Array("after".utf8))
        let result = negotiator.process(bytes)
        XCTAssertEqual(result.payload, Array("beforeafter".utf8))
    }

    func testSubnegotiationIsSwallowed() {
        var negotiator = TelnetNegotiator()
        let iac: UInt8 = 255, sb: UInt8 = 250, se: UInt8 = 240
        var bytes = Array("a".utf8)
        bytes.append(contentsOf: [iac, sb, 24, 0, 1, 2, iac, se])
        bytes.append(contentsOf: Array("b".utf8))
        let result = negotiator.process(bytes)
        XCTAssertEqual(result.payload, Array("ab".utf8))
    }

    func testStateSurvivesAcrossChunkBoundaries() {
        var negotiator = TelnetNegotiator()
        let iac: UInt8 = 255, will: UInt8 = 251
        let first = negotiator.process([iac])
        XCTAssertTrue(first.payload.isEmpty)
        XCTAssertTrue(first.reply.isEmpty)
        let second = negotiator.process([will, 1])
        XCTAssertEqual(second.reply, [iac, 254, 1])
    }
}
