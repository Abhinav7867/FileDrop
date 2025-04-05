import UIKit
import MultipeerConnectivity

class MainViewController: UIViewController {
    private let fileSharingService = FileSharingService.shared
    private var connectedPeers: [MCPeerID] = []
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Looking for nearby devices..."
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(PeerCell.self, forCellReuseIdentifier: PeerCell.identifier)
        table.rowHeight = 70
        table.separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 0)
        return table
    }()
    
    private let shareButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Share Files", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 25
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.1
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFileSharingService()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "FileDrop"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        view.addSubview(tableView)
        view.addSubview(shareButton)
        view.addSubview(emptyStateLabel)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: shareButton.topAnchor, constant: -20),
            
            shareButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            shareButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            shareButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            shareButton.heightAnchor.constraint(equalToConstant: 50),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])
        
        tableView.dataSource = self
        tableView.delegate = self
        
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
    }
    
    private func setupFileSharingService() {
        fileSharingService.onPeerConnected = { [weak self] peer in
            DispatchQueue.main.async {
                self?.connectedPeers.append(peer)
                self?.updateUI()
            }
        }
        
        fileSharingService.onPeerDisconnected = { [weak self] peer in
            DispatchQueue.main.async {
                self?.connectedPeers.removeAll { $0 == peer }
                self?.updateUI()
            }
        }
        
        fileSharingService.onFileReceived = { [weak self] url, peer in
            DispatchQueue.main.async {
                self?.handleReceivedFile(url, from: peer)
            }
        }
        
        fileSharingService.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.showError(error)
            }
        }
        
        fileSharingService.startAdvertising()
        fileSharingService.startBrowsing()
    }
    
    private func updateUI() {
        tableView.reloadData()
        emptyStateLabel.isHidden = !connectedPeers.isEmpty
    }
    
    @objc private func shareButtonTapped() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
    
    private func handleReceivedFile(_ url: URL, from peer: MCPeerID) {
        let alert = UIAlertController(
            title: "File Received",
            message: "Received \(url.lastPathComponent) from \(peer.displayName)",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "View", style: .default) { [weak self] _ in
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self?.present(activityVC, animated: true)
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension MainViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return connectedPeers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PeerCell.identifier, for: indexPath) as! PeerCell
        let peer = connectedPeers[indexPath.row]
        cell.configure(with: peer.displayName)
        return cell
    }
}

extension MainViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedFileURL = urls.first else { return }
        
        let alert = UIAlertController(title: "Select Peer", message: "Choose a device to send to:", preferredStyle: .actionSheet)
        
        for peer in connectedPeers {
            alert.addAction(UIAlertAction(title: peer.displayName, style: .default) { [weak self] _ in
                let progressAlert = UIAlertController(
                    title: "Sending",
                    message: "Sending \(selectedFileURL.lastPathComponent) to \(peer.displayName)...",
                    preferredStyle: .alert
                )
                progressAlert.addAction(UIAlertAction(title: "OK", style: .cancel))
                self?.present(progressAlert, animated: true)
                
                self?.fileSharingService.sendFile(selectedFileURL, to: peer) { error in
                    DispatchQueue.main.async {
                        progressAlert.dismiss(animated: true)
                        if let error = error {
                            self?.showError(error)
                        }
                    }
                }
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = shareButton
            popoverController.sourceRect = shareButton.bounds
        }
        
        present(alert, animated: true)
    }
} 