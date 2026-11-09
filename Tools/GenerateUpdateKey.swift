import Foundation
import CryptoKit
let path=URL(fileURLWithPath:CommandLine.arguments[1])
guard !FileManager.default.fileExists(atPath:path.path) else {fatalError("Refusing to replace an existing update key")}
let key=Curve25519.Signing.PrivateKey()
try key.rawRepresentation.write(to:path,options:.atomic)
try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
print(key.publicKey.rawRepresentation.base64EncodedString())
