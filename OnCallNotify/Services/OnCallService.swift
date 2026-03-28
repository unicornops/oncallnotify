//
//  OnCallService.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

// swiftlint:disable file_length
import Foundation
import os.log

protocol AccountServicing: AnyObject {
    var account: Account { get }

    func updateAccount(_ newAccount: Account)
    func fetchData() async throws -> AccountAlertSummary
    func acknowledgeIncident(incidentId: String) async throws
    func performAcknowledgment(incidentId: String) async throws
    func testConnection() async -> Bool
}

protocol ChangeTrackingAccountService: AnyObject {
    var previousIncidentStatuses: [String: IncidentStatus] { get set }
    var previousOnCallStatus: Bool { get set }
    var isFirstFetch: Bool { get set }
}

extension ChangeTrackingAccountService {
    func detectAndNotifyChanges(incidents: [Incident], isOnCall: Bool) {
        let currentIncidentStatuses = Dictionary(uniqueKeysWithValues: incidents.map { ($0.id, $0.status) })
        let currentIncidentIds = Set(currentIncidentStatuses.keys)
        let previousIncidentIds = Set(previousIncidentStatuses.keys)

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
                if incident.status == .triggered {
                    NotificationService.shared.sendIncidentNotification(incident: incident)
                } else if incident.status == .acknowledged {
                    NotificationService.shared.sendIncidentAcknowledgedNotification(incident: incident)
                }
            }
        }

        let resolvedIncidentIds = previousIncidentIds.subtracting(currentIncidentIds)
        for incidentId in resolvedIncidentIds {
            NotificationService.shared.removeIncidentNotification(incidentId: incidentId)
        }

        if isOnCall != previousOnCallStatus {
            if isOnCall {
                NotificationService.shared.sendOnCallStartNotification(nextShift: nil)
            } else {
                NotificationService.shared.sendOnCallEndNotification(nextShift: nil)
            }
        }
    }

    func updateChangeTracking(incidents: [Incident], isOnCall: Bool) {
        if !isFirstFetch {
            detectAndNotifyChanges(incidents: incidents, isOnCall: isOnCall)
        }

        previousIncidentStatuses = Dictionary(uniqueKeysWithValues: incidents.map { ($0.id, $0.status) })
        previousOnCallStatus = isOnCall
        isFirstFetch = false
    }
}

@MainActor
class OnCallService: ObservableObject {
    static let shared = OnCallService()

    @Published var alertSummary = AlertSummary()
    @Published var isLoading = false
    @Published var lastError: Error?

    private var accountServices: [String: AccountServicing] = [:]
    private var updateTimer: Timer?

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
        let enabledAccounts = accounts.filter(\.isEnabled)
        let enabledAccountIds = Set(enabledAccounts.map(\.id))

        accountServices = accountServices.filter { enabledAccountIds.contains($0.key) }

