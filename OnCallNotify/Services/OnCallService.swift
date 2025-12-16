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

    private var accountServices: [String: AccountService] = [:] // accountId -> service
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
                accountServices[account.id] = AccountService(account: account)
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

// MARK: - AccountService

/// Service that manages API calls for a single account
class AccountService {
    private let account: Account
    private let baseURL = "https://api.pagerduty.com"
    private var currentUserId: String?

    // Track previous state for change detection per account
    private var previousIncidentStatuses: [String: IncidentStatus] = [:]
    private var previousOnCallStatus: Bool = false
    private var isFirstFetch: Bool = true

    private static let iso8601Formatter = ISO8601DateFormatter()
    private let futureScheduleLookupDays: Int = 30

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    init(account: Account) {
        self.account = account
    }

    func updateAccount(_ account: Account) {
        // Update if needed in future
    }

    // MARK: - Main Fetch

    func fetchData() async throws -> AccountAlertSummary {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        // First, get current user ID if we don't have it
        if currentUserId == nil {
            try await fetchCurrentUser(apiToken: apiToken)
        }

        // Fetch incidents and on-call status in parallel
        async let incidents = fetchIncidents(apiToken: apiToken)
        async let oncalls = fetchOncalls(apiToken: apiToken)

        let (fetchedIncidents, fetchedOncalls) = try await (incidents, oncalls)

        // Process and return summary
        return processData(incidents: fetchedIncidents, oncalls: fetchedOncalls)
    }

    // MARK: - API Methods

