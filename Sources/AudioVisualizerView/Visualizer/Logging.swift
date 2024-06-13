import Foundation
import Logging
import AnyCodable

let domain = Domain(name: "AudioVisualizerView")
func verboseLog(_ message: String, meta: [String: AnyCodable] = [:]) {
    log.verbose(message, domain: domain, meta: meta)
}
func errorLog(_ message: String, meta: [String: AnyCodable] = [:]) {
    log.error(message, domain: domain, meta: meta)
}
func warnLog(_ message: String, meta: [String: AnyCodable] = [:]) {
    log.warn(message, domain: domain, meta: meta)
}
func debugLog(_ message: String, meta: [String: AnyCodable] = [:]) {
    log.debug(message, domain: domain, meta: meta)
}
func fatalLog(_ message: String, meta: [String: AnyCodable] = [:]) {
    log.fatal(message, domain: domain, meta: meta)
}

