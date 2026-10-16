import Foundation
import CryptoKit

/// Offline-only builder. Never installs kexts, writes a mounted EFI, reads PCI registers,
/// changes firmware, or needs administrator privileges.
struct PolarisPreparer {
    static let expectedROMHash = "483b9fb9eaccd3cfdbb440389127c47c5decdc9e081cb624ffa0e3b952a42fba"
    static let expectedROMSize = 262_144
    static let imageSize = 65_536
    static let targetDeviceID = Data([0xDF, 0x67, 0x00, 0x00])

    func listGPUEntries(configURL: URL) throws -> [GPUEntry] {
        let plist = try loadConfig(configURL)
        let entries = try gpuEntries(plist)
        return entries.compactMap { (pciPath, properties) -> GPUEntry? in
            guard let properties = properties as? [String: Any], gpuLike(properties) else { return nil }
            let label = stringValue(properties["model"]) ?? stringValue(properties["device_type"]) ?? "GPU"
            return GPUEntry(path: pciPath, description: label)
        }.sorted { $0.path < $1.path }
    }

    func inspectROM(_ url: URL) throws -> String {
        let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard bytes.count == Self.expectedROMSize else {
            throw PolarisError.invalid("ROM de \(bytes.count) bytes; esperados 262144 bytes.")
        }
        let actualHash = sha256(bytes)
        guard actualHash == Self.expectedROMHash else {
            throw PolarisError.invalid("SHA-256 diferente da ROM modificada que já funcionou nessa placa. Evite usar firmware de outra placa.")
        }
        guard bytes[0] == 0x55 && bytes[1] == 0xAA,
              bytes[0xD4] == 0xF0 && bytes[0xD5] == 0x7D &&
              bytes[0xD6] == 0xE6 && bytes[0xD7] == 0x07,
              bytes[0x252] == 0xDF && bytes[0x253] == 0x67 else {
            throw PolarisError.invalid("Assinatura/bytes de patch da ROM não conferem.")
        }
        return "256 KiB; SHA-256 validado; a prévia utilizará os primeiros 64 KiB"
    }