        for account in enabledAccounts {
            if let existingService = accountServices[account.id] {
                existingService.updateAccount(account)
                continue
            }

            switch account.serviceType {
            case .pagerDuty:
                accountServices[account.id] = PagerDutyAccountService(account: account)
            case .demo:
                accountServices[account.id] = DemoAccountService(account: account)
            }
        }
    }

    func reloadAccounts() {
        initializeAccountServices()
        refreshData(force: true)
    }

    func enabledAccounts() -> [Account] {
        KeychainHelper.shared.getAccounts().filter(\.isEnabled)
    }

    func hasEnabledDemoAccount() -> Bool {
        enabledAccounts().contains { $0.isDemoAccount }
    }

    func primaryDemoAccount() -> Account? {
        enabledAccounts().first { $0.isDemoAccount }
    }

    func primaryLiveAccount() -> Account? {
        enabledAccounts().first { !$0.isDemoAccount }
    }

    func demoConfiguration(for accountId: String) -> DemoConfiguration? {
        guard let service = accountServices[accountId] as? DemoAccountService else {
            return nil
        }

        return service.configuration()
    }

    func setDemoScenario(_ scenario: DemoScenario, for accountId: String) {
        guard let service = accountServices[accountId] as? DemoAccountService else {
            return
        }

        service.setScenario(scenario)
        refreshData(force: true)
    }

    func advanceDemoScenario(for accountId: String) {
        guard let service = accountServices[accountId] as? DemoAccountService else {
            return
        }

        service.advanceScenario()
        refreshData(force: true)
    }

    func resetDemoScenario(for accountId: String) {
        guard let service = accountServices[accountId] as? DemoAccountService else {
            return
        }

        service.resetScenario()
        refreshData(force: true)
    }

    // MARK: - Auto Update

    func startAutoUpdate() {
        Task {
            await fetchAllData()
        }

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
        guard !accountServices.isEmpty else {
            lastError = OnCallError.noAPIToken
            alertSummary = AlertSummary()
            return
        }

        isLoading = true
        lastError = nil

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
                if let summary {
                    accountSummaries[accountId] = summary
                } else if let error {
                    hasError = true
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            aggregateResults(accountSummaries: accountSummaries)

            if hasError, let firstError {
                lastError = firstError
            }
        }

        isLoading = false
    }

    private func aggregateResults(accountSummaries: [String: AccountAlertSummary]) {
        var summary = AlertSummary()
        summary.accountSummaries = accountSummaries

        var allIncidents: [Incident] = []
        var nextShiftCandidates: [Date] = []

        for (_, accountSummary) in accountSummaries {
            summary.totalAlerts += accountSummary.totalAlerts
            summary.acknowledgedCount += accountSummary.acknowledgedCount
            summary.unacknowledgedCount += accountSummary.unacknowledgedCount
            summary.isOnCall = summary.isOnCall || accountSummary.isOnCall
            allIncidents.append(contentsOf: accountSummary.incidents)

            if let nextShift = accountSummary.nextOnCallShift {
                nextShiftCandidates.append(nextShift)
            }
        }

        allIncidents.sort { incident1, incident2 in
            let formatter = ISO8601DateFormatter()
            guard let date1 = formatter.date(from: incident1.createdAt),
                  let date2 = formatter.date(from: incident2.createdAt) else {
                return false
            }
            return date1 > date2
        }

        summary.incidents = allIncidents
        summary.nextOnCallShift = nextShiftCandidates.min()
        alertSummary = summary
    }

    // MARK: - API Methods

    func acknowledgeAllIncidents() async throws {
        let triggeredIncidents = alertSummary.incidents.filter { $0.status == .triggered }

        guard !triggeredIncidents.isEmpty else {
            return
        }

        var errors: [Error] = []
        for incident in triggeredIncidents {
            guard let accountId = incident.accountId,
                  let service = accountServices[accountId] else {
                continue
            }

            do {
                try await service.performAcknowledgment(incidentId: incident.id)
            } catch {
                errors.append(error)
            }
        }

        if let firstError = errors.first {
            throw firstError
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
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

    func refreshData(force: Bool = false) {
        if !force,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < minimumFetchInterval {
            Self.logger.debug("Refresh throttled - minimum interval not met")
            return
        }

        lastFetchTime = Date()

        Task {
            await fetchAllData()
        }
    }

    private static let logger = Logger(subsystem: "com.oncall.notify", category: "api")
}

// MARK: - PagerDuty Account Service

class PagerDutyAccountService: AccountServicing, ChangeTrackingAccountService {
    private(set) var account: Account
    private let baseURL = "https://api.pagerduty.com"
    private var currentUserId: String?

    var previousIncidentStatuses: [String: IncidentStatus] = [:]
    var previousOnCallStatus: Bool = false
    var isFirstFetch: Bool = true

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

    func updateAccount(_ newAccount: Account) {
        account = newAccount
    }

    func fetchData() async throws -> AccountAlertSummary {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        if currentUserId == nil {
            try await fetchCurrentUser(apiToken: apiToken)
        }

        async let incidents = fetchIncidents(apiToken: apiToken)
        async let oncalls = fetchOncalls(apiToken: apiToken)

        let (fetchedIncidents, fetchedOncalls) = try await (incidents, oncalls)
        return processData(incidents: fetchedIncidents, oncalls: fetchedOncalls)
    }

    func acknowledgeIncident(incidentId: String) async throws {
        try await performAcknowledgment(incidentId: incidentId)
    }

    func performAcknowledgment(incidentId: String) async throws {
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
                    userMessage: "Unable to complete request"
                )
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
                    userMessage: "Unable to complete request"
                )
            }
        }

        let decoder = JSONDecoder()
        let incidentsResponse = try decoder.decode(PagerDutyIncidentsResponse.self, from: data)

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
        guard let futureDate = Calendar.current.date(byAdding: .day, value: futureScheduleLookupDays, to: now) else {
            throw OnCallError.apiError(
                technicalMessage: "Failed to calculate future date",
                userMessage: "Unable to process schedule data"
            )
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
                    userMessage: "Unable to complete request"
                )
            }
        }

        let decoder = JSONDecoder()
        let oncallsResponse = try decoder.decode(PagerDutyOncallsResponse.self, from: data)
        return oncallsResponse.oncalls
    }

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
        let now = Date()
        var isCurrentlyOnCall = false
        var nextOnCallShift: Date?

        for oncall in oncalls {
            if let startString = oncall.start,
               let startDate = Self.iso8601Formatter.date(from: startString),
               startDate > now {
                if let currentNextShift = nextOnCallShift {
                    if startDate < currentNextShift {
                        nextOnCallShift = startDate
                    }
                } else {
                    nextOnCallShift = startDate
                }
            }

            if let startString = oncall.start,
               let endString = oncall.end,
               let startDate = Self.iso8601Formatter.date(from: startString),
               let endDate = Self.iso8601Formatter.date(from: endString),
               startDate <= now,
               endDate > now {
                isCurrentlyOnCall = true
            }
        }

        updateChangeTracking(incidents: incidents, isOnCall: isCurrentlyOnCall)

        return AccountAlertSummary(
            accountId: account.id,
            accountName: account.name,
            totalAlerts: incidents.count,
            acknowledgedCount: incidents.filter { $0.status == .acknowledged }.count,
            unacknowledgedCount: incidents.filter { $0.status == .triggered }.count,
            isOnCall: isCurrentlyOnCall,
            nextOnCallShift: nextOnCallShift,
            incidents: incidents
        )
    }
}

