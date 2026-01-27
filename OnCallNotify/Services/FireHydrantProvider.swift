//
//  FireHydrantProvider.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation
import os.log

class FireHydrantProvider: ServiceProvider {
    private(set) var account: Account
    private let baseURL = "https://api.firehydrant.io/v1"
    private var currentUserId: String?

    private var previousIncidentStatuses: [String: IncidentStatus] = [:]
    private var previousOnCallStatus: Bool = false
    private var isFirstFetch: Bool = true

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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

    // MARK: - ServiceProvider Implementation

    func fetchData() async throws -> AccountAlertSummary {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        // Fetch current user if needed
        if currentUserId == nil {
            try await fetchCurrentUser(apiToken: apiToken)
        }

        // Fetch incidents and on-call status
        async let incidents = fetchIncidents(apiToken: apiToken)
        async let isOnCall = checkOnCallStatus(apiToken: apiToken)

        let (fetchedIncidents, onCallStatus) = try await (incidents, isOnCall)

        return processData(incidents: fetchedIncidents, isOnCall: onCallStatus)
    }

    func acknowledgeIncident(incidentId: String) async throws {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        let endpoint = "/incidents/\(incidentId)/acknowledge"
        let url = try buildURL(endpoint: endpoint)
        var request = try buildRequest(url: url, apiToken: apiToken)
        request.httpMethod = "POST"

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
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
            throw handleHTTPError(statusCode: httpResponse.statusCode)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = json["id"] as? String {
            currentUserId = id
        }
    }

    private func fetchIncidents(apiToken: String) async throws -> [Incident] {
        let endpoint = "/incidents"
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "status", value: "open"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "100")
        ]

        guard let url = components.url else {
            throw OnCallError.invalidURL
        }

        let request = try buildRequest(url: url, apiToken: apiToken)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw handleHTTPError(statusCode: httpResponse.statusCode)
        }

        return try parseFireHydrantIncidents(from: data)
    }

    private func checkOnCallStatus(apiToken: String) async throws -> Bool {
        // TODO: Implement FireHydrant on-call schedule checking
        // FireHydrant on-call schedules are managed through integrations
        // For now, return false as default - can be enhanced with specific schedule API
        return false
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
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func parseFireHydrantIncidents(from data: Data) throws -> [Incident] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let incidentsData = json["data"] as? [[String: Any]] else {
            return []
        }

        var incidents: [Incident] = []

        for incidentData in incidentsData {
            guard let id = incidentData["id"] as? String,
                  let summary = incidentData["name"] as? String,
                  let createdAt = incidentData["created_at"] as? String else {
                continue
            }

            // Map FireHydrant milestone to status
            let milestone = incidentData["current_milestone"] as? String ?? ""
            let status: IncidentStatus = milestone.contains("acknowledged") ? .acknowledged : .triggered

            let incident = Incident(
                id: id,
                type: "incident",
                summary: summary,
                status: status,
                urgency: "high",
                title: summary,
                createdAt: createdAt,
                updatedAt: incidentData["updated_at"] as? String,
                htmlUrl: incidentData["private_status_page_url"] as? String,
                incidentNumber: nil,
                service: nil,
                assignments: nil,
                acknowledgements: nil,
                lastStatusChangeAt: incidentData["updated_at"] as? String,
                accountId: account.id
            )

            incidents.append(incident)
        }

        return incidents
    }

    private func processData(incidents: [Incident], isOnCall: Bool) -> AccountAlertSummary {
        // Detect changes and send notifications (skip on first fetch)
        if !isFirstFetch {
            detectAndNotifyChanges(incidents: incidents, isOnCall: isOnCall)
        }

        previousIncidentStatuses = Dictionary(uniqueKeysWithValues: incidents.map { ($0.id, $0.status) })
        previousOnCallStatus = isOnCall
        isFirstFetch = false

        return AccountAlertSummary(
            accountId: account.id,
            accountName: account.name,
            totalAlerts: incidents.count,
            acknowledgedCount: incidents.filter { $0.status == .acknowledged }.count,
            unacknowledgedCount: incidents.filter { $0.status == .triggered }.count,
            isOnCall: isOnCall,
            incidents: incidents
        )
    }

    private func detectAndNotifyChanges(incidents: [Incident], isOnCall: Bool) {
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

    private func handleHTTPError(statusCode: Int) -> OnCallError {
        if statusCode == 401 {
            return OnCallError.unauthorized
        } else if statusCode == 429 {
            return OnCallError.rateLimited
        } else if statusCode >= 500 {
            return OnCallError.serverError(statusCode: statusCode)
        } else {
            return OnCallError.apiError(
                technicalMessage: "HTTP \(statusCode)",
                userMessage: "Unable to complete request")
        }
    }
}
