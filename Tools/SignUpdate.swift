import Foundation
import CryptoKit
// Private key is read only from the explicitly supplied local path. It is never printed.
let key=try Curve25519.Signing.PrivateKey(rawRepresentation:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
let archive=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]),options:.mappedIfSafe)
let signature=try key.signature(for:archive)
guard key.publicKey.isValidSignature(signature,for:archive)else{fatalError("Signature verification failed")}
print(signature.base64EncodedString())
