import Foundation
import Testing

// Accepts the usual swift-testing arguments, e.g. `--filter MetadataParsingTests`.
let status: CInt = await __swiftPMEntryPoint()
exit(status)
