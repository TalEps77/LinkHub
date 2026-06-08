import Foundation
import os

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.linkhub.app"
    static let app = os.Logger(subsystem: subsystem, category: "app")
    static let menuBar = os.Logger(subsystem: subsystem, category: "menuBar")
    static let networkWiFi = os.Logger(subsystem: subsystem, category: "network.wifi")
    // Future categories: network.ethernet, state, services.keychain, services.settings
}
