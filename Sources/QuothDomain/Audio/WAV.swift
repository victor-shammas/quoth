import Foundation

/// 16 kHz mono samples as a 16-bit PCM WAV file, for listening to a capture
/// (`QUOTH_DUMP_WAV`).
public enum WAVWriter {
    public static func write(samples: [Float], sampleRate: Int, to path: String) throws {
        let bytes = samples.count * 2
        var data = Data("RIFF".utf8)
        data.append(littleEndian: UInt32(36 + bytes))
        data.append(contentsOf: Data("WAVEfmt ".utf8))
        data.append(littleEndian: UInt32(16)) // fmt chunk size
        data.append(littleEndian: UInt16(1)) // PCM
        data.append(littleEndian: UInt16(1)) // mono
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: UInt32(sampleRate * 2)) // bytes a second
        data.append(littleEndian: UInt16(2)) // block align
        data.append(littleEndian: UInt16(16)) // bits a sample
        data.append(contentsOf: Data("data".utf8))
        data.append(littleEndian: UInt32(bytes))
        for sample in samples {
            data.append(littleEndian: UInt16(bitPattern: Int16(max(-1, min(1, sample)) * 32767)))
        }
        try data.write(to: URL(fileURLWithPath: path))
    }
}

extension Data {
    fileprivate mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

/// The root mean square of `samples`: their level, 0 for none.
public func computeRMS<C: Collection>(_ samples: C) -> Float where C.Element == Float {
    guard !samples.isEmpty else { return 0 }
    let power = samples.reduce(0.0) { $0 + Double($1 * $1) }
    return Float((power / Double(samples.count)).squareRoot())
}
