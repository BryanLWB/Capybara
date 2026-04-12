import NetworkExtension

// MARK: - ⚠️ IMPORTANT SETUP INSTRUCTIONS
// 1. Open project in Xcode (`ios/Runner.xcworkspace`)
// 2. File -> New -> Target -> Network Extension
// 3. Product Name: "PacketTunnel" (Language: Swift)
// 4. Finish. If asked to activate scheme, say "Cancel" or "Activate" (doesn't matter much).
// 5. Replace the content of the generated `PacketTunnelProvider.swift` (in the PacketTunnel folder) with this code.
// 6. ⚠️ You MUST link your V2Core framework (e.g. LibXray.xcframework) to the PacketTunnel Target in "Frameworks and Libraries".
// 7. Enable "App Groups" capability for both Runner and PacketTunnel targets if you need to share files (optional for basic memory config).

class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // 1. Retrieve config from Provider Configuration
        guard let conf = self.protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = conf.providerConfiguration,
              let configStr = providerConfig["config"] as? String else {
            NSLog("[Capybara] Missing VPN configuration")
            completionHandler(NSError(domain: "app.capybara.client", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing config"]))
            return
        }
        
        // 2. Start V2Ray Core
        // Note: You need to import your V2Ray core library here (e.g. LibXray)
        /*
         LibXray.shared.start(config: configStr)
         */
        NSLog("[Capybara] Starting Tunnel with config length: \(configStr.count)")

        // 3. Configure Network Settings (Tun2Socks)
        // This sets up the virtual interface
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        let ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        // Route all traffic through the tunnel
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4Settings
        
        // DNS Settings
        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "1.1.1.1"])
        dnsSettings.matchDomains = [""] // Capture all DNS queries
        settings.dnsSettings = dnsSettings
        
        settings.mtu = 1500
        
        self.setTunnelNetworkSettings(settings) { error in
            if let error = error {
                NSLog("[Capybara] Failed to set settings: \(error)")
                completionHandler(error)
            } else {
                NSLog("[Capybara] Tunnel settings applied successfully")
                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Stop V2Ray Core
        /*
         LibXray.shared.stop()
         */
        NSLog("[Capybara] Stopping Tunnel")
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Use this to communicate with main app if needed
        completionHandler?(nil)
    }
}
