import SwiftUI

struct PairingView: View {
    @ObservedObject var service: ConversationService

    @State private var inboundPairingCode = ""
    @State private var localPairingCode = ""
    @State private var hasLoadedPairingCode = false
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    VStack(spacing: 16) {
                        if localPairingCode.isEmpty {
                            ProgressView()
                                .frame(maxWidth: 260, minHeight: 260)
                        } else {
                            QRCodeImageView(payload: localPairingCode)
                                .frame(maxWidth: 260, maxHeight: 260)
                                .padding(12)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        Text("Dieser QR-Code enthält nur deine öffentlichen Identity Keys. Private Keys verlassen das Gerät nicht.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    ShareLink(item: localPairingCode) {
                        Label("Pairing-Code teilen", systemImage: "square.and.arrow.up")
                    }
                    .disabled(localPairingCode.isEmpty)

                    DisclosureGroup("Pairing-Code anzeigen") {
                        Text(localPairingCode.isEmpty ? "Pairing-Code konnte nicht geladen werden." : localPairingCode)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                    }

                    Button("Pairing-Code neu laden") {
                        refreshLocalPairingCode()
                    }
                } header: {
                    Text("Mein Pairing")
                }

                SwiftUI.Section {
                    TextEditor(text: $inboundPairingCode)
                        .frame(minHeight: 96)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    HStack {
                        Button {
                            showScanner = true
                        } label: {
                            Label("QR scannen", systemImage: "qrcode.viewfinder")
                        }

                        Spacer()

                        Button("Importieren") {
                            importInboundPairingCode()
                        }
                        .disabled(inboundPairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Kontakt importieren")
                } footer: {
                    Text("Nach dem Import muss die Safety Number über einen zweiten Kanal verglichen werden. Erst danach Nachrichtenversand erlauben.")
                }

                SwiftUI.Section {
                    if service.trustedPeers.isEmpty {
                        Text("Noch keine Kontakte importiert.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(service.trustedPeers) { peer in
                            PeerTrustRow(service: service, peer: peer)
                        }
                    }
                } header: {
                    Text("Vertrauensstatus")
                }
            }
            .navigationTitle("Pairing")
            .privateChatErrorAlert(service: service)
            .onAppear {
                guard hasLoadedPairingCode == false else {
                    return
                }
                hasLoadedPairingCode = true
                refreshLocalPairingCode()
            }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { scannedCode in
                        handleScannedPairingCode(scannedCode)
                    }
                    .navigationTitle("QR scannen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { showScanner = false }
                        }
                    }
                }
            }
        }
    }

    private func refreshLocalPairingCode() {
        do {
            localPairingCode = try service.makeLocalPairingCode()
        } catch {
            localPairingCode = ""
            service.reportError(error)
        }
    }

    private func importInboundPairingCode() {
        let normalizedCode = inboundPairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCode.isEmpty == false else {
            return
        }
        service.importPeer(from: normalizedCode)
        inboundPairingCode = ""
    }

    private func handleScannedPairingCode(_ scannedCode: String) {
        let normalizedCode = scannedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCode.isEmpty == false else {
            return
        }
        inboundPairingCode = normalizedCode
        showScanner = false
        Task { @MainActor in
            service.importPeer(from: normalizedCode)
        }
    }
}

private struct PeerTrustRow: View {
    @ObservedObject var service: ConversationService
    let peer: TrustedPeer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.headline)
                    Text(peer.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                TrustBadge(state: peer.trustState)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Safety Number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(peer.safetyNumber)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            if let lastVerifiedAt = peer.lastVerifiedAt {
                Text("Verifiziert: \(lastVerifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if peer.trustState == .verified {
                    Button("Verifizierung zurücknehmen") {
                        service.unblockPeerAsUnverified(id: peer.id)
                    }
                    .buttonStyle(.bordered)
                } else if peer.trustState == .blocked {
                    Button("Entsperren") {
                        service.unblockPeerAsUnverified(id: peer.id)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Verifizieren") {
                        service.verifyPeer(id: peer.id)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                Button(role: .destructive) {
                    service.blockPeer(id: peer.id)
                } label: {
                    Text("Blockieren")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct TrustBadge: View {
    let state: TrustState

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var title: String {
        switch state {
        case .unverified:
            return "Unverified"
        case .verified:
            return "Verified"
        case .blocked:
            return "Blocked"
        }
    }

    private var icon: String {
        switch state {
        case .unverified:
            return "exclamationmark.triangle"
        case .verified:
            return "checkmark.shield"
        case .blocked:
            return "nosign"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .unverified:
            return Color.orange.opacity(0.16)
        case .verified:
            return Color.green.opacity(0.16)
        case .blocked:
            return Color.red.opacity(0.16)
        }
    }
}
