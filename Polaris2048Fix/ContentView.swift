import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: PolarisModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Polaris2048Fix")
                        .font(.title).bold()
                    Text("RX 580 2048SP · Preparador experimental OpenCore · v0.2")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("PRÉVIA OFFLINE")
                    .font(.caption).monospaced().bold()
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            GroupBox("Arquivos") {
                VStack(alignment: .leading, spacing: 12) {
                    fileRow("1. Configuração OpenCore", file: model.configURL, action: model.chooseConfig)
                    fileRow("2. Sua RX580 Mod.rom", file: model.romURL, action: model.chooseROM)
                    fileRow("3. Pasta local para gerar prévia", file: model.destinationURL, action: model.chooseDestination)
                }
                .padding(8)
            }

            GroupBox("Identificação da GPU") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Entrada PCI no config.plist")
                        Spacer()
                        Picker("", selection: $model.selectedPCIPath) {
                            Text("Selecione uma GPU").tag("")
                            ForEach(model.candidates) { entry in
                                Text("\(entry.description) · \(entry.path)").tag(entry.path)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 390)
                    }
                    Text(model.selectedPCIPath.isEmpty ? "Selecione o caminho correto para a placa RX 580." : model.selectedPCIPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("O caminho é extraído do plist. O app NÃO confirma automaticamente se esse caminho corresponde ao PCI atual do Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Segurança do experimento") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A prévia adiciona ATY,bin_image (64 KiB) e device-id DF670000 ao arquivo gerado. Não altera outros dados propositalmente. Isso NÃO garante Metal.")
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Confirmei o caminho PCI e vou usar a prévia apenas em uma EFI USB de testes, após validar com ocvalidate.", isOn: $model.userConfirmed)
                        .toggleStyle(.checkbox)
                }
                .padding(8)
            }

            HStack {
                Button("Gerar prévia e backup") { model.prepare() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canPrepare)
                Button("Abrir resultado") { model.openResultFolder() }
                    .disabled(model.resultURL == nil)
                Spacer()
                Label("Sem root · Sem instalação · Sem flash", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Text(model.status)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 0)
        }
        .padding(22)
    }

    private func fileRow(_ title: String, file: URL?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 220, alignment: .leading)
            Text(file?.path ?? "Nenhum arquivo selecionado")
                .font(.caption.monospaced())
                .foregroundStyle(file == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(file?.path ?? "")
            Button("Selecionar…", action: action)
        }
    }
}