// MARK: - Demo Account Service

class DemoAccountService: AccountServicing, ChangeTrackingAccountService {
    private(set) var account: Account

    var previousIncidentStatuses: [String: IncidentStatus] = [:]
    var previousOnCallStatus: Bool = false
    var isFirstFetch: Bool = true

    private let stateStore = DemoStateStore.shared

    init(account: Account) {
        self.account = account
    }

    func updateAccount(_ newAccount: Account) {
        account = newAccount
    }

    func fetchData() async throws -> AccountAlertSummary {
        let state = stateStore.state(for: account)
        updateChangeTracking(incidents: state.incidents, isOnCall: state.isOnCall)

        return AccountAlertSummary(
            accountId: account.id,
            accountName: account.name,
            totalAlerts: state.incidents.count,
            acknowledgedCount: state.incidents.filter { $0.status == .acknowledged }.count,
            unacknowledgedCount: state.incidents.filter { $0.status == .triggered }.count,
            isOnCall: state.isOnCall,
            nextOnCallShift: state.nextOnCallShift,
            incidents: state.incidents
        )
    }

    func acknowledgeIncident(incidentId: String) async throws {
        try await performAcknowledgment(incidentId: incidentId)
    }

    func performAcknowledgment(incidentId: String) async throws {
        guard stateStore.acknowledgeIncident(withId: incidentId, for: account) else {
            throw OnCallError.acknowledgmentFailed(message: "Unable to acknowledge the demo incident")
        }
    }

    func testConnection() async -> Bool {
        true
    }

    func configuration() -> DemoConfiguration {
        stateStore.configuration(for: account.id)
    }

    func setScenario(_ scenario: DemoScenario) {
        stateStore.setScenario(scenario, for: account)
    }

    func advanceScenario() {
        stateStore.advanceScenario(for: account)
    }

    func resetScenario() {
        stateStore.resetScenario(for: account)
    }
}

private struct DemoState: Codable {
    var scenario: DemoScenario
    var isOnCall: Bool
    var nextOnCallShift: Date?
    var incidents: [Incident]
}

private class DemoStateStore {
    static let shared = DemoStateStore()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let stateKeyPrefix = "com.oncall.notify.demo.state."
    private let configurationKeyPrefix = "com.oncall.notify.demo.configuration."
    private let iso8601Formatter = ISO8601DateFormatter()

    private init() {}

    func configuration(for accountId: String) -> DemoConfiguration {
        guard let data = defaults.data(forKey: configurationKeyPrefix + accountId),
              let configuration = try? decoder.decode(DemoConfiguration.self, from: data) else {
            return DemoConfiguration()
        }

        return configuration
    }

