//
//  EditAccountView.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import SwiftUI

struct EditAccountView: View {
    let account: Account
    let onSave: (Account, String?) -> Void
    let onCancel: () -> Void

    @State private var accountName: String = ""
    @State private var apiToken = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Account")
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

                    HStack {
                        Text("Service Type:")
                        Spacer()
                        Text(account.serviceType.displayName)
                            .foregroundColor(.secondary)
                    }

                    if account.requiresAPIToken {
                        SecureField("New API Token (leave blank to keep current)", text: $apiToken)
                            .textFieldStyle(.roundedBorder)
                    }
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

                Button("Save") {
                    saveAccount()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 350)
        .onAppear {
            accountName = account.name
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

        if account.requiresAPIToken, !trimmedToken.isEmpty {
            let validation = validateAPIToken(trimmedToken)
            guard validation.isValid else {
                showError = true
                errorMessage = validation.message ?? "Invalid API token"
                return
            }
        }

        var updatedAccount = account
        updatedAccount.name = trimmedName

        let tokenToSave: String? = trimmedToken.isEmpty ? nil : trimmedToken
        onSave(updatedAccount, tokenToSave)
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
