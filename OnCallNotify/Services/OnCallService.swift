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

    private let baseURL = "https://api.pagerduty.com"
    private var currentUserId: String?
    private var updateTimer: Timer?

    // Rate limiting and retry logic
    private var lastFetchTime: Date?
    private var consecutiveErrors: Int = 0
    private let minimumFetchInterval: TimeInterval = 5.0 // Minimum 5 seconds between fetches
    private let maxRetryCount: Int = 3
    private var isBackingOff: Bool = false

    // On-call schedule lookup window (days into the future)
    private let futureScheduleLookupDays: Int = 30

    // Track previous state for change detection
    private var previousIncidentStatuses: [String: IncidentStatus] = [:]
    private var previousOnCallStatus: Bool = false
    private var isFirstFetch: Bool = true

    // Cached ISO8601DateFormatter for performance (DateFormatter initialization is expensive)
    private static let iso8601Formatter = ISO8601DateFormatter()

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false

        // Disable automatic logging
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never

        return URLSession(configuration: config)
    }()

    private init() {
        startAutoUpdate()
    }

    deinit {
        updateTimer?.invalidate()
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
        guard KeychainHelper.shared.hasAPIToken() else {
            lastError = OnCallError.noAPIToken
            return
        }

        isLoading = true
        lastError = nil

        do {
            // First, get current user ID
            if currentUserId == nil {
                try await fetchCurrentUser()
            }

            // Fetch incidents and on-call status
            async let incidents = fetchIncidents()
            async let oncalls = fetchOncalls()

            let (fetchedIncidents, fetchedOncalls) = try await (incidents, oncalls)

            // Process the data
            await processData(incidents: fetchedIncidents, oncalls: fetchedOncalls)

            // Mark successful fetch
            handleFetchSuccess()
        } catch {
            lastError = error

            // Handle fetch error with backoff logic
            handleFetchError(error)

            // Log technical details securely
            #if DEBUG
            if let onCallError = error as? OnCallError {
                Self.logger.debug(
                    "Error: \(onCallError.technicalDescription, privacy: .private)")
            } else {
                Self.logger.debug("Error: \(error.localizedDescription, privacy: .private)")
            }
            #endif
        }
        isLoading = false
    }

    // MARK: - API Methods

    func acknowledgeAllIncidents() async throws {
        // Get all triggered incidents
        let triggeredIncidents = alertSummary.incidents.filter { $0.status == .triggered }

        guard !triggeredIncidents.isEmpty else {
            return
        }

        // Acknowledge each incident
        var errors: [Error] = []
        for incident in triggeredIncidents {
            do {
                try await acknowledgeIncident(incidentId: incident.id)
            } catch {
                errors.append(error)
            }
        }

        // If any errors occurred, throw the first one
        if let firstError = errors.first {
            throw firstError
        }

        // Refresh data to get latest from server
        await fetchAllData()
    }

    func acknowledgeIncident(incidentId: String) async throws {
        let endpoint = "/incidents/\(incidentId)"
        let url = try buildURL(endpoint: endpoint)
        var request = try buildRequest(url: url)

        // Override method to PUT for acknowledgment
        request.httpMethod = "PUT"

        // Create request body
        let requestBody = AcknowledgeIncidentRequest(
            incident: AcknowledgeIncidentRequest.AcknowledgeIncidentBody()
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        logSecureResponse(statusCode: httpResponse.statusCode, bytes: data.count)

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

        // Refresh data to get latest from server after a brief delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        await fetchAllData()
    }

    private func fetchCurrentUser() async throws {
        let endpoint = "/users/me"
        let url = try buildURL(endpoint: endpoint)
        let request = try buildRequest(url: url)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        // Log response securely
        logSecureResponse(statusCode: httpResponse.statusCode, bytes: data.count)

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

    private func fetchIncidents() async throws -> [Incident] {
        let endpoint = "/incidents"
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }

        // Get incidents that are triggered or acknowledged
        components.queryItems = [
            URLQueryItem(name: "statuses[]", value: "triggered"),
            URLQueryItem(name: "statuses[]", value: "acknowledged"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "sort_by", value: "created_at:desc")
        ]

        // If we have a user ID, filter by current user
        if let userId = currentUserId {
            components.queryItems?.append(URLQueryItem(name: "user_ids[]", value: userId))
        }

        guard let url = components.url else {
            throw OnCallError.invalidURL
        }

        let request = try buildRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        // Log response securely
        logSecureResponse(statusCode: httpResponse.statusCode, bytes: data.count)

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

        return incidentsResponse.incidents
    }

    private func fetchOncalls() async throws -> [Oncall] {
        let endpoint = "/oncalls"
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }

        // Set time range to fetch current and future on-call schedules
        // This allows us to show when the next shift starts
        let now = Date()
        guard
            let futureDate = Calendar.current.date(
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

        // Filter by current user if we have the ID
        if let userId = currentUserId {
            components.queryItems?.append(URLQueryItem(name: "user_ids[]", value: userId))
        }

        guard let url = components.url else {
            throw OnCallError.invalidURL
        }

        let request = try buildRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        // Log response securely
        logSecureResponse(statusCode: httpResponse.statusCode, bytes: data.count)

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

    private func buildRequest(url: URL) throws -> URLRequest {
        guard let apiToken = KeychainHelper.shared.getAPIToken() else {
            throw OnCallError.noAPIToken
        }

        logSecureRequest(url)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Set headers - API token will not be logged due to secure logging
        request.setValue("Token token=\(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Prevent caching of sensitive requests
        request.cachePolicy = .reloadIgnoringLocalCacheData

        return request
    }

    private func processData(incidents: [Incident], oncalls: [Oncall]) async {
        var summary = AlertSummary()

        // Process incidents
        summary.incidents = incidents
        summary.totalAlerts = incidents.count
        summary.acknowledgedCount = incidents.count { $0.status == .acknowledged }
        summary.unacknowledgedCount = incidents.count { $0.status == .triggered }

        // Process on-call status
        let now = Date()
        var isCurrentlyOnCall = false
        var nextShift: Date?

        for oncall in oncalls {
            // Check if currently on call
            if let startString = oncall.start,
               let endString = oncall.end,
               let startDate = Self.iso8601Formatter.date(from: startString),
               let endDate = Self.iso8601Formatter.date(from: endString) {
                // Currently on call
                if startDate <= now, endDate > now {
                    isCurrentlyOnCall = true
                }

                // Find next shift
                if startDate > now {
                    if let currentNextShift = nextShift {
                        if startDate < currentNextShift {
                            nextShift = startDate
                        }
                    } else {
                        nextShift = startDate
                    }
                }
            }
        }

        summary.isOnCall = isCurrentlyOnCall
        summary.nextOnCallShift = nextShift

        // Detect changes and send notifications (skip on first fetch)
        if !isFirstFetch {
            detectAndNotifyChanges(
                incidents: incidents, isOnCall: isCurrentlyOnCall, nextShift: nextShift)
        }

        // Update previous state
        let newIncidentStatuses = Dictionary(uniqueKeysWithValues: incidents.map { ($0.id, $0.status) })
        previousIncidentStatuses = newIncidentStatuses
        previousOnCallStatus = isCurrentlyOnCall
        isFirstFetch = false

        alertSummary = summary
    }

    private func detectAndNotifyChanges(incidents: [Incident], isOnCall: Bool, nextShift: Date?) {
        // Build current incident status map
        let currentIncidentStatuses = Dictionary(uniqueKeysWithValues: incidents.map { ($0.id, $0.status) })
        let currentIncidentIds = Set(currentIncidentStatuses.keys)
        let previousIncidentIds = Set(previousIncidentStatuses.keys)

        // Detect new incidents and status transitions
        for incident in incidents {
            if let previousStatus = previousIncidentStatuses[incident.id] {
                // Existing incident - check for status transition
                if previousStatus != incident.status {
                    // Status changed
                    if previousStatus == .triggered, incident.status == .acknowledged {
                        // Incident was acknowledged
                        NotificationService.shared.removeIncidentNotification(incidentId: incident.id)
                        NotificationService.shared.sendIncidentAcknowledgedNotification(incident: incident)
                    } else if incident.status == .resolved {
                        // Incident was resolved
                        NotificationService.shared.sendIncidentResolvedNotification(incident: incident)
                        NotificationService.shared.removeIncidentNotification(incidentId: incident.id)
                    }
                }
            } else {
                // New incident (never seen before)
                if incident.status == .triggered {
                    NotificationService.shared.sendIncidentNotification(incident: incident)
                } else if incident.status == .acknowledged {
                    // Newly discovered incident that's already acknowledged
                    NotificationService.shared.sendIncidentAcknowledgedNotification(incident: incident)
                }
            }
        }

        // Detect resolved incidents (no longer in current list)
        let resolvedIncidentIds = previousIncidentIds.subtracting(currentIncidentIds)
        for incidentId in resolvedIncidentIds {
            // Remove the notification for resolved incidents
            NotificationService.shared.removeIncidentNotification(incidentId: incidentId)
        }

        // Detect on-call status changes
        if isOnCall != previousOnCallStatus {
            if isOnCall {
                // Just went on-call
                NotificationService.shared.sendOnCallStartNotification(nextShift: nextShift)
            } else {
                // Just went off-call
                NotificationService.shared.sendOnCallEndNotification(nextShift: nextShift)
            }
        }
    }

    // MARK: - Public Helper Methods

    func refreshData() {
        // Prevent rapid refresh spam
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < minimumFetchInterval {
            Self.logger.debug("Refresh throttled - minimum interval not met")
            return
        }

        // Don't allow refresh during backoff period
        guard !isBackingOff else {
            Self.logger.debug("Refresh blocked - in backoff period")
            return
        }

        Task {
            await fetchAllData()
        }
    }

    func testConnection() async -> Bool {
        do {
            try await fetchCurrentUser()
            return true
        } catch {
            lastError = error
            return false
        }
    }

    // MARK: - Rate Limiting Helpers

    private func handleFetchSuccess() {
        consecutiveErrors = 0
        lastFetchTime = Date()
        isBackingOff = false
    }

    private func handleFetchError(_: Error) {
        consecutiveErrors += 1
        lastFetchTime = Date()

        // Exponential backoff on repeated errors
        if consecutiveErrors >= maxRetryCount {
            isBackingOff = true
            let backoffTime = min(pow(2.0, Double(consecutiveErrors - maxRetryCount)) * 30, 300)

            Self.logger.warning(
                "Entering backoff period for \(backoffTime, privacy: .public) seconds after \(self.consecutiveErrors, privacy: .public) consecutive errors"
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + backoffTime) { [weak self] in
                guard let self else { return }
                isBackingOff = false
                consecutiveErrors = max(0, consecutiveErrors - 1)
                Self.logger.info("Backoff period ended, resuming normal operation")
            }
        }
    }

    // MARK: - Secure Logging

    private static let logger = Logger(subsystem: "com.oncall.notify", category: "api")

    private func logSecureRequest(_ url: URL) {
        #if DEBUG
        Self.logger.debug("API Request: \(url.path, privacy: .public)")
        #else
        Self.logger.info("API Request initiated")
        #endif
    }

    private func logSecureResponse(statusCode: Int, bytes: Int) {
        #if DEBUG
        Self.logger.debug("API Response: Status \(statusCode), \(bytes) bytes")
        #else
        Self.logger.info("API Response received")
        #endif
    }
}
