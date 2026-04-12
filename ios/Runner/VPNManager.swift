import Foundation
import NetworkExtension
import Flutter

class VPNManager: NSObject {
    static let shared = VPNManager()
    
    // The Bundle ID of the Network Extension
    // User must create a Target named 'PacketTunnel'
    let extensionBundleId = Bundle.main.bundleIdentifier! + ".PacketTunnel"
    
    var manager: NETunnelProviderManager?
    var statusSink: FlutterEventSink?
    
    override init() {
        super.init()
        loadManager()
    }
    
    private func loadManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
            guard let self = self else { return }
            if let error = error {
                print("Error loading VPN managers: \(error)")
                return
            }
            
            if let managers = managers, !managers.isEmpty {
                self.manager = managers.first
            } else {
                self.manager = NETunnelProviderManager()
                self.manager?.localizedDescription = "Capybara VPN"
                
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = self.extensionBundleId
                proto.serverAddress = "Capybara"
                self.manager?.protocolConfiguration = proto
                
                self.manager?.saveToPreferences(completionHandler: { (error) in
                    if let error = error {
                        print("Error saving new manager: \(error)")
                    }
                })
            }
            
            // Listen for status changes
            NotificationCenter.default.addObserver(self, selector: #selector(self.statusDidChange(_:)), name: .NEVPNStatusDidChange, object: nil)
        }
    }
    
    func connect(config: String, result: @escaping FlutterResult) {
        guard let manager = self.manager else {
            loadManager()
            result(FlutterError(code: "MANAGER_NOT_READY", message: "VPN Manager not loaded yet", details: nil))
            return
        }
        
        manager.loadFromPreferences { [weak self] (error) in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
                return
            }
            
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.extensionBundleId
            proto.serverAddress = "Capybara"
            // Pass V2Ray config to extension
            proto.providerConfiguration = ["config": config]
            
            manager.protocolConfiguration = proto
            manager.isEnabled = true
            
            manager.saveToPreferences { (error) in
                if let error = error {
                    result(FlutterError(code: "SAVE_ERROR", message: error.localizedDescription, details: nil))
                    return
                }
                
                do {
                    try manager.connection.startVPNTunnel(options: [:])
                    result(true)
                } catch {
                    result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    func disconnect(result: @escaping FlutterResult) {
        manager?.connection.stopVPNTunnel()
        result(true)
    }
    
    func isConnected() -> Bool {
        return manager?.connection.status == .connected
    }
    
    @objc func statusDidChange(_ notification: Notification) {
        guard let connection = notification.object as? NEVPNConnection else { return }
        let status = connection.status
        let isConnected = (status == .connected)
        statusSink?(isConnected)
    }
}

class VPNStatusStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        VPNManager.shared.statusSink = events
        // Send initial status
        events(VPNManager.shared.isConnected())
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        VPNManager.shared.statusSink = nil
        return nil
    }
}
