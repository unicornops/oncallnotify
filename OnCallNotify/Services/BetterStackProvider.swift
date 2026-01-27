//
//  BetterStackProvider.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation
import os.log

class BetterStackProvider: ServiceProvider {
    private(set) var account: Account
    private let baseURL = "https://uptime.betterstack.com/api/v2"
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

        // Fetch incidents
        let incidents = try await fetchIncidents(apiToken: apiToken)

        // Check on-call status
        let isOnCall = try await checkOnCallStatus(apiToken: apiToken)

        return processData(incidents: incidents, isOnCall: isOnCall)
    }

    func acknowledgeIncident(incidentId: String) async throws {
        guard let apiToken = KeychainHelper.shared.getAPIToken(forAccountId: account.id) else {
            throw OnCallError.noAPIToken
        }

        // BetterStack uses incident acknowledgment endpoint
        let endpoint = "/incidents/\(incidentId)/acknowledge"
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
            // Test by fetching monitors
            _ = try await fetchIncidents(apiToken: apiToken)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private API Methods

    private func fetchIncidents(apiToken: String) async throws -> [Incident] {
        let endpoint = "/incidents"
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw OnCallError.invalidURL
        }

        // Fetch only unresolved incidents
        components.queryItems = [
            URLQueryItem(name: "status", value: "open"),
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

        return try parseBetterStackIncidents(from: data)
    }

    private func checkOnCallStatus(apiToken: String) async throws -> Bool {
        // TODO: Implement BetterStack on-call schedule checking
        // BetterStack on-call is managed through on-call schedules
        // Would need to check current on-call rotation
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

    private func parseBetterStackIncidents(from data: Data) throws -> [Incident] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let incidentsData = json["data"] as? [[String: Any]] else {
            return []
        }

        var incidents: [Incident] = []

        for incidentData in incidentsData {
            guard let id = incidentData["id"] as? String,
                  let attributes = incidentData["attributes"] as? [String: Any],
                  let name = attributes["name"] as? String,
                  let createdAt = attributes["started_at"] as? String else {
                continue
            }

            // Map BetterStack acknowledged to our status
            let acknowledged = attributes["acknowledged"] as? Bool ?? false
            let status: IncidentStatus = acknowledged ? .acknowledged : .triggered

            // Get severity/impact
            let impact = attributes["call"] as? String ?? "high"

            let incident = Incident(
                id: id,
                type: "incident",
                summary: name,
                status: status,
                urgency: impact.lowercased(),
                title: name,
                createdAt: createdAt,
                updatedAt: attributes["acknowledged_at"] as? String ?? createdAt,
                htmlUrl: attributes["screenshot_url"] as? String,
                incidentNumber: nil,
                service: nil,
                assignments: nil,
                acknowledgements: nil,
                lastStatusChangeAt: attributes["acknowledged_at"] as? String,
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
