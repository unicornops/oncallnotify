//
//  OnCallService.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation
import os.log

@MainActor
class OnCallService: ObservableObject {
    static let shared = OnCallService()

    @Published var alertSummary = AlertSummary()
    @Published var isLoading = false
    @Published var lastError: Error?

    private var accountServices: [String: ServiceProvider] = [:] // accountId -> service
    private var updateTimer: Timer?

    // Rate limiting and retry logic
    private var lastFetchTime: Date?
    private let minimumFetchInterval: TimeInterval = 5.0

    private init() {
        initializeAccountServices()
        startAutoUpdate()
    }

    deinit {
        updateTimer?.invalidate()
    }

    // MARK: - Account Management

    func initializeAccountServices() {
        let accounts = KeychainHelper.shared.getAccounts()

        // Remove services for accounts that no longer exist
        let accountIds = Set(accounts.map { $0.id })
        accountServices = accountServices.filter { accountIds.contains($0.key) }

        // Create or update services for each account
        for account in accounts where account.isEnabled {
            if accountServices[account.id] == nil {
                accountServices[account.id] = ServiceProviderFactory.createProvider(for: account)
            } else {
                accountServices[account.id]?.updateAccount(account)
            }
        }
    }

    func reloadAccounts() {
        initializeAccountServices()
        refreshData()
    }

    // MARK: - Auto Update

    func startAutoUpdate() {
        // Update immediately
        Task {
            await fetchAllData()
        }

        // Then update every 60 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchAllData()
            }
        }
    }

    func stopAutoUpdate() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Main Fetch Method

    func fetchAllData() async {
        // Check if we have any accounts
        guard !accountServices.isEmpty else {
            lastError = OnCallError.noAPIToken
            alertSummary = AlertSummary()
            return
        }

        isLoading = true
        lastError = nil

        // Fetch data from all account services
        await withTaskGroup(of: (String, AccountAlertSummary?, Error?).self) { group in
            for (accountId, service) in accountServices {
                group.addTask {
                    do {
                        let summary = try await service.fetchData()
                        return (accountId, summary, nil)
                    } catch {
                        return (accountId, nil, error)
                    }
                }
            }

            var accountSummaries: [String: AccountAlertSummary] = [:]
            var hasError = false
            var firstError: Error?

            for await (accountId, summary, error) in group {
                if let summary = summary {
                    accountSummaries[accountId] = summary
                } else if let error = error {
                    hasError = true
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            // Aggregate results
            aggregateResults(accountSummaries: accountSummaries)

            // Set error if any account failed
            if hasError, let error = firstError {
                lastError = error
            }
        }

        isLoading = false
    }

    private func aggregateResults(accountSummaries: [String: AccountAlertSummary]) {
        var summary = AlertSummary()
        summary.accountSummaries = accountSummaries

        // Aggregate totals across all accounts
        var allIncidents: [Incident] = []

        for (_, accountSummary) in accountSummaries {
            summary.totalAlerts += accountSummary.totalAlerts
            summary.acknowledgedCount += accountSummary.acknowledgedCount
            summary.unacknowledgedCount += accountSummary.unacknowledgedCount
            summary.isOnCall = summary.isOnCall || accountSummary.isOnCall
            allIncidents.append(contentsOf: accountSummary.incidents)
        }

        // Sort incidents by creation time (most recent first)
        allIncidents.sort { incident1, incident2 in
            let formatter = ISO8601DateFormatter()
            guard let date1 = formatter.date(from: incident1.createdAt),
                  let date2 = formatter.date(from: incident2.createdAt) else {
                return false
            }
            return date1 > date2
        }

        summary.incidents = allIncidents

        alertSummary = summary
    }

    // MARK: - API Methods

    func acknowledgeAllIncidents() async throws {
        // Get all triggered incidents
        let triggeredIncidents = alertSummary.incidents.filter { $0.status == .triggered }

        guard !triggeredIncidents.isEmpty else {
            return
        }

        // Acknowledge each incident without refreshing after each one
        var errors: [Error] = []
        for incident in triggeredIncidents {
            guard let accountId = incident.accountId else {
                continue
            }

            guard let service = accountServices[accountId] else {
                continue
            }

            do {
                try await service.acknowledgeIncident(incidentId: incident.id)
            } catch {
                errors.append(error)
            }
        }

        // If any errors occurred, throw the first one
        if let firstError = errors.first {
            throw firstError
        }

        // Refresh data once at the end to get latest from server
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        await fetchAllData()
    }

    func acknowledgeIncident(incidentId: String, accountId: String) async throws {
        guard let service = accountServices[accountId] else {
            throw OnCallError.apiError(
                technicalMessage: "Account service not found",
                userMessage: "Unable to find account configuration"
            )
        }

        try await service.acknowledgeIncident(incidentId: incidentId)

        // Refresh data after acknowledgment
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await fetchAllData()
    }

    func testConnection(accountId: String) async -> Bool {
        guard let service = accountServices[accountId] else {
            return false
        }
        return await service.testConnection()
    }

    // MARK: - Public Helper Methods

    func refreshData() {
        // Prevent rapid refresh spam
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < minimumFetchInterval {
            Self.logger.debug("Refresh throttled - minimum interval not met")
            return
        }

        lastFetchTime = Date()

        Task {
            await fetchAllData()
        }
    }

    // MARK: - Secure Logging

    private static let logger = Logger(subsystem: "com.oncall.notify", category: "api")
}
