//
//  SettingsView.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import SwiftUI

struct SettingsView: View {
    @State private var apiToken: String = ""
    @State private var hasStoredToken: Bool = false
    @State private var isSaved: Bool = false
    @State private var isEditingToken: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: Bool?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("API Token (PagerDuty)")
                            .font(.headline)

                        if hasStoredToken, !isEditingToken {
                            HStack {
                                Text("••••••••••••••••")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Change") {
                                    isEditingToken = true
                                    apiToken = ""
                                    isSaved = false
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        } else {
                            SecureField("Enter your API token", text: $apiToken)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: apiToken) { _ in
                                    isSaved = false
                                    connectionTestResult = nil
                                    isEditingToken = true
                                }
                        }

                        Text(
                            "Create an API token in your PagerDuty account under User Settings → " +
                                "API Access Keys. Future versions will support additional on-call services."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("API Configuration")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button(action: saveToken) {
                                Label("Save Token", systemImage: "checkmark.circle")
                            }
                            .disabled(apiToken.isEmpty)

                            if isSaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Saved")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }

                        HStack {
                            Button(action: testConnection) {
                                Label("Test Connection", systemImage: "network")
                            }
                            .disabled(!isSaved || isTestingConnection)

                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }

                            if let result = connectionTestResult {
                                Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result ? .green : .red)
                                Text(result ? "Connected" : "Failed")
                                    .font(.caption)
                                    .foregroundColor(result ? .green : .red)
                            }
                        }

                        Button(action: loadToken) {
                            Label("Load Saved Token", systemImage: "key")
                        }

                        Button(role: .destructive, action: deleteToken) {
                            Label("Delete Token", systemImage: "trash")
                        }
                        .disabled(!KeychainHelper.shared.hasAPIToken())
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Actions")
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
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Information")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 500, minHeight: 400)

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
        .onAppear {
            loadToken()
        }
    }

    // MARK: - Validation

    private func validateAPIToken(_ token: String) -> (isValid: Bool, message: String?) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check minimum length
        guard trimmed.count >= 20 else {
            return (false, "API token must be at least 20 characters")
        }

        // Check maximum length (reasonable upper bound)
        guard trimmed.count <= 100 else {
            return (false, "API token appears to be invalid (too long)")
        }

        // Check for valid characters (alphanumeric, hyphens, underscores)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard trimmed.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return (false, "API token contains invalid characters")
        }

        // Check it's not the masked placeholder
        guard !trimmed.allSatisfy({ $0 == "•" }) else {
            return (false, "Please enter your actual API token")
        }

        return (true, nil)
    }

    // MARK: - Actions

    private func saveToken() {
        let trimmed = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return }

        // Validate token format
        let validation = validateAPIToken(trimmed)
        guard validation.isValid else {
            showError = true
            errorMessage = validation.message ?? "Invalid API token format"
            return
        }

        let success = KeychainHelper.shared.saveAPIToken(trimmed)

        if success {
            isSaved = true
            hasStoredToken = true
            isEditingToken = false
            connectionTestResult = nil
            // Clear the actual token from memory
            apiToken = "••••••••••••••••"
            // Trigger a refresh of data
            OnCallService.shared.refreshData()
        } else {
            showError = true
            errorMessage = "Failed to save API token to Keychain"
        }
    }

    private func loadToken() {
        hasStoredToken = KeychainHelper.shared.hasAPIToken()

        if hasStoredToken {
            // Only show a masked placeholder, never load the actual token
            apiToken = "••••••••••••••••"
            isSaved = true
            isEditingToken = false
        } else {
            apiToken = ""
            isSaved = false
            isEditingToken = false
        }
    }

    private func deleteToken() {
        let success = KeychainHelper.shared.deleteAPIToken()

        if success {
            apiToken = ""
            isSaved = false
            hasStoredToken = false
            isEditingToken = false
            connectionTestResult = nil
            // Clear service data
            OnCallService.shared.alertSummary = AlertSummary()
        } else {
            showError = true
            errorMessage = "Failed to delete API token from Keychain"
        }
    }

    func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        Task {
            let result = await OnCallService.shared.testConnection()

            await MainActor.run {
                isTestingConnection = false
                connectionTestResult = result

                if !result {
                    showError = true
                    if let error = OnCallService.shared.lastError {
                        errorMessage = error.localizedDescription
                    } else {
                        errorMessage = "Failed to connect to API"
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
