//
//  AlertOpsService.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation
import os.log

/// Service that manages AlertOps API calls for a single account
class AlertOpsService: OnCallServiceProvider {
    private(set) var account: Account
    private let baseURL = "https://api.alertops.com"
    private var currentUserId: String?
    private var currentUserName: String?

    // Track previous state for change detection
    private var previousIncidentStatuses: [String: IncidentStatus] = [:]
    private var previousOnCallStatus: Bool = false
    private var isFirstFetch: Bool = true

    private static let iso8601Formatter = ISO8601DateFormatter()

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
        self.account = newAccount
    }

    // MARK: - OnCallServiceProvider Implementation

    func fetchData() async throws -> AccountAlertSummary {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        // First, get current user info if we don't have it
        if currentUserId == nil {
            try await fetchCurrentUser(apiToken: apiToken)
        }

        // Fetch incidents and schedules in parallel
        async let incidents = fetchIncidents(apiToken: apiToken)
        async let schedules = fetchSchedules(apiToken: apiToken)

        let (fetchedIncidents, fetchedSchedules) = try await (incidents, schedules)

        // Process and return summary
        return processData(incidents: fetchedIncidents, schedules: fetchedSchedules)
    }

    func acknowledgeIncident(incidentId: String) async throws {
        try await performAcknowledgment(incidentId: incidentId)
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
        let endpoint = "/api/v2/users/me"
        let url = try buildURL(endpoint: endpoint)
        let request = try buildRequest(url: url, apiToken: apiToken)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            try handleHTTPError(statusCode: httpResponse.statusCode)
            throw OnCallError.invalidResponse
        }

        let decoder = JSONDecoder()
        let userResponse = try decoder.decode(AlertOpsUserResponse.self, from: data)
        currentUserId = userResponse.user.id
        currentUserName = userResponse.user.name
    }

    private func fetchIncidents(apiToken: String) async throws -> [Incident] {
        let endpoint = "/api/v2/incidents"
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }

        // Filter for open incidents (triggered and acknowledged)
        components.queryItems = [
            URLQueryItem(name: "status", value: "Open"),
            URLQueryItem(name: "limit", value: "100")
        ]

        // Add user filter if we have current user
        if let userName = currentUserName {
            components.queryItems?.append(URLQueryItem(name: "assigned_to", value: userName))
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
            try handleHTTPError(statusCode: httpResponse.statusCode)
            throw OnCallError.invalidResponse
        }

        let decoder = JSONDecoder()
        let incidentsResponse = try decoder.decode(AlertOpsIncidentsResponse.self, from: data)

        // Map AlertOps incidents to common Incident model
        return incidentsResponse.incidents.map { alertOpsIncident in
            mapAlertOpsIncident(alertOpsIncident)
        }
    }

    private func fetchSchedules(apiToken: String) async throws -> [Oncall] {
        let endpoint = "/api/v2/schedules"
        let url = try buildURL(endpoint: endpoint)
        let request = try buildRequest(url: url, apiToken: apiToken)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            try handleHTTPError(statusCode: httpResponse.statusCode)
            throw OnCallError.invalidResponse
        }

        let decoder = JSONDecoder()
        let schedulesResponse = try decoder.decode(AlertOpsSchedulesResponse.self, from: data)

        // Map AlertOps schedules to Oncall records for current user
        var oncalls: [Oncall] = []
        for schedule in schedulesResponse.schedules {
            if let currentOncalls = schedule.currentOncall {
                for oncallUser in currentOncalls where oncallUser.userId == currentUserId {
                    oncalls.append(mapAlertOpsOncall(schedule: schedule, oncallUser: oncallUser))
                }
            }
        }

        return oncalls
    }

    private func performAcknowledgment(incidentId: String) async throws {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        let endpoint = "/api/v2/incidents/\(incidentId)/acknowledge"
        let url = try buildURL(endpoint: endpoint)
        var request = try buildRequest(url: url, apiToken: apiToken)
        request.httpMethod = "POST"

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            try handleHTTPError(statusCode: httpResponse.statusCode)
            throw OnCallError.acknowledgmentFailed(message: "Failed to acknowledge incident")
        }
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // AlertOps uses "api-key" header for authentication
        request.setValue(apiToken, forHTTPHeaderField: "api-key")
        return request
    }

    private func handleHTTPError(statusCode: Int) throws {
        if statusCode == 401 || statusCode == 403 {
            throw OnCallError.unauthorized
        } else if statusCode == 429 {
            throw OnCallError.rateLimited
        } else if statusCode >= 500 {
            throw OnCallError.serverError(statusCode: statusCode)
        }
    }

    private func mapAlertOpsIncident(_ alertOpsIncident: AlertOpsIncident) -> Incident {
        // Map AlertOps status to our IncidentStatus enum
        let status: IncidentStatus
        switch alertOpsIncident.status.lowercased() {
        case "open", "triggered":
            status = .triggered
        case "acknowledged":
            status = .acknowledged
        case "closed", "resolved":
            status = .resolved
        default:
            status = .triggered
        }

        // Map urgency based on priority/severity
        let urgency: String
        if let priority = alertOpsIncident.priority?.lowercased() {
            urgency = (priority == "high" || priority == "critical") ? "high" : "low"
        } else if let severity = alertOpsIncident.severity?.lowercased() {
            urgency = (severity == "critical" || severity == "high") ? "high" : "low"
        } else {
            urgency = "low"
        }

        return Incident(
            id: alertOpsIncident.id,
            type: "incident",
            summary: alertOpsIncident.title,
            status: status,
            urgency: urgency,
            title: alertOpsIncident.title,
            createdAt: alertOpsIncident.createdAt,
            updatedAt: alertOpsIncident.updatedAt,
            htmlUrl: nil, // AlertOps may not provide direct URLs in the same way
            incidentNumber: nil,
            service: alertOpsIncident.service.map { Service(
                id: $0,
                type: "service",
                summary: $0,
                htmlUrl: nil
            )},
            assignments: alertOpsIncident.assignedTo.map { assignedTo in
                [Assignment(at: alertOpsIncident.createdAt, assignee: User(
                    id: assignedTo,
                    type: "user",
                    summary: assignedTo,
                    htmlUrl: nil
                ))]
            },
            acknowledgements: status == .acknowledged ? [Acknowledgement(
                at: alertOpsIncident.updatedAt ?? alertOpsIncident.createdAt,
                acknowledger: User(
                    id: currentUserId ?? "unknown",
                    type: "user",
                    summary: currentUserName ?? "Unknown",
                    htmlUrl: nil
                )
            )] : nil,
            lastStatusChangeAt: alertOpsIncident.updatedAt,
            accountId: account.id
        )
    }

    private func mapAlertOpsOncall(schedule: AlertOpsSchedule, oncallUser: AlertOpsOncallUser) -> Oncall {
        return Oncall(
            escalationPolicy: EscalationPolicy(
                id: schedule.id,
                type: "escalation_policy",
                summary: schedule.name,
                htmlUrl: nil
            ),
            escalationLevel: 1,
            schedule: Schedule(
                id: schedule.id,
                type: "schedule",
                summary: schedule.name,
                htmlUrl: nil
            ),
            user: User(
                id: oncallUser.userId,
                type: "user",
                summary: oncallUser.userName,
                htmlUrl: nil
            ),
            start: oncallUser.start,
            end: oncallUser.end
        )
    }

    private func processData(incidents: [Incident], schedules: [Oncall]) -> AccountAlertSummary {
        let triggeredIncidents = incidents.filter { $0.status == .triggered }
        let acknowledgedIncidents = incidents.filter { $0.status == .acknowledged }

        let currentlyOnCall = !schedules.isEmpty

        // Detect changes and send notifications (skip on first fetch)
        if !isFirstFetch {
            detectAndNotifyChanges(incidents: incidents, isOnCall: currentlyOnCall)
        }

        // Update tracking state
        previousIncidentStatuses = Dictionary(
            uniqueKeysWithValues: incidents.map { ($0.id, $0.status) }
        )
        previousOnCallStatus = currentlyOnCall
        isFirstFetch = false

        return AccountAlertSummary(
            accountId: account.id,
            accountName: account.name,
            totalAlerts: incidents.count,
            acknowledgedCount: acknowledgedIncidents.count,
            unacknowledgedCount: triggeredIncidents.count,
            isOnCall: currentlyOnCall,
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

    private static let logger = Logger(subsystem: "com.oncall.notify", category: "alertops")
}