    func state(for account: Account) -> DemoState {
        if let data = defaults.data(forKey: stateKeyPrefix + account.id),
           let state = try? decoder.decode(DemoState.self, from: data) {
            return normalizeState(state, accountId: account.id)
        }

        let configuration = configuration(for: account.id)
        let state = makeState(for: configuration.selectedScenario, accountId: account.id)
        save(state: state, for: account.id)
        return state
    }

    func setScenario(_ scenario: DemoScenario, for account: Account) {
        save(configuration: DemoConfiguration(selectedScenario: scenario), for: account.id)
        save(state: makeState(for: scenario, accountId: account.id), for: account.id)
    }

    func advanceScenario(for account: Account) {
        let currentConfiguration = configuration(for: account.id)
        let scenarios = DemoScenario.allCases
        guard let currentIndex = scenarios.firstIndex(of: currentConfiguration.selectedScenario) else {
            setScenario(.reviewOverview, for: account)
            return
        }

        let nextIndex = scenarios.index(after: currentIndex)
        let nextScenario = nextIndex < scenarios.endIndex ? scenarios[nextIndex] : scenarios[scenarios.startIndex]
        setScenario(nextScenario, for: account)
    }

    func resetScenario(for account: Account) {
        let currentConfiguration = configuration(for: account.id)
        save(state: makeState(for: currentConfiguration.selectedScenario, accountId: account.id), for: account.id)
    }

    func acknowledgeIncident(withId incidentId: String, for account: Account) -> Bool {
        var state = state(for: account)
        guard let index = state.incidents.firstIndex(where: { $0.id == incidentId }) else {
            return false
        }

        let incident = state.incidents[index]
        guard incident.status == .triggered else {
            return true
        }

        let updatedDate = iso8601Formatter.string(from: Date())
        state.incidents[index] = incident.updating(
            status: .acknowledged,
            updatedAt: updatedDate,
            lastStatusChangeAt: updatedDate
        )
        save(state: state, for: account.id)
        return true
    }

    private func save(configuration: DemoConfiguration, for accountId: String) {
        guard let data = try? encoder.encode(configuration) else {
            return
        }

        defaults.set(data, forKey: configurationKeyPrefix + accountId)
    }

    private func save(state: DemoState, for accountId: String) {
        guard let data = try? encoder.encode(state) else {
            return
        }

        defaults.set(data, forKey: stateKeyPrefix + accountId)
    }

    private func normalizeState(_ state: DemoState, accountId: String) -> DemoState {
        var normalizedState = state
        normalizedState.incidents = normalizedState.incidents.map { incident in
            var taggedIncident = incident
            taggedIncident.accountId = accountId
            return taggedIncident
        }
        return normalizedState
    }

    private func makeState(for scenario: DemoScenario, accountId: String) -> DemoState {
        let now = Date()
        switch scenario {
        case .reviewOverview:
            return makeReviewOverviewState(now: now, accountId: accountId)
        case .activeIncident:
            return makeActiveIncidentState(now: now, accountId: accountId)
        case .shiftHandoff:
            return makeShiftHandoffState(now: now, accountId: accountId)
        case .quietShift:
            return makeQuietShiftState(now: now, accountId: accountId)
        }
    }

    private func makeReviewOverviewState(now: Date, accountId: String) -> DemoState {
        DemoState(
            scenario: .reviewOverview,
            isOnCall: true,
            nextOnCallShift: Calendar.current.date(byAdding: .day, value: 5, to: now),
            incidents: [
                makeIncident(
                    id: "demo-review-triggered",
                    title: "Payments API latency crossing SLO",
                    summary: "Latency to the payments API is above the paging threshold.",
                    status: .triggered,
                    urgency: "high",
                    createdAt: now.addingTimeInterval(-12 * 60),
                    updatedAt: now.addingTimeInterval(-12 * 60),
                    serviceName: "Payments API",
                    incidentNumber: 4201,
                    accountId: accountId
                ),
                makeIncident(
                    id: "demo-review-acknowledged",
                    title: "Background jobs retry queue growing",
                    summary: "Retry backlog is elevated but being actively worked.",
                    status: .acknowledged,
                    urgency: "high",
                    createdAt: now.addingTimeInterval(-52 * 60),
                    updatedAt: now.addingTimeInterval(-18 * 60),
                    serviceName: "Worker Fleet",
                    incidentNumber: 4200,
                    accountId: accountId
                )
            ]
        )
    }

