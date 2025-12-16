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
    private let accountsKey = "accounts-list" // Stores list of account IDs
    private let legacyApiTokenKey = "api-token" // For migration from single account

    private init() {}

    // MARK: - Account Management

    /// Get all stored accounts
    func getAccounts() -> [Account] {
        guard let data = getKeychainData(account: accountsKey),
              let accounts = try? JSONDecoder().decode([Account].self, from: data) else {
            // Try to migrate legacy single-account setup
            return migrateLegacyAccount()
        }
        return accounts
    }

    /// Save accounts list
    private func saveAccounts(_ accounts: [Account]) -> Bool {
        guard let data = try? JSONEncoder().encode(accounts) else {
            return false
        }
        return saveKeychainData(data, account: accountsKey)
    }

    /// Add a new account
    func addAccount(_ account: Account, apiToken: String) -> Bool {
        var accounts = getAccounts()

        // Check if account already exists
        if accounts.contains(where: { $0.id == account.id }) {
            return false
        }

        // Save API token for this account
        guard saveAPIToken(apiToken, forAccountId: account.id) else {
            return false
        }

        // Add account to list
        accounts.append(account)
        return saveAccounts(accounts)
    }

    /// Update an existing account
    func updateAccount(_ account: Account) -> Bool {
        var accounts = getAccounts()

        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return false
        }

        accounts[index] = account
        return saveAccounts(accounts)
    }

    /// Delete an account
    func deleteAccount(accountId: String) -> Bool {
        var accounts = getAccounts()

        // Remove from list
        accounts.removeAll { $0.id == accountId }

        // Delete API token
        _ = deleteAPIToken(forAccountId: accountId)

        return saveAccounts(accounts)
    }

    // MARK: - API Token Management

    /// Save API token for a specific account
    func saveAPIToken(_ token: String, forAccountId accountId: String) -> Bool {
        let data = Data(token.utf8)
        let accountKey = "api-token-\(accountId)"

        // First, try to delete any existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Now add the new item with stronger protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false // Explicitly prevent sync
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Get API token for a specific account
    func getAPIToken(forAccountId accountId: String) -> String? {
        let accountKey = "api-token-\(accountId)"
        return getKeychainString(account: accountKey)
    }

    /// Delete API token for a specific account
    func deleteAPIToken(forAccountId accountId: String) -> Bool {
        let accountKey = "api-token-\(accountId)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Legacy Support (for backward compatibility)

    /// Save API token using legacy key (for backward compatibility)
    func saveAPIToken(_ token: String) -> Bool {
        saveAPIToken(token, forAccountId: "legacy")
    }

    /// Get API token using legacy key
    func getAPIToken() -> String? {
        // First try legacy key directly
        if let token = getKeychainString(account: legacyApiTokenKey) {
            return token
        }
        // Then try the migrated version
        return getAPIToken(forAccountId: "legacy")
    }

    /// Delete API token using legacy key
    func deleteAPIToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyApiTokenKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if legacy API token exists
    func hasAPIToken() -> Bool {
        getAPIToken() != nil
    }

    // MARK: - Migration

    /// Migrate from single-account to multi-account setup
    private func migrateLegacyAccount() -> [Account] {
        // Check if there's a legacy API token
        guard let legacyToken = getKeychainString(account: legacyApiTokenKey) else {
            return []
        }

        // Create a default account
        let defaultAccount = Account(
            id: "legacy",
            name: "PagerDuty Account",
            serviceType: .pagerDuty,
            isEnabled: true
        )

        // Save the token with the new key structure
        guard saveAPIToken(legacyToken, forAccountId: defaultAccount.id) else {
            return []
        }

        // Save the account
        guard saveAccounts([defaultAccount]) else {
            return []
        }

        // Delete the old legacy token entry
        _ = deleteAPIToken()

        return [defaultAccount]
    }

    // MARK: - Private Helpers

    private func saveKeychainData(_ data: Data, account: String) -> Bool {
        // First, try to delete any existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Now add the new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func getKeychainData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    private func getKeychainString(account: String) -> String? {
        guard let data = getKeychainData(account: account),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
