import CoreGraphics
import Compression
import Foundation

/// Errors thrown while inflating a gzip payload with the system Compression framework.
enum GunzipError: Error {
    case tooShort
    case badMagic
    case unsupportedMethod
    case truncatedHeader
    case decodeFailed
}

/// Minimal gzip (RFC 1952) container reader that hands the raw DEFLATE payload to
/// Apple's Compression framework (`COMPRESSION_ZLIB`, which despite the name performs
/// raw-DEFLATE decoding, not zlib-wrapped decoding).
enum Gunzip {
    /// Inflate a full gzip byte stream (10-byte header + variable optional fields +
    /// raw DEFLATE data + 8-byte trailer) into its decompressed bytes.
    static func inflate(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { throw GunzipError.tooShort } // 10 header + 8 trailer minimum
        guard bytes[0] == 0x1f, bytes[1] == 0x8b else { throw GunzipError.badMagic }
        guard bytes[2] == 8 else { throw GunzipError.unsupportedMethod } // CM = deflate

        let flg = bytes[3]
        var pos = 10

        // FEXTRA
        if flg & 0x04 != 0 {
            guard pos + 2 <= bytes.count else { throw GunzipError.truncatedHeader }
            let xlen = Int(bytes[pos]) | (Int(bytes[pos + 1]) << 8)
            pos += 2 + xlen
        }
        // FNAME (null-terminated)
        if flg & 0x08 != 0 {
            while pos < bytes.count, bytes[pos] != 0 { pos += 1 }
            guard pos < bytes.count else { throw GunzipError.truncatedHeader }
            pos += 1
        }
        // FCOMMENT (null-terminated)
        if flg & 0x10 != 0 {
            while pos < bytes.count, bytes[pos] != 0 { pos += 1 }
            guard pos < bytes.count else { throw GunzipError.truncatedHeader }
            pos += 1
        }
        // FHCRC
        if flg & 0x02 != 0 {
            pos += 2
        }
        guard pos <= bytes.count - 8 else { throw GunzipError.truncatedHeader }

        let deflateBytes = Array(bytes[pos..<(bytes.count - 8)])

        // Trailer's ISIZE field (last 4 bytes, little-endian) is the exact decompressed
        // size mod 2^32 -- use it to size the destination buffer precisely.
        let isizeOffset = bytes.count - 4
        var isize: UInt32 = 0
        for i in 0..<4 {
            isize |= UInt32(bytes[isizeOffset + i]) << (8 * i)
        }
        let destSize = Int(isize)
        // ISIZE is authoritative for our payload sizes (all well under 4GB); a
        // reported empty output means there's nothing to inflate, and short-circuiting
        // here also sidesteps zero-length buffers having a nil `baseAddress`.
        guard destSize > 0 else { return Data() }
        guard !deflateBytes.isEmpty else { throw GunzipError.decodeFailed }

        var destBuffer = [UInt8](repeating: 0, count: destSize)
        let decodedCount = destBuffer.withUnsafeMutableBufferPointer { destPtr -> Int in
            deflateBytes.withUnsafeBufferPointer { srcPtr -> Int in
                compression_decode_buffer(
                    destPtr.baseAddress!, destSize,
                    srcPtr.baseAddress!, deflateBytes.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount > 0 else { throw GunzipError.decodeFailed }
        return Data(destBuffer[0..<decodedCount])
    }
}

/// One variant's byte range into the decompressed `<style>.bin` payload, as recorded
/// in `<style>.index.json.gz`. See handwriting-foundry's `export/FORMAT.md`.
private struct VariantRef: Decodable {
    let offset: Int
    let length: Int
    let nStrokes: Int
    let nPoints: Int
    let hitCap: Bool

    enum CodingKeys: String, CodingKey {
        case offset, length
        case nStrokes = "n_strokes"
        case nPoints = "n_points"
        case hitCap = "hit_cap"
    }
}

private struct Manifest: Decodable {
    let formatVersion: Int

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
    }
}

/// A loaded SDT handwriting trajectory bank for one style (e.g. "neat-C002"):
/// per-character, per-variant pre-generated stroke trajectories in unit em-box
/// coordinates ([0,1] x [0,1], origin top-left, y-down).
struct HandBank {
    private let binData: Data
    private let index: [String: [VariantRef]]

    private init(binData: Data, index: [String: [VariantRef]]) {
        self.binData = binData
        self.index = index
    }

    /// Loads `<style>.bin.gz` + `<style>.index.json.gz` + `manifest.json` from the app
    /// bundle. Returns nil if any file is missing, malformed, or the manifest's
    /// `format_version` isn't the one this decoder understands.
    static func load(style: String) -> HandBank? {
        guard
            let manifestURL = Bundle.main.url(forResource: "manifest", withExtension: "json"),
            let manifestData = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
            manifest.formatVersion == 1
        else { return nil }

        guard
            let binURL = Bundle.main.url(forResource: "\(style).bin", withExtension: "gz"),
            let indexURL = Bundle.main.url(forResource: "\(style).index.json", withExtension: "gz"),
            let binGz = try? Data(contentsOf: binURL),
            let indexGz = try? Data(contentsOf: indexURL)
        else { return nil }

        guard
            let binData = try? Gunzip.inflate(binGz),
            let indexData = try? Gunzip.inflate(indexGz),
            let index = try? JSONDecoder().decode([String: [VariantRef]].self, from: indexData)
        else { return nil }

        return HandBank(binData: binData, index: index)
    }

    /// True if this bank has trajectory data for `char` (any variant).
    func contains(_ char: Character) -> Bool {
        index[String(char)] != nil
    }

    /// Decodes a single record (one variant's trajectory data) from raw bytes.
    /// Performs bounds checking at each read to ensure truncated or malformed records
    /// return nil rather than crashing. Returns nil if the record is truncated.
    static func decodeRecord(_ bytes: [UInt8]) -> [[CGPoint]]? {
        var cursor = 0

        // Read n_strokes (1 byte)
        guard cursor + 1 <= bytes.count else { return nil }
        let nStrokes = Int(bytes[cursor])
        cursor += 1

        var strokes: [[CGPoint]] = []
        strokes.reserveCapacity(nStrokes)

        for _ in 0..<nStrokes {
            // Read n_points (2 bytes, little-endian)
            guard cursor + 2 <= bytes.count else { return nil }
            let nPts = Int(bytes[cursor]) | (Int(bytes[cursor + 1]) << 8)
            cursor += 2

            var pts: [CGPoint] = []
            pts.reserveCapacity(nPts)

            for _ in 0..<nPts {
                // Read (xq, yq) = 4 bytes total
                guard cursor + 4 <= bytes.count else { return nil }
                let xq = UInt16(bytes[cursor]) | (UInt16(bytes[cursor + 1]) << 8)
                let yq = UInt16(bytes[cursor + 2]) | (UInt16(bytes[cursor + 3]) << 8)
                cursor += 4

                pts.append(CGPoint(x: Double(xq) / 65535.0, y: Double(yq) / 65535.0))
            }
            strokes.append(pts)
        }
        return strokes
    }

    /// Returns `char`'s `variant`-th trajectory as arrays of unit-em-box CGPoints
    /// (x, y both in [0,1]), one inner array per stroke, points in stroke order.
    /// Returns nil if the char isn't in the bank or `variant` is out of range.
    func strokes(for char: Character, variant: Int) -> [[CGPoint]]? {
        guard let refs = index[String(char)], variant >= 0, variant < refs.count else { return nil }
        let ref = refs[variant]
        guard ref.offset >= 0, ref.length >= 0, ref.offset + ref.length <= binData.count else { return nil }

        let bytes = [UInt8](binData[ref.offset..<(ref.offset + ref.length)])
        return Self.decodeRecord(bytes)
    }
}
