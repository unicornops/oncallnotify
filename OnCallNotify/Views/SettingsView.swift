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
    @State private var accountToEdit: Account?
    @State private var showError = false
    @State private var errorMessage = ""

    private var demoAccounts: [Account] {
        accounts.filter { $0.isDemoAccount }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                demoModeSection
                accountsSection
                informationSection
            }
            .formStyle(.grouped)
            .frame(minWidth: 640, minHeight: 440)

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
            AddAccountView(
                onSave: { account, token in
                    addAccount(account, token: token)
                    showingAddAccount = false
                },
                onCancel: {
                    showingAddAccount = false
                }
            )
        }
        .sheet(item: $accountToEdit) { account in
            EditAccountView(
                account: account,
                onSave: { updatedAccount, newToken in
                    updateAccount(updatedAccount, newToken: newToken)
                    accountToEdit = nil
                },
                onCancel: {
                    accountToEdit = nil
                }
            )
        }
        .onAppear {
            loadAccounts()
        }
    }

    private var demoModeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Review-Friendly Demo Mode", systemImage: "play.square.fill")
                    .font(.headline)

                Text(
                    "Demo Mode runs entirely offline with local sample incidents, on-call state, " +
                        "and acknowledge actions. It is intended for App Store review " +
                        "and for anyone evaluating the app without a paid PagerDuty account."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if demoAccounts.isEmpty {
                    Button {
                        addDemoAccount()
                    } label: {
                        Label("Add Demo Account", systemImage: "plus.circle.fill")
                    }
                } else {
                    ForEach(demoAccounts) { account in
                        DemoAccountControlsView(account: account)
                    }
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Demo Mode")
        }
    }

    private var accountsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if accounts.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("No accounts configured. Add a PagerDuty account or create a Demo account to get started.")
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

                Button {
                    showingAddAccount = true
                } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Accounts")
        }
    }

    private var informationSection: some View {
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
                    Text("Keychain + UserDefaults")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Active Accounts:")
                    Spacer()
                    Text("\(accounts.filter { $0.isEnabled }.count) of \(accounts.count)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("App Review Access:")
                    Spacer()
                    Text(demoAccounts.isEmpty ? "Add Demo Mode" : "Ready")
                        .foregroundColor(demoAccounts.isEmpty ? .orange : .green)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Information")
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

    private func addDemoAccount() {
        let demoAccount = Account(name: "Demo Workspace", serviceType: .demo, isEnabled: true)
        addAccount(demoAccount, token: "")
    }

    private func editAccount(_ account: Account) {
        accountToEdit = account
    }

    private func updateAccount(_ account: Account, newToken: String?) {
        var success = KeychainHelper.shared.updateAccount(account)

        if success,
           account.requiresAPIToken,
           let newToken,
           !newToken.isEmpty {
            success = KeychainHelper.shared.updateAPIToken(for: account.id, token: newToken)
        }

        if success {
            loadAccounts()
            OnCallService.shared.reloadAccounts()
        } else {
            showError = true
            errorMessage = "Failed to update account"
        }
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

// MARK: - Demo Controls

struct DemoAccountControlsView: View {
    let account: Account
    @ObservedObject private var service = OnCallService.shared

    private var scenarioBinding: Binding<DemoScenario> {
        Binding(
            get: {
                service.demoConfiguration(for: account.id)?.selectedScenario ?? .reviewOverview
            },
            set: { scenario in
                service.setDemoScenario(scenario, for: account.id)
            }
        )
    }

    private var selectedScenario: DemoScenario {
        service.demoConfiguration(for: account.id)?.selectedScenario ?? .reviewOverview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.headline)
                    Text("No sign-in required. All demo actions stay local on this Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    service.resetDemoScenario(for: account.id)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    service.advanceDemoScenario(for: account.id)
                } label: {
                    Label("Next Scenario", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            Picker("Demo Scenario", selection: scenarioBinding) {
                ForEach(DemoScenario.allCases) { scenario in
                    Text(scenario.displayName).tag(scenario)
                }
            }
            .pickerStyle(.menu)

            Text(selectedScenario.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.06))
        )
    }
}

// MARK: - Account Row View

struct AccountRowView: View {
    let account: Account
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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

                if account.isDemoAccount {
                    Text("Offline sample data for App Review and evaluation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !account.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Button(action: testConnection) {
                if isTestingConnection {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let result = connectionTestResult {
                    Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result ? .green : .red)
                } else {
                    Image(systemName: account.isDemoAccount ? "play.circle" : "network")
                }
            }
            .buttonStyle(.plain)
            .disabled(isTestingConnection || !account.isEnabled)
            .help(account.isDemoAccount ? "Validate Demo Mode" : "Test Connection")

            Button(action: onToggle) {
                Image(systemName: account.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(account.isEnabled ? .green : .gray)
            }
            .buttonStyle(.plain)
            .help(account.isEnabled ? "Disable Account" : "Enable Account")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("Edit Account")

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
        case .demo:
            "play.square.fill"
        case .pagerDuty:
            "bell.fill"
        }
    }

    func testConnection() {
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

    @State private var accountName = ""
    @State private var serviceType: ServiceType = .demo
    @State private var apiToken = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add New Account")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section {
                    TextField("Account Name", text: $accountName)
                        .textFieldStyle(.roundedBorder)

                    Picker("Service Type", selection: $serviceType) {
                        ForEach(ServiceType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    if serviceType.requiresAPIToken {
                        SecureField("API Token", text: $apiToken)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield")
                                .foregroundColor(.green)
                            Text("Demo Mode does not require credentials.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

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

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Account") {
                    saveAccount()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || addButtonDisabled)
            }
            .padding()
        }
        .frame(width: 520, height: 400)
    }

    private var addButtonDisabled: Bool {
        serviceType.requiresAPIToken && apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var serviceInstructions: String {
        switch serviceType {
        case .demo:
            "Demo Mode creates local sample incidents and on-call data " +
                "so the full app can be explored without external sign-in."
        case .pagerDuty:
            "Create an API token in your PagerDuty account under User Settings → API Access Keys."
        }
    }

    private func saveAccount() {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            showError = true
            errorMessage = "Please enter an account name"
            return
        }

        if serviceType.requiresAPIToken {
            let validation = validateAPIToken(trimmedToken)
            guard validation.isValid else {
                showError = true
                errorMessage = validation.message ?? "Invalid API token"
                return
            }
        }

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

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_+"))
        guard trimmed.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return (false, "API token contains invalid characters")
        }

        return (true, nil)
    }
}

#Preview {
    SettingsView()
}
