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
    private let minimumFetchInterval: TimeInterval = 5.0  // Minimum 5 seconds between fetches
    private let maxRetryCount: Int = 3
    private var isBackingOff: Bool = false

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
            self.lastError = OnCallError.noAPIToken
            return
        }

        self.isLoading = true
        self.lastError = nil

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
            self.lastError = error

            // Handle fetch error with backoff logic
            handleFetchError(error)

            // Log technical details securely
            #if DEBUG
            if let onCallError = error as? OnCallError {
                print("[DEBUG] \(onCallError.technicalDescription)")
            } else {
                print("[DEBUG] \(error.localizedDescription)")
            }
            #endif
        }

        self.isLoading = false
    }

    // MARK: - API Methods

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
                    userMessage: "Unable to complete request"
                )
            }
        }

        let decoder = JSONDecoder()
        let userResponse = try decoder.decode(PagerDutyUserResponse.self, from: data)
        currentUserId = userResponse.user.id
    }

    private func fetchIncidents() async throws -> [Incident] {
        let endpoint = "/incidents"
        var components = URLComponents(string: baseURL + endpoint)!

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
                    userMessage: "Unable to complete request"
                )
            }
        }

        let decoder = JSONDecoder()
        let incidentsResponse = try decoder.decode(PagerDutyIncidentsResponse.self, from: data)

        return incidentsResponse.incidents
    }

    private func fetchOncalls() async throws -> [Oncall] {
        let endpoint = "/oncalls"
        var components = URLComponents(string: baseURL + endpoint)!

        components.queryItems = [
            URLQueryItem(name: "include[]", value: "users"),
            URLQueryItem(name: "include[]", value: "schedules"),
            URLQueryItem(name: "limit", value: "100")
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
                    userMessage: "Unable to complete request"
                )
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
        guard let token = KeychainHelper.shared.getAPIToken() else {
            throw OnCallError.noAPIToken
        }

        logSecureRequest(url)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Set headers - token will not be logged due to secure logging
        request.setValue("Token token=\(token)", forHTTPHeaderField: "Authorization")
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
        summary.acknowledgedCount = incidents.filter { $0.status == .acknowledged }.count
        summary.unacknowledgedCount = incidents.filter { $0.status == .triggered }.count

        // Process on-call status
        let now = Date()
        var isCurrentlyOnCall = false
        var nextShift: Date?

        let dateFormatter = ISO8601DateFormatter()

        for oncall in oncalls {
            // Check if currently on call
            if let startString = oncall.start,
               let endString = oncall.end,
               let startDate = dateFormatter.date(from: startString),
               let endDate = dateFormatter.date(from: endString) {

                // Currently on call
                if startDate <= now && endDate > now {
                    isCurrentlyOnCall = true
                }

                // Find next shift
                if startDate > now {
                    if nextShift == nil || startDate < nextShift! {
                        nextShift = startDate
                    }
                }
            }
        }

        summary.isOnCall = isCurrentlyOnCall
        summary.nextOnCallShift = nextShift

        self.alertSummary = summary
        
        // Process notification changes
        NotificationService.shared.processAlertChanges(currentSummary: summary)
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
            self.lastError = error
            return false
        }
    }

    // MARK: - Rate Limiting Helpers

    private func handleFetchSuccess() {
        consecutiveErrors = 0
        lastFetchTime = Date()
        isBackingOff = false
    }

    private func handleFetchError(_ error: Error) {
        consecutiveErrors += 1
        lastFetchTime = Date()

        // Exponential backoff on repeated errors
        if consecutiveErrors >= maxRetryCount {
            isBackingOff = true
            let backoffTime = min(pow(2.0, Double(consecutiveErrors - maxRetryCount)) * 30, 300)

            Self.logger.warning("Entering backoff period for \(backoffTime, privacy: .public) seconds after \(self.consecutiveErrors, privacy: .public) consecutive errors")

            DispatchQueue.main.asyncAfter(deadline: .now() + backoffTime) { [weak self] in
                guard let self = self else { return }
                self.isBackingOff = false
                self.consecutiveErrors = max(0, self.consecutiveErrors - 1)
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
