import Foundation
import Network
import Combine

class FileTransferService: ObservableObject {
    @Published var discoveredDevices: [Device] = []
    @Published var transferProgress: Double = 0.0
    @Published var isTransferring: Bool = false
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var browser: NWBrowser?
    
    struct Device: Identifiable {
        let id = UUID()
        let name: String
        let endpoint: NWEndpoint
    }
    
    init() {
        setupNetworkListener()
        startBrowsing()
    }
    
    private func setupNetworkListener() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        
        do {
            listener = try NWListener(using: parameters)
            listener?.service = NWListener.Service(name: "FileDrop", type: "_filedrop._tcp")
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Listener ready")
                case .failed(let error):
                    print("Listener failed with error: \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: .main)
        } catch {
            print("Failed to create listener: \(error)")
        }
    }
    
    private func startBrowsing() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        
        browser = NWBrowser(for: .bonjour(type: "_filedrop._tcp", domain: nil), using: parameters)
        
        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Browser ready")
            case .failed(let error):
                print("Browser failed with error: \(error)")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            self?.updateDiscoveredDevices(results)
        }
        
        browser?.start(queue: .main)
    }
    
    private func updateDiscoveredDevices(_ results: Set<NWBrowser.Result>) {
        discoveredDevices = results.compactMap { result in
            guard let name = result.endpoint.name else { return nil }
            return Device(name: name, endpoint: result.endpoint)
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Connection ready")
            case .failed(let error):
                print("Connection failed with error: \(error)")
            default:
                break
            }
        }
        
        connection.start(queue: .main)
        connections.append(connection)
    }
    
    func sendFile(_ fileURL: URL, to device: Device) {
        guard let connection = connections.first(where: { $0.endpoint == device.endpoint }) else {
            print("No connection found for device")
            return
        }
        
        isTransferring = true
        transferProgress = 0.0
        
        do {
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            let fileSize = fileData.count
            
            // Send file metadata first
            let metadata = FileMetadata(name: fileName, size: fileSize)
            let metadataData = try JSONEncoder().encode(metadata)
            
            connection.send(content: metadataData, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("Error sending metadata: \(error)")
                    self?.isTransferring = false
                    return
                }
                
                // Send file data in chunks
                let chunkSize = 1024 * 1024 // 1MB chunks
                var offset = 0
                
                while offset < fileData.count {
                    let chunk = fileData.subdata(in: offset..<min(offset + chunkSize, fileData.count))
                    connection.send(content: chunk, completion: .contentProcessed { error in
                        if let error = error {
                            print("Error sending chunk: \(error)")
                            self?.isTransferring = false
                            return
                        }
                        
                        offset += chunk.count
                        self?.transferProgress = Double(offset) / Double(fileSize)
                        
                        if offset >= fileData.count {
                            self?.isTransferring = false
                            self?.transferProgress = 1.0
                        }
                    })
                }
            })
        } catch {
            print("Error preparing file for transfer: \(error)")
            isTransferring = false
        }
    }
}

struct FileMetadata: Codable {
    let name: String
    let size: Int
} 