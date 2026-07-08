import Compression
import XCTest
@testable import Riddle

/// Minimal, JSON-only mirror of HandBank's private `VariantRef`, used to independently
/// cross-check `HandBank.strokes(for:variant:)` against the raw index file in the bundle.
private struct IndexVariantRef: Decodable {
    let offset: Int
    let length: Int
    let nStrokes: Int
    enum CodingKeys: String, CodingKey {
        case offset, length
        case nStrokes = "n_strokes"
    }
}

final class HandBankTests: XCTestCase {

    // MARK: - Gunzip helper (focused round-trip test, no real bank files involved)

    func testGunzipRoundTripsAKnownString() throws {
        let original = "hello handwriting bank 你好世界".data(using: .utf8)!
        let gz = try Self.makeGzip(from: original)
        let inflated = try Gunzip.inflate(gz)
        XCTAssertEqual(inflated, original)
    }

    func testGunzipRoundTripsEmptyPayload() throws {
        let original = Data()
        let gz = try Self.makeGzip(from: original)
        let inflated = try Gunzip.inflate(gz)
        XCTAssertEqual(inflated, original)
    }

    func testGunzipRejectsBadMagic() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
                             0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        XCTAssertThrowsError(try Gunzip.inflate(garbage))
    }

    // MARK: - HandBank.load

    func testLoadRealBankSucceeds() {
        XCTAssertNotNil(HandBank.load(style: "neat-C002"))
    }

    func testLoadUnknownStyleReturnsNil() {
        XCTAssertNil(HandBank.load(style: "nonexistent-style"))
    }

    // MARK: - contains

    func testContainsCommonChar() throws {
        let bank = try XCTUnwrap(HandBank.load(style: "neat-C002"))
        XCTAssertTrue(bank.contains("哈"))
    }

    func testDoesNotContainCharOutsideBank() throws {
        let bank = try XCTUnwrap(HandBank.load(style: "neat-C002"))
        // A rare CJK-extension character far outside GB2312/the pilot vocabulary.
        XCTAssertFalse(bank.contains("𰻝"))
        // An emoji is also outside the bank.
        XCTAssertFalse(bank.contains("😀"))
    }

    // MARK: - strokes(for:variant:)

    func testStrokesForCommonCharAreValidAndMatchIndex() throws {
        let bank = try XCTUnwrap(HandBank.load(style: "neat-C002"))
        let strokes = try XCTUnwrap(bank.strokes(for: "哈", variant: 0))
        XCTAssertFalse(strokes.isEmpty)

        for stroke in strokes {
            XCTAssertFalse(stroke.isEmpty)
            for point in stroke {
                XCTAssertTrue((0...1).contains(point.x), "x \(point.x) out of [0,1]")
                XCTAssertTrue((0...1).contains(point.y), "y \(point.y) out of [0,1]")
            }
        }

        let expectedNStrokes = try Self.loadIndexNStrokes(char: "哈", variant: 0)
        XCTAssertEqual(strokes.count, expectedNStrokes)
    }

    func testStrokesOutOfRangeVariantReturnsNil() throws {
        let bank = try XCTUnwrap(HandBank.load(style: "neat-C002"))
        XCTAssertNil(bank.strokes(for: "哈", variant: 99))
    }

    // MARK: - Test helpers

    /// Builds a standards-conformant gzip byte stream (10-byte header, FLG=0, raw
    /// DEFLATE payload via the Compression framework, CRC32 + ISIZE trailer) around
    /// `data`, entirely independent of HandBank's own gunzip implementation.
    private static func makeGzip(from data: Data) throws -> Data {
        let srcBytes = [UInt8](data)
        let dstCapacity = max(srcBytes.count * 2, 64)
        var dstBuffer = [UInt8](repeating: 0, count: dstCapacity)
        let compressedSize = dstBuffer.withUnsafeMutableBufferPointer { dst -> Int in
            srcBytes.withUnsafeBufferPointer { src -> Int in
                compression_encode_buffer(
                    dst.baseAddress!, dstCapacity,
                    src.baseAddress ?? UnsafePointer(bitPattern: 1)!, srcBytes.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard compressedSize > 0 || srcBytes.isEmpty else {
            throw NSError(domain: "HandBankTests", code: 1)
        }

        var out = Data()
        out.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00]) // magic, CM=deflate, FLG=0
        out.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // MTIME
        out.append(contentsOf: [0x00, 0xff])              // XFL, OS=unknown
        out.append(contentsOf: dstBuffer[0..<compressedSize])

        let crc = Self.crc32(srcBytes)
        withUnsafeBytes(of: crc.littleEndian) { out.append(contentsOf: $0) }
        let isize = UInt32(truncatingIfNeeded: srcBytes.count)
        withUnsafeBytes(of: isize.littleEndian) { out.append(contentsOf: $0) }
        return out
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -(Int32(crc & 1)))
                crc = (crc >> 1) ^ (0xEDB88320 & mask)
            }
        }
        return ~crc
    }

    /// Independently reads + inflates + decodes `neat-C002.index.json.gz` straight from
    /// the bundle (bypassing HandBank entirely) to cross-check stroke counts.
    private static func loadIndexNStrokes(char: Character, variant: Int) throws -> Int {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "neat-C002.index.json", withExtension: "gz"))
        let gz = try Data(contentsOf: url)
        let json = try Gunzip.inflate(gz)
        let index = try JSONDecoder().decode([String: [IndexVariantRef]].self, from: json)
        let refs = try XCTUnwrap(index[String(char)])
        return refs[variant].nStrokes
    }
}
