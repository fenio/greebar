import CommonCrypto
import CryptoKit
import Foundation

/// Gree units encrypt the inner "pack" payload with AES-128.
/// Older firmware uses ECB, newer (roughly v1.21+) uses GCM with a fixed nonce and AAD.
enum GreeCrypto {
    static let genericECBKey = "a3K8Bx%2r8Y7#xDh"
    static let genericGCMKey = "{yxAHAY_Lm6pbC/<"
    private static let gcmNonce = Data([0x54, 0x40, 0x78, 0x44, 0x49, 0x67, 0x5a, 0x51, 0x6c, 0x5e, 0x63, 0x13])
    private static let gcmAAD = Data("qualcomm-test".utf8)

    // MARK: ECB

    static func ecbEncrypt(_ plain: Data, key: String) throws -> String {
        try aesECB(CCOperation(kCCEncrypt), plain, key: key, padding: true).base64EncodedString()
    }

    static func ecbDecrypt(_ base64: String, key: String) throws -> Data {
        guard let cipher = Data(base64Encoded: base64) else { throw GreeError.crypto }
        // Devices don't always pad correctly, so decrypt raw and trim to the closing brace.
        let raw = try aesECB(CCOperation(kCCDecrypt), cipher, key: key, padding: false)
        guard let end = raw.lastIndex(of: UInt8(ascii: "}")) else { throw GreeError.crypto }
        return raw[...end]
    }

    private static func aesECB(_ op: CCOperation, _ input: Data, key: String, padding: Bool) throws -> Data {
        let keyData = Data(key.utf8)
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var outLength = 0
        let options = CCOptions(kCCOptionECBMode | (padding ? kCCOptionPKCS7Padding : 0))
        let status = output.withUnsafeMutableBytes { outBuf in
            input.withUnsafeBytes { inBuf in
                keyData.withUnsafeBytes { keyBuf in
                    CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), options,
                            keyBuf.baseAddress, keyData.count, nil,
                            inBuf.baseAddress, input.count,
                            outBuf.baseAddress, outBuf.count, &outLength)
                }
            }
        }
        guard status == kCCSuccess else { throw GreeError.crypto }
        return output.prefix(outLength)
    }

    // MARK: GCM

    static func gcmEncrypt(_ plain: Data, key: String) throws -> (pack: String, tag: String) {
        let sealed = try AES.GCM.seal(plain, using: SymmetricKey(data: Data(key.utf8)),
                                      nonce: AES.GCM.Nonce(data: gcmNonce), authenticating: gcmAAD)
        return (sealed.ciphertext.base64EncodedString(), sealed.tag.base64EncodedString())
    }

    static func gcmDecrypt(pack: String, tag: String, key: String) throws -> Data {
        guard let cipher = Data(base64Encoded: pack), let tagData = Data(base64Encoded: tag) else {
            throw GreeError.crypto
        }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: gcmNonce), ciphertext: cipher, tag: tagData)
        return try AES.GCM.open(box, using: SymmetricKey(data: Data(key.utf8)), authenticating: gcmAAD)
    }
}
