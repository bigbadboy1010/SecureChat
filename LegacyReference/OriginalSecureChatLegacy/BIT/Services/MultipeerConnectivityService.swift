import Foundation
import Combine
import MultipeerConnectivity
#if os(iOS)
import UIKit
#endif

final class MultipeerConnectivityService: NSObject, ObservableObject {
    @MainActor @Published private(set) var connectedPeers: [String] = []
    private let serviceType = "bit-mesh"
    private let myPeerId = MCPeerID(displayName: MultipeerConnectivityService.defaultDisplayName)
    private static var defaultDisplayName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "schat-node"
        #endif
    }
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser

    @MainActor override init() {
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        // Update @Published properties from delegate callbacks as needed
        advertiser.startAdvertisingPeer()
    }
}

extension MultipeerConnectivityService: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {}
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
}
