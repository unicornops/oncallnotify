//
//  AlertOpsProvider.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation
import os.log

class AlertOpsProvider: ServiceProvider {
    private(set) var account: Account
    private let baseURL = "https://api.alertops.com/api/v2"
    private var currentUserId: String?

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

    // MARK: - ServiceProvider Implementation

    func fetchData() async throws -> AccountAlertSummary {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        // Fetch alerts
        let incidents = try await fetchAlerts(apiToken: apiToken)

        // Check on-call status
        let isOnCall = try await checkOnCallStatus(apiToken: apiToken)

        return processData(incidents: incidents, isOnCall: isOnCall)
    }

    func acknowledgeIncident(incidentId: String) async throws {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        // AlertOps uses alert acknowledgment
        let endpoint = "/alerts/\(incidentId)/acknowledge"
        let url = try buildURL(endpoint: endpoint)
        var request = try buildRequest(url: url, apiToken: apiToken)
        request.httpMethod = "POST"

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnCallError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw handleHTTPError(statusCode: httpResponse.statusCode)
        }
    }

    func testConnection() async -> Bool {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            return false
        }

        do {
            // Test by fetching alerts
            _ = try await fetchAlerts(apiToken: apiToken)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private API Methods

    private func fetchAlerts(apiToken: String) async throws -> [Incident] {
        let endpoint = "/alerts"
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }

        // Fetch alerts with status 'new' or 'open' (both are active/triggered)
        components.queryItems = [
            URLQueryItem(name: "state", value: "new,open"),
            URLQueryItem(name: "limit", value: "100")
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

        return try parseAlertOpsAlerts(from: data)
    }

    private func checkOnCallStatus(apiToken: String) async throws -> Bool {
        // TODO: Implement AlertOps on-call schedule checking
        // AlertOps on-call is managed through schedules
        // Would need to check current on-call schedule
        // For now, return false as default
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

    private func parseAlertOpsAlerts(from data: Data) throws -> [Incident] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let alertsData = json["alerts"] as? [[String: Any]] else {
            return []
        }

        var incidents: [Incident] = []

        for alertData in alertsData {
            guard let id = alertData["id"] as? String,
                  let message = alertData["message"] as? String,
                  let createdAt = alertData["created_at"] as? String else {
                continue
            }

            // Map AlertOps status to our status
            let statusString = alertData["state"] as? String ?? "new"
            let status: IncidentStatus
            switch statusString {
            case "new", "open":
                status = .triggered
            case "acknowledged":
                status = .acknowledged
            case "closed", "resolved":
                status = .resolved
            default:
                status = .triggered
            }

            // Get priority
            let priority = alertData["priority"] as? String ?? "high"

            let incident = Incident(
                id: id,
                type: "alert",
                summary: message,
                status: status,
                urgency: priority.lowercased(),
                title: message,
                createdAt: createdAt,
                updatedAt: alertData["updated_at"] as? String,
                htmlUrl: alertData["url"] as? String,
                incidentNumber: alertData["alert_number"] as? Int,
                service: nil,
                assignments: nil,
                acknowledgements: nil,
                lastStatusChangeAt: alertData["updated_at"] as? String,
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
