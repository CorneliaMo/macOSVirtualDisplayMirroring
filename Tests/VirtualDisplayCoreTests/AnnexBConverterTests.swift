import Foundation
import Testing
@testable import VirtualDisplayCore

@Test func convertsMultipleNALUnits() throws {
    let avcc = Data([0,0,0,2,0x67,0x01, 0,0,0,3,0x65,0x02,0x03])
    #expect(try AnnexBConverter.convertAVCC(avcc) == Data([0,0,0,1,0x67,0x01, 0,0,0,1,0x65,0x02,0x03]))
}

@Test func rejectsTruncatedNALUnit() { #expect(throws: Error.self) { try AnnexBConverter.convertAVCC(Data([0,0,0,5,1])) } }
