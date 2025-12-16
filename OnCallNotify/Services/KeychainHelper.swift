//
//  KeychainHelper.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.oncall.notify"
    private let apiTokenKey = "api-token"

    private init() {}

    // MARK: - Save API Token

    func saveAPIToken(_ token: String) -> Bool {
        let data = Data(token.utf8)

        // First, try to delete any existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiTokenKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Now add the new item with stronger protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiTokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false // Explicitly prevent sync
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Get API Token

    func getAPIToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    // MARK: - Delete API Token

    func deleteAPIToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiTokenKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Check if API Token Exists

    func hasAPIToken() -> Bool {
        getAPIToken() != nil
    }
}
