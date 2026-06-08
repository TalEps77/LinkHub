import Foundation

enum WiFiSecurity: Equatable, Sendable {
    case none
    case wpa2Personal
    case wpa3Personal
    case enterprise
    case other
}
