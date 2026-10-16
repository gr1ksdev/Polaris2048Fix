import Foundation
import AppKit
import Combine
import CryptoKit

struct GPUEntry: Identifiable, Hashable {
    let path: String
    let description: String
    var id: String { path }
}

struct PreviewResult {
    let folder: URL
    let summary: String
}

enum PolarisError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let explanation): return explanation }
    }
}

@MainActor
final class PolarisModel: ObservableObject {
    @Published var configURL: URL?
    @Published var romURL: URL?
    @Published var destinationURL: URL?
    @Published var candidates: [GPUEntry] = []
    @Published var hardware: [DetectedAMDDevice] = []
    @Published var hardwareStatus = "Verificação de dispositivos AMD ainda não executada."
    @Published var selectedPCIPath = ""
    @Published var status = "Selecione o config.plist da sua EFI de testes. Nada será instalado automaticamente."
    @Published var resultURL: URL?
    @Published var userConfirmed = false
    @Published var busy = false

    private let preparer = PolarisPreparer()

    func chooseConfig() {
        let dialog = NSOpenPanel()
        dialog.title = "Selecione o config.plist do OpenCore"
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = false
        dialog.prompt = "Selecionar"
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        configURL = url
        resultURL = nil
        userConfirmed = false
        do {
            candidates = try preparer.listGPUEntries(configURL: url)
            selectedPCIPath = candidates.count == 1 ? candidates[0].path : ""
            if candidates.isEmpty {
                status = "Sem entradas de GPU no config.plist. Isso NÃO significa que a placa esteja ausente. Você pode informar manualmente o caminho PCI correto."
            } else {
                status = "Encontrei \(candidates.count) entrada(s) de GPU no plist. Confirme o caminho PCI real antes de preparar."
            }
        } catch {
            candidates = []
            selectedPCIPath = ""
            status = "Erro ao ler config.plist: \(error.localizedDescription)"
        }
    }

    func scanHardware() {
        do {
            hardware = try HardwareDetector.scanAMD()
            hardwareStatus = hardware.isEmpty
                ? "Nenhum dispositivo AMD encontrado pelo ioreg. Isso não confirma ausência de GPU; veja o IORegistry."
                : "Encontrado(s) \(hardware.count) dispositivo(s) AMD no IORegistry. A identificação pode refletir spoof do OpenCore."
        } catch {
            hardware = []
            hardwareStatus = "Falha ao consultar ioreg: \(error.localizedDescription)"
        }
    }

    func chooseROM() {
        let dialog = NSOpenPanel()
        dialog.title = "Selecione sua RX580 Mod.rom (256 KiB)"
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = false
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        romURL = url
        resultURL = nil
        do {
            let description = try preparer.inspectROM(url)
            status = "ROM reconhecida: \(description). Nenhum arquivo do sistema foi alterado."
        } catch {
            status = "ROM recusada: \(error.localizedDescription)"
        }
    }

    func chooseDestination() {
        let dialog = NSOpenPanel()
        dialog.title = "Selecione uma pasta local para a prévia (ex.: Documentos)"
        dialog.canChooseFiles = false
        dialog.canChooseDirectories = true
        dialog.canCreateDirectories = true
        dialog.allowsMultipleSelection = false
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        destinationURL = url
        resultURL = nil
        status = "Pasta de saída selecionada. O app recusará destinos dentro de EFI/Volumes."
    }

    var canPrepare: Bool {
        configURL != nil && romURL != nil && destinationURL != nil
        && !selectedPCIPath.isEmpty && userConfirmed && !busy
    }

    func prepare() {
        guard let configURL, let romURL, let destinationURL, canPrepare else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try preparer.prepare(
                configURL: configURL,
                romURL: romURL,
                outputParent: destinationURL,
                pciPath: selectedPCIPath
            )
            resultURL = result.folder
            status = result.summary
        } catch {
            status = "Não foi possível gerar a prévia: \(error.localizedDescription)"
        }
    }

    func openResultFolder() {
        guard let resultURL else { return }
        NSWorkspace.shared.open(resultURL)
    }
}
