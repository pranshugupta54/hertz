import Foundation
import IOKit

/// CPU temperature and fan speeds read from the System Management Controller.
/// On a fanless Mac (e.g. MacBook Air) `fanRPM` is empty.
public struct SensorSnapshot {
    public var cpuTemperature: Double // °C, 0 when unavailable
    public var fanRPM: [Int]
    public init(cpuTemperature: Double = 0, fanRPM: [Int] = []) {
        self.cpuTemperature = cpuTemperature
        self.fanRPM = fanRPM
    }
}

// The AppleSMC user-client protocol. These struct layouts must match the
// kernel's `SMCKeyData_t` — Swift's natural alignment of these primitive
// fields matches the C ABI, so no explicit padding is needed.

private let kSMCUserClientSelector: UInt32 = 2
private let kSMCReadBytes: UInt8 = 5
private let kSMCGetKeyInfo: UInt8 = 9

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // Explicit trailing padding — without it Swift packs SMCKeyData's next
    // fields into this struct's pad, shrinking the layout below the 80 bytes
    // the kernel requires.
    var pad0: UInt8 = 0
    var pad1: UInt8 = 0
    var pad2: UInt8 = 0
}

/// 32-byte payload.
private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private let zeroBytes: SMCBytes = (
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var pad: UInt8 = 0          // explicit pad before the 4-byte data32
    var data32: UInt32 = 0
    var bytes: SMCBytes = zeroBytes
}

/// Opens one connection to AppleSMC and reads keys on demand.
public final class SMCReader {
    private var connection: io_connect_t = 0

    // Apple-silicon die-temperature sensor keys. Whichever ones exist on this
    // chip return valid readings; the rest are skipped.
    private let cpuTempKeys = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L",
                               "Tp0P", "Tp0T", "Tp0X", "Tp0b", "Tp0f", "Tp0j",
                               "Tp0n", "Te05", "Tg05"]

    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func read() -> SensorSnapshot {
        guard connection != 0 else { return SensorSnapshot() }
        var snap = SensorSnapshot()

        var sum = 0.0, count = 0
        for key in cpuTempKeys {
            if let value = readNumber(key), value > 10, value < 115 {
                sum += value
                count += 1
            }
        }
        if count > 0 { snap.cpuTemperature = sum / Double(count) }

        if let fanCount = readNumber("FNum"), fanCount >= 1 {
            for i in 0..<Int(fanCount) {
                if let rpm = readNumber("F\(i)Ac"), rpm > 0 {
                    snap.fanRPM.append(Int(rpm))
                }
            }
        }
        return snap
    }

    /// Debug: raw probe of a `#KEY` keyinfo call.
    public func debugInfo() -> String {
        let stride = MemoryLayout<SMCKeyData>.stride
        guard connection != 0 else { return "conn NOT open (stride \(stride))" }
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = encodeKey("#KEY")
        input.data8 = kSMCGetKeyInfo
        var outSize = stride
        let kr = IOConnectCallStructMethod(connection, kSMCUserClientSelector,
                                           &input, stride, &output, &outSize)
        return "stride=\(stride) kr=0x\(String(UInt32(bitPattern: kr), radix: 16)) "
            + "result=\(output.result) dataSize=\(output.keyInfo.dataSize) "
            + "dataType=0x\(String(output.keyInfo.dataType, radix: 16))"
    }

    /// Debug: enumerate every SMC key with the given prefix (empty = all).
    public func enumerateKeys(prefix: String) -> [(key: String, value: Double?)] {
        guard connection != 0, let count = readNumber("#KEY"), count > 0 else { return [] }
        var found: [(String, Double?)] = []
        for index in 0..<Int(count) {
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.data8 = 8 // kSMCGetKeyFromIndex
            input.data32 = UInt32(index)
            guard call(&input, &output) else { continue }
            let name = decodeKey(output.key)
            if name.hasPrefix(prefix) {
                found.append((name, readNumber(name)))
            }
        }
        return found
    }

    /// Read a key and decode it to a Double, or nil if absent/unsupported.
    private func readNumber(_ key: String) -> Double? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        let fourCC = encodeKey(key)

        // 1. key info — gives data size + type.
        input.key = fourCC
        input.data8 = kSMCGetKeyInfo
        guard call(&input, &output) else { return nil }
        let dataSize = output.keyInfo.dataSize
        let dataType = output.keyInfo.dataType
        guard dataSize > 0 else { return nil }

        // 2. the bytes.
        input = SMCKeyData()
        input.key = fourCC
        input.data8 = kSMCReadBytes
        input.keyInfo.dataSize = dataSize
        guard call(&input, &output), output.result == 0 else { return nil }

        return decode(output.bytes, type: dataType, size: dataSize)
    }

    private func call(_ input: inout SMCKeyData, _ output: inout SMCKeyData) -> Bool {
        var outSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(connection, kSMCUserClientSelector,
                                           &input, MemoryLayout<SMCKeyData>.stride,
                                           &output, &outSize)
        return kr == kIOReturnSuccess
    }

    /// Decode the leading bytes of the payload by SMC data type.
    private func decode(_ bytes: SMCBytes, type: UInt32, size: UInt32) -> Double? {
        var buffer = bytes
        return withUnsafeBytes(of: &buffer) { raw -> Double? in
            switch type {
            case encodeKey("flt "):
                guard size == 4 else { return nil }
                return Double(raw.load(as: Float32.self))
            case encodeKey("ui8 "), encodeKey("ui16"), encodeKey("ui32"):
                var value: UInt64 = 0
                for i in 0..<min(Int(size), 8) {
                    value |= UInt64(raw[i]) << (8 * i)
                }
                return Double(value)
            case encodeKey("sp78"):
                // signed fixed-point, 8 integer + 8 fraction bits.
                guard size == 2 else { return nil }
                let signed = Int16(bitPattern: UInt16(raw[0]) << 8 | UInt16(raw[1]))
                return Double(signed) / 256.0
            default:
                return nil
            }
        }
    }
}

/// Unpack a UInt32 FourCC back into its 4-character key string.
private func decodeKey(_ code: UInt32) -> String {
    let chars: [UInt8] = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
                          UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
    return String(decoding: chars, as: UTF8.self)
}

/// A 4-character SMC key packed big-endian into a UInt32.
private func encodeKey(_ key: String) -> UInt32 {
    var result: UInt32 = 0
    for byte in key.utf8.prefix(4) {
        result = (result << 8) | UInt32(byte)
    }
    return result
}