    func prepare(configURL: URL, romURL: URL, outputParent: URL, pciPath: String) throws -> PreviewResult {
        // Read the original first; never modify its contents.
        try validateOutputFolder(outputParent, source: configURL)
        _ = try inspectROM(romURL)
        let rom = try Data(contentsOf: romURL)
        let image = rom.prefix(Self.imageSize)
        var root = try loadConfig(configURL)
        var deviceProperties = root["DeviceProperties"] as! [String: Any]
        var entries = try gpuEntries(root)
        guard validPCIPath(pciPath) else {
            throw PolarisError.invalid("Caminho PCI inválido. Use PciRoot(0x0)/Pci(0x...,0x...).")
        }
        var props = (entries[pciPath] as? [String: Any]) ?? [:]
        // Never overwrite an existing property group for another device.
        if !props.isEmpty && !gpuLike(props) {
            throw PolarisError.invalid("Este caminho já contém propriedades de outro dispositivo ou não é reconhecível como GPU. Não vou sobrescrevê-lo.")
        }
        // Do not alter unrelated properties, boot arguments, SMBIOS, other PCI devices, etc.
        props["ATY,bin_image"] = Data(image)
        props["device-id"] = Self.targetDeviceID
        entries[pciPath] = props
        deviceProperties["Add"] = entries
        root["DeviceProperties"] = deviceProperties

        let candidate = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        let parsedCandidate = try PropertyListSerialization.propertyList(from: candidate, options: [], format: nil)
        guard let parsed = parsedCandidate as? [String: Any],
              let checkedProps = try gpuEntries(parsed)[pciPath] as? [String: Any],
              checkedProps["device-id"] as? Data == Self.targetDeviceID,
              checkedProps["ATY,bin_image"] as? Data == Data(image) else {
            throw PolarisError.invalid("Falha na validação da prévia gerada.")
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let directory = outputParent.appendingPathComponent("Polaris2048Fix-Preview-\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path) else {
            throw PolarisError.invalid("Pasta de prévia já existe; não vou sobrescrever.")
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        // A newly created local folder contains both source backup and generated candidate.
        // A failed operation leaves the source untouched.
        let backupURL = directory.appendingPathComponent("config.original.backup.plist")
        let candidateURL = directory.appendingPathComponent("config.polaris-preview.plist")
        let reportURL = directory.appendingPathComponent("report.json")
        try manager.copyItem(at: configURL, to: backupURL)
        try candidate.write(to: candidateURL, options: .atomic)

        let onDiskCandidate = try Data(contentsOf: candidateURL)
        guard onDiskCandidate == candidate else {
            throw PolarisError.invalid("Prévia salva não corresponde aos dados verificados.")
        }
        let report: [String: Any] = [
            "status": "PREVIEW_ONLY_NOT_INSTALLED",
            "pci_path": pciPath,
            "rom_sha256": Self.expectedROMHash,
            "bin_image_bytes": Self.imageSize,
            "bin_image_sha256": sha256(Data(image)),
            "candidate_sha256": sha256(candidate),
            "target_device_id_data_hex": "df670000",
            "metal_confirmed": false,
            "opencore_validated": false,
            "efi_modified": false,
            "firmware_modified": false
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try reportData.write(to: reportURL, options: .atomic)
        return PreviewResult(
            folder: directory,
            summary: "Prévia e backup criados em \(directory.lastPathComponent). EFI e VBIOS não foram alteradas."
        )
    }

    private func loadConfig(_ url: URL) throws -> [String: Any] {
        guard url.isFileURL, url.lastPathComponent.lowercased() == "config.plist" else {
            throw PolarisError.invalid("Selecione um arquivo chamado config.plist.")
        }
        let bytes = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)
        guard let root = object as? [String: Any], root["DeviceProperties"] is [String: Any] else {
            throw PolarisError.invalid("O arquivo não possui DeviceProperties de OpenCore.")
        }
        return root
    }

    private func gpuEntries(_ root: [String: Any]) throws -> [String: Any] {
        guard let deviceProperties = root["DeviceProperties"] as? [String: Any],
              let add = deviceProperties["Add"] as? [String: Any] else {
            throw PolarisError.invalid("DeviceProperties/Add inválido.")
        }
        return add
    }

    private func gpuLike(_ props: [String: Any]) -> Bool {
        let text = "\(stringValue(props["device_type"]) ?? "") \(stringValue(props["model"]) ?? "")".lowercased()
        if text.contains("vga") || text.contains("radeon") || text.contains("display controller") || text.contains("amd gpu") { return true }
        if let id = props["device-id"] as? Data, id.count >= 2 {
            let code = UInt16(id[id.startIndex]) | (UInt16(id[id.startIndex + 1]) << 8)
            if code == 0x6FDF || code == 0x67DF { return true }
        }
        return false
    }

    private func validPCIPath(_ value: String) -> Bool {
        let pattern = #"^PciRoot\(0x[0-9a-fA-F]+\)(/Pci\(0x[0-9a-fA-F]+,0x[0-9a-fA-F]+\))+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func stringValue(_ property: Any?) -> String? {
        if let value = property as? String { return value }
        if let value = property as? Data { return String(data: value, encoding: .utf8) }
        return nil
    }

    private func validateOutputFolder(_ folder: URL, source: URL) throws {
        guard folder.isFileURL else { throw PolarisError.invalid("Saída deve ser uma pasta local.") }
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL
        let base = home.path.hasSuffix("/") ? home.path : home.path + "/"
        guard resolved.path.hasPrefix(base) else {
            throw PolarisError.invalid("Escolha uma pasta dentro da sua pasta de usuário (Documentos/Downloads/Área de Trabalho). Não escreva em EFI.")
        }
        let components = resolved.pathComponents.map { $0.lowercased() }
        guard !components.contains("efi") && !components.contains("oc") && !components.contains("volumes") else {
            throw PolarisError.invalid("Pasta de saída parece pertencer à EFI/OC. Escolha uma pasta local.")
        }
        guard resolved != source.deletingLastPathComponent().resolvingSymlinksInPath() else {
            throw PolarisError.invalid("Não gere a prévia no mesmo diretório do config.plist original.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PolarisError.invalid("A pasta de saída não existe.")
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
