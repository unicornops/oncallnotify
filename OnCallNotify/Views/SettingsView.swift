//
//  SettingsView.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import SwiftUI

struct SettingsView: View {
    @State private var accounts: [Account] = []
    @State private var showingAddAccount = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if accounts.isEmpty {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("No accounts configured. Add an account to get started.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            ForEach(accounts) { account in
                                AccountRowView(
                                    account: account,
                                    onEdit: { editAccount(account) },
                                    onDelete: { deleteAccount(account) },
                                    onToggle: { toggleAccount(account) }
                                )
                            }
                        }

                        Button(action: {
                            showingAddAccount = true
                        }) {
                            Label("Add Account", systemImage: "plus.circle")
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Accounts")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Auto-refresh:")
                            Spacer()
                            Text("Every 60 seconds")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Data Storage:")
                            Spacer()
                            Text("Keychain (Secure)")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Active Accounts:")
                            Spacer()
                            Text("\(accounts.filter { $0.isEnabled }.count) of \(accounts.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Information")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 600, minHeight: 400)

            if showError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        showError = false
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView(onSave: { account, token in
                addAccount(account, token: token)
                showingAddAccount = false
            }, onCancel: {
                showingAddAccount = false
            })
        }
        .onAppear {
            loadAccounts()
        }
    }

    // MARK: - Actions

    private func loadAccounts() {
        accounts = KeychainHelper.shared.getAccounts()
    }

    private func addAccount(_ account: Account, token: String) {
        let success = KeychainHelper.shared.addAccount(account, apiToken: token)

        if success {
            loadAccounts()
            OnCallService.shared.reloadAccounts()
        } else {
            showError = true
            errorMessage = "Failed to add account"
        }
    }

    private func editAccount(_ account: Account) {
        // For now, just allow toggling. Full edit will be added later if needed
        toggleAccount(account)
    }

    private func toggleAccount(_ account: Account) {
        var updatedAccount = account
        updatedAccount.isEnabled.toggle()

        let success = KeychainHelper.shared.updateAccount(updatedAccount)

        if success {
            loadAccounts()
            OnCallService.shared.reloadAccounts()
        } else {
            showError = true
            errorMessage = "Failed to update account"
        }
    }

    private func deleteAccount(_ account: Account) {
        let success = KeychainHelper.shared.deleteAccount(accountId: account.id)

        if success {
            loadAccounts()
            OnCallService.shared.reloadAccounts()
        } else {
            showError = true
            errorMessage = "Failed to delete account"
        }
    }
}

// MARK: - Account Row View

struct AccountRowView: View {
    let account: Account
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: Bool?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Service icon
            Image(systemName: serviceIcon)
                .font(.title2)
                .foregroundColor(account.isEnabled ? .blue : .gray)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                    .foregroundColor(account.isEnabled ? .primary : .secondary)

                Text(account.serviceType.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !account.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            // Test Connection button
            Button(action: testConnection) {
                if isTestingConnection {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let result = connectionTestResult {
                    Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result ? .green : .red)
                } else {
                    Image(systemName: "network")
                }
            }
            .buttonStyle(.plain)
            .disabled(isTestingConnection || !account.isEnabled)
            .help("Test Connection")

            // Toggle enabled
            Toggle("", isOn: .constant(account.isEnabled))
                .labelsHidden()
                .onChange(of: account.isEnabled) { _ in
                    onToggle()
                }
                .toggleStyle(SwitchToggleStyle())
                .help(account.isEnabled ? "Disable Account" : "Enable Account")

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Account")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var serviceIcon: String {
        switch account.serviceType {
        case .pagerDuty:
            "bell.fill"
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        Task {
            let result = await OnCallService.shared.testConnection(accountId: account.id)

            await MainActor.run {
                isTestingConnection = false
                connectionTestResult = result
            }
        }
    }
}

// MARK: - Add Account View

struct AddAccountView: View {
    let onSave: (Account, String) -> Void
    let onCancel: () -> Void

    @State private var accountName: String = ""
    @State private var serviceType: ServiceType = .pagerDuty
    @State private var apiToken: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add New Account")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            // Form
            Form {
                Section {
                    TextField("Account Name", text: $accountName)
                        .textFieldStyle(.roundedBorder)

                    Picker("Service Type", selection: $serviceType) {
                        ForEach(ServiceType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    SecureField("API Token", text: $apiToken)
                        .textFieldStyle(.roundedBorder)

                    Text(serviceInstructions)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Account Details")
                }
            }
            .formStyle(.grouped)
            .padding()

            if showError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Account") {
                    saveAccount()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountName.isEmpty || apiToken.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private var serviceInstructions: String {
        switch serviceType {
        case .pagerDuty:
            "Create an API token in your PagerDuty account under User Settings → API Access Keys."
        }
    }

    private func saveAccount() {
        // Validate inputs
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            showError = true
            errorMessage = "Please enter an account name"
            return
        }

        let validation = validateAPIToken(trimmedToken)
        guard validation.isValid else {
            showError = true
            errorMessage = validation.message ?? "Invalid API token"
            return
        }

        // Create account
        let account = Account(
            name: trimmedName,
            serviceType: serviceType,
            isEnabled: true
        )

        onSave(account, trimmedToken)
    }

    private func validateAPIToken(_ token: String) -> (isValid: Bool, message: String?) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 20 else {
            return (false, "API token must be at least 20 characters")
        }

        guard trimmed.count <= 100 else {
            return (false, "API token appears to be invalid (too long)")
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard trimmed.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return (false, "API token contains invalid characters")
        }

        return (true, nil)
    }
}

#Preview {
    SettingsView()
}
