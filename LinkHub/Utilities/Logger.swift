import Foundation
import os

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.linkhub.app"
    static let app = os.Logger(subsystem: subsystem, category: "app")
    static let menuBar = os.Logger(subsystem: subsystem, category: "menuBar")
    static let networkWiFi = os.Logger(subsystem: subsystem, category: "network.wifi")
    static let networkEthernet = os.Logger(subsystem: subsystem, category: "network.ethernet")
    static let servicesKeychain = os.Logger(subsystem: subsystem, category: "services.keychain")
    // Future categories: state, services.settings
}
