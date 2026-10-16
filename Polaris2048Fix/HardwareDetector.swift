import Foundation

/// Hardware detection is read-only and deliberately independent of OpenCore.
/// It identifies AMD devices, NOT their verified OpenCore device paths.
struct DetectedAMDDevice: Identifiable {
    let name: String
    let vendorID: UInt16
    let deviceID: UInt16
    let pciDebug: String
    var id: String { "\(vendorID)-\(deviceID)-\(pciDebug)-\(name)" }
    var label: String {
        let pci = pciDebug.isEmpty ? "PCI não informado" : "PCI \(pciDebug)"
        return String(format: "%@ · %04X:%04X · %@", name, vendorID, deviceID, pci)
    }
}

enum HardwareDetector {
    static func scanAMD() throws -> [DetectedAMDDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-a", "-r", "-c", "IOPCIDevice", "-w", "0"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain the pipe before waitUntilExit to avoid a deadlock on large IORegistry dumps.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PolarisError.invalid("ioreg retornou código \(process.terminationStatus)")
        }
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        var results: [DetectedAMDDevice] = []
        walk(plist, found: &results)
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    private static func walk(_ obj: Any, found: inout [DetectedAMDDevice]) {
        if let items = obj as? [Any] {
            for item in items { walk(item, found: &found) }
            return
        }
        guard let dict = obj as? [String: Any] else { return }
        if let vendor = u16(dict["vendor-id"]), vendor == 0x1002,
           let device = u16(dict["device-id"]),
           isDisplayController(dict["class-code"], device: device) {
            let name = readable(dict["model"]) ?? readable(dict["IOName"]) ??
                       readable(dict["name"]) ?? "Dispositivo AMD"
            let debug = readable(dict["pcidebug"]) ?? ""
            found.append(DetectedAMDDevice(name: name, vendorID: vendor,
                                           deviceID: device, pciDebug: debug))
        }
        for value in dict.values {
            if value is [String: Any] || value is [Any] { walk(value, found: &found) }
        }
    }

    private static func isDisplayController(_ value: Any?, device: UInt16) -> Bool {
        if let data = value as? Data, data.count >= 4 {
            let raw = UInt32(data[data.startIndex]) |
                      (UInt32(data[data.startIndex + 1]) << 8) |
                      (UInt32(data[data.startIndex + 2]) << 16) |
                      (UInt32(data[data.startIndex + 3]) << 24)
            return ((raw >> 16) & 0xFF) == 0x03
        }
        // Some IORegistry nodes omit class-code; only allow our known Polaris IDs.
        return device == 0x6FDF || device == 0x67DF
    }

    private static func u16(_ value: Any?) -> UInt16? {
        if let data = value as? Data, data.count >= 2 {
            return UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
        }
        if let num = value as? NSNumber { return UInt16(truncatingIfNeeded: num.uint32Value) }
        return nil
    }

    private static func readable(_ value: Any?) -> String? {
        if let str = value as? String, !str.isEmpty { return str }
        if let data = value as? Data, !data.isEmpty {
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .controlCharacters)
            return text.isEmpty ? nil : text
        }
        return nil
    }
}
