import Foundation
import MultipeerConnectivity
import UIKit

class FileSharingService: NSObject {
    static let shared = FileSharingService()
    
    private let serviceType = "filedrop"
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    var connectedPeers: [MCPeerID] = []
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?
    var onFileReceived: ((URL, MCPeerID) -> Void)?
    var onError: ((Error) -> Void)?
    
    private override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser?.delegate = self
    }
    
    func startAdvertising() {
        advertiser?.startAdvertisingPeer()
    }
    
    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
    }
    
    func startBrowsing() {
        browser?.startBrowsingForPeers()
    }
    
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
    }
    
    func sendFile(_ fileURL: URL, to peer: MCPeerID, completion: @escaping (Error?) -> Void) {
        guard let session = session else {
            let error = NSError(domain: "FileDrop", code: -1, userInfo: [NSLocalizedDescriptionKey: "Session not initialized"])
            completion(error)
            return
        }
        
        guard session.connectedPeers.contains(peer) else {
            let error = NSError(domain: "FileDrop", code: -2, userInfo: [NSLocalizedDescriptionKey: "Peer not connected"])
            completion(error)
            return
        }
        
        session.sendResource(at: fileURL, withName: fileURL.lastPathComponent, toPeer: peer) { error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(error)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

extension FileSharingService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                self?.connectedPeers.append(peerID)
                self?.onPeerConnected?(peerID)
            case .notConnected:
                self?.connectedPeers.removeAll { $0 == peerID }
                self?.onPeerDisconnected?(peerID)
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle data if needed
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle stream if needed
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Handle resource start
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                self?.onError?(error)
            } else if let localURL = localURL {
                self?.onFileReceived?(localURL, peerID)
            }
        }
    }
}

extension FileSharingService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }
}

extension FileSharingService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let session = session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Peer disconnected naturally
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }
} 