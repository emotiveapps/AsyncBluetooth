import CoreBluetooth
import Foundation
import XCTest
@testable import AsyncBluetooth

/// emotiveapps: the restored state is kept for a caller that arrives after the event.
class RestoredStateTests: XCTestCase {
    func testNothingIsRestoredUntilIOSSaysSo() {
        XCTAssertNil(RestoredStateBox().value)
    }

    func testTheRestoredStateIsKeptForALateCaller() {
        let box = RestoredStateBox()
        box.keep([CBCentralManagerRestoredStateScanServicesKey: [CBUUID(string: "FEED")]])
        XCTAssertEqual(box.value?[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID], [CBUUID(string: "FEED")])
    }
}