    private func makeActiveIncidentState(now: Date, accountId: String) -> DemoState {
        DemoState(
            scenario: .activeIncident,
            isOnCall: true,
            nextOnCallShift: Calendar.current.date(byAdding: .day, value: 3, to: now),
            incidents: [
                makeIncident(
                    id: "demo-active-1",
                    title: "Login service elevated 5xx rate",
                    summary: "Customer sign-ins are failing for multiple regions.",
                    status: .triggered,
                    urgency: "high",
                    createdAt: now.addingTimeInterval(-6 * 60),
                    updatedAt: now.addingTimeInterval(-6 * 60),
                    serviceName: "Identity Platform",
                    incidentNumber: 4301,
                    accountId: accountId
                ),
                makeIncident(
                    id: "demo-active-2",
                    title: "Search index replication lag",
                    summary: "Search results are stale while replicas catch up.",
                    status: .triggered,
                    urgency: "high",
                    createdAt: now.addingTimeInterval(-24 * 60),
                    updatedAt: now.addingTimeInterval(-24 * 60),
                    serviceName: "Search Cluster",
                    incidentNumber: 4300,
                    accountId: accountId
                ),
                makeIncident(
                    id: "demo-active-3",
                    title: "Billing exports delayed",
                    summary: "Scheduled exports are delayed but customer traffic is unaffected.",
                    status: .acknowledged,
                    urgency: "low",
                    createdAt: now.addingTimeInterval(-90 * 60),
                    updatedAt: now.addingTimeInterval(-40 * 60),
                    serviceName: "Billing Pipeline",
                    incidentNumber: 4298,
                    accountId: accountId
                )
            ]
        )
    }

    private func makeShiftHandoffState(now: Date, accountId: String) -> DemoState {
        DemoState(
            scenario: .shiftHandoff,
            isOnCall: false,
            nextOnCallShift: Calendar.current.date(byAdding: .hour, value: 6, to: now),
            incidents: [
                makeIncident(
                    id: "demo-handoff-1",
                    title: "Synthetic checkout monitor flapping",
                    summary: "Intermittent monitor failures were acknowledged during handoff.",
                    status: .acknowledged,
                    urgency: "low",
                    createdAt: now.addingTimeInterval(-3 * 3600),
                    updatedAt: now.addingTimeInterval(-45 * 60),
                    serviceName: "Checkout Experience",
                    incidentNumber: 4288,
                    accountId: accountId
                )
            ]
        )
    }

    private func makeQuietShiftState(now: Date, accountId: String) -> DemoState {
        DemoState(
            scenario: .quietShift,
            isOnCall: false,
            nextOnCallShift: Calendar.current.date(byAdding: .hour, value: 2, to: now),
            incidents: []
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func makeIncident(
        id: String,
        title: String,
        summary: String,
        status: IncidentStatus,
        urgency: String,
        createdAt: Date,
        updatedAt: Date,
        serviceName: String,
        incidentNumber: Int,
        accountId: String
    ) -> Incident {
        Incident(
            id: id,
            type: "incident",
            summary: summary,
            status: status,
            urgency: urgency,
            title: title,
            createdAt: iso8601Formatter.string(from: createdAt),
            updatedAt: iso8601Formatter.string(from: updatedAt),
            htmlUrl: nil,
            incidentNumber: incidentNumber,
            service: Service(
                id: "service-\(id)",
                type: "service_reference",
                summary: serviceName,
                htmlUrl: nil
            ),
            assignments: nil,
            acknowledgements: nil,
            lastStatusChangeAt: iso8601Formatter.string(from: updatedAt),
            accountId: accountId
        )
    }
}

private extension Incident {
    func updating(
        status: IncidentStatus,
        updatedAt: String?,
        lastStatusChangeAt: String?
    ) -> Incident {
        Incident(
            id: id,
            type: type,
            summary: summary,
            status: status,
            urgency: urgency,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            htmlUrl: htmlUrl,
            incidentNumber: incidentNumber,
            service: service,
            assignments: assignments,
            acknowledgements: acknowledgements,
            lastStatusChangeAt: lastStatusChangeAt,
            accountId: accountId
        )
    }
}