    func acknowledgeIncident(incidentId: String) async throws {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        let endpoint = "/incidents/\(incidentId)"
        let url = try buildURL(endpoint: endpoint)
        var request = try buildRequest(url: url, apiToken: apiToken)

        request.httpMethod = "PUT"

        let requestBody = AcknowledgeIncidentRequest(
            incident: AcknowledgeIncidentRequest.AcknowledgeIncidentBody()
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw OnCallError.unauthorized
            } else if httpResponse.statusCode == 429 {
                throw OnCallError.rateLimited
            } else if httpResponse.statusCode >= 500 {
                throw OnCallError.serverError(statusCode: httpResponse.statusCode)
            } else {
                throw OnCallError.acknowledgmentFailed(message: "Failed to acknowledge incident")
            }
        }
    }

    func testConnection() async -> Bool {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            return false
        }

        do {
            try await fetchCurrentUser(apiToken: apiToken)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private API Methods

    private func fetchCurrentUser(apiToken: String) async throws {
        let endpoint = "/users/me"
        let url = try buildURL(endpoint: endpoint)
        let request = try buildRequest(url: url, apiToken: apiToken)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw OnCallError.unauthorized
            } else if httpResponse.statusCode == 429 {
                throw OnCallError.rateLimited
            } else if httpResponse.statusCode >= 500 {
                throw OnCallError.serverError(statusCode: httpResponse.statusCode)
            } else {
                throw OnCallError.apiError(
                    technicalMessage: "HTTP \(httpResponse.statusCode)",
                    userMessage: "Unable to complete request")
            }
        }

        let decoder = JSONDecoder()
        let userResponse = try decoder.decode(PagerDutyUserResponse.self, from: data)
        currentUserId = userResponse.user.id
    }

    private func fetchIncidents(apiToken: String) async throws -> [Incident] {
        let endpoint = "/incidents"
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "statuses[]", value: "triggered"),
            URLQueryItem(name: "statuses[]", value: "acknowledged"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "sort_by", value: "created_at:desc")
        ]

        if let userId = currentUserId {
            components.queryItems?.append(URLQueryItem(name: "user_ids[]", value: userId))
        }

        guard let url = components.url else {
            throw OnCallError.invalidURL
        }

        let request = try buildRequest(url: url, apiToken: apiToken)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw OnCallError.unauthorized
            } else if httpResponse.statusCode == 429 {
                throw OnCallError.rateLimited
            } else if httpResponse.statusCode >= 500 {
                throw OnCallError.serverError(statusCode: httpResponse.statusCode)
            } else {
                throw OnCallError.apiError(
                    technicalMessage: "HTTP \(httpResponse.statusCode)",
                    userMessage: "Unable to complete request")
            }
        }

        let decoder = JSONDecoder()
        let incidentsResponse = try decoder.decode(PagerDutyIncidentsResponse.self, from: data)

        // Tag incidents with account ID
        return incidentsResponse.incidents.map { incident in
            var taggedIncident = incident
            taggedIncident.accountId = account.id
            return taggedIncident
        }
    }

    private func fetchOncalls(apiToken: String) async throws -> [Oncall] {
        let endpoint = "/oncalls"
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }

        let now = Date()
        guard let futureDate = Calendar.current.date(
            byAdding: .day, value: futureScheduleLookupDays, to: now) else {
            throw OnCallError.apiError(
                technicalMessage: "Failed to calculate future date",
                userMessage: "Unable to process schedule data")
        }

        let sinceParam = Self.iso8601Formatter.string(from: now)
        let untilParam = Self.iso8601Formatter.string(from: futureDate)

        components.queryItems = [
            URLQueryItem(name: "include[]", value: "users"),
            URLQueryItem(name: "include[]", value: "schedules"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "since", value: sinceParam),
            URLQueryItem(name: "until", value: untilParam)
        ]

        if let userId = currentUserId {
            components.queryItems?.append(URLQueryItem(name: "user_ids[]", value: userId))
        }

        guard let url = components.url else {
            throw OnCallError.invalidURL
        }

        let request = try buildRequest(url: url, apiToken: apiToken)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw OnCallError.unauthorized
            } else if httpResponse.statusCode == 429 {
                throw OnCallError.rateLimited
            } else if httpResponse.statusCode >= 500 {
                throw OnCallError.serverError(statusCode: httpResponse.statusCode)
            } else {
                throw OnCallError.apiError(
                    technicalMessage: "HTTP \(httpResponse.statusCode)",
                    userMessage: "Unable to complete request")
            }
        }

        let decoder = JSONDecoder()
        let oncallsResponse = try decoder.decode(PagerDutyOncallsResponse.self, from: data)

        return oncallsResponse.oncalls
    }

    // MARK: - Helper Methods

    private func buildURL(endpoint: String) throws -> URL {
        guard let url = URL(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }
        return url
    }

    private func buildRequest(url: URL, apiToken: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token token=\(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func processData(incidents: [Incident], oncalls: [Oncall]) -> AccountAlertSummary {
        // Process on-call status
        let now = Date()
        var isCurrentlyOnCall = false

        for oncall in oncalls {
            if let startString = oncall.start,
               let endString = oncall.end,
               let startDate = Self.iso8601Formatter.date(from: startString),
               let endDate = Self.iso8601Formatter.date(from: endString) {
                if startDate <= now, endDate > now {
                    isCurrentlyOnCall = true
                    break
                }
            }
        }

        // Detect changes and send notifications (skip on first fetch)
        if !isFirstFetch {
            detectAndNotifyChanges(incidents: incidents, isOnCall: isCurrentlyOnCall)
        }

        // Update previous state
        previousIncidentStatuses = Dictionary(uniqueKeysWithValues: incidents.map { ($0.id, $0.status) })
        previousOnCallStatus = isCurrentlyOnCall
        isFirstFetch = false

        // Return summary
        return AccountAlertSummary(
            accountId: account.id,
            accountName: account.name,
            totalAlerts: incidents.count,
            acknowledgedCount: incidents.filter { $0.status == .acknowledged }.count,
            unacknowledgedCount: incidents.filter { $0.status == .triggered }.count,
            isOnCall: isCurrentlyOnCall,
            incidents: incidents
        )
    }

    private func detectAndNotifyChanges(incidents: [Incident], isOnCall: Bool) {
        let currentIncidentStatuses = Dictionary(uniqueKeysWithValues: incidents.map { ($0.id, $0.status) })
        let currentIncidentIds = Set(currentIncidentStatuses.keys)
        let previousIncidentIds = Set(previousIncidentStatuses.keys)

        // Detect new incidents and status transitions
        for incident in incidents {
            if let previousStatus = previousIncidentStatuses[incident.id] {
                if previousStatus != incident.status {
                    if previousStatus == .triggered, incident.status == .acknowledged {
                        NotificationService.shared.removeIncidentNotification(incidentId: incident.id)
                        NotificationService.shared.sendIncidentAcknowledgedNotification(incident: incident)
                    } else if incident.status == .resolved {
                        NotificationService.shared.sendIncidentResolvedNotification(incident: incident)
                        NotificationService.shared.removeIncidentNotification(incidentId: incident.id)
                    }
                }
            } else {
                // New incident
                if incident.status == .triggered {
                    NotificationService.shared.sendIncidentNotification(incident: incident)
                } else if incident.status == .acknowledged {
                    NotificationService.shared.sendIncidentAcknowledgedNotification(incident: incident)
                }
            }
        }

        // Detect resolved incidents
        let resolvedIncidentIds = previousIncidentIds.subtracting(currentIncidentIds)
        for incidentId in resolvedIncidentIds {
            NotificationService.shared.removeIncidentNotification(incidentId: incidentId)
        }

        // Detect on-call status changes
        if isOnCall != previousOnCallStatus {
            if isOnCall {
                NotificationService.shared.sendOnCallStartNotification(nextShift: nil)
            } else {
                NotificationService.shared.sendOnCallEndNotification(nextShift: nil)
            }
        }
    }
}
