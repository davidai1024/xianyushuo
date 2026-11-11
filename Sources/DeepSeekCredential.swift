import Foundation
import Security

enum DeepSeekCredential {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "im.muse.dianyu.cleanup.deepseek",
         kSecAttrAccount as String: "api-key"]
    }

    static func read() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw AppError.message("钥匙串中的 DeepSeek API Key 无法读取。")
        }
        return key
    }

    static func save(_ input: String) throws {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.range(of: #"^[A-Za-z0-9_-]{1,256}$"#, options: .regularExpression) != nil else {
            throw AppError.message("请输入有效的 DeepSeek API Key。")
        }
        let secret = Data(key.utf8)
        let attributes = [kSecValueData as String: secret]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = secret
            try check(SecItemAdd(entry as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw AppError.message("无法访问 DeepSeek 钥匙串项目（\(status)）。")
        }
    }
}
