import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: PolarisModel

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Polaris2048Fix")
                        .font(.title).bold()
                    Text("RX 580 2048SP · Preparador experimental OpenCore · v0.3")
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

            GroupBox("GPU detectada no macOS (somente leitura)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Detectar GPU AMD") { model.scanHardware() }
                        Spacer()
                    }
                    Text(model.hardwareStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.hardware) { device in
                        Text(device.label)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Text("A detecção pelo IORegistry não fornece automaticamente o caminho DeviceProperties do OpenCore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Caminho PCI na EFI de testes") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Entradas já cadastradas")
                        Spacer()
                        Picker("", selection: $model.selectedPCIPath) {
                            Text("Informar manualmente").tag("")
                            ForEach(model.candidates) { entry in
                                Text("\(entry.description) · \(entry.path)").tag(entry.path)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 330)
                    }
                    TextField("PciRoot(0x0)/Pci(0x3,0x0)/Pci(0x0,0x0)", text: $model.selectedPCIPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                    Text("Digite o caminho PCI real se a entrada ainda não existir no plist. O exemplo acima NÃO deve ser copiado sem verificar sua EFI atual.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Segurança do experimento") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A prévia adiciona ATY,bin_image (64 KiB) e device-id DF670000 ao arquivo gerado. Não altera outros dados propositalmente. Isso NÃO garante Metal.")
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Verifiquei o caminho PCI na minha instalação atual e só aplicarei a prévia em EFI USB de testes, após ocvalidate.", isOn: $model.userConfirmed)
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
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.scanHardware() }
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
