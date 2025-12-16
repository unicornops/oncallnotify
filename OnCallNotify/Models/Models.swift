//
//  Models.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation

// MARK: - Alert Models

struct PagerDutyIncidentsResponse: Codable {
    let incidents: [Incident]
    let limit: Int
    let offset: Int
    let total: Int?
    let more: Bool
}

struct Incident: Codable, Identifiable {
    let id: String
    let type: String
    let summary: String
    let status: IncidentStatus
    let urgency: String
    let title: String
    let createdAt: String
    let updatedAt: String?
    let htmlUrl: String?
    let incidentNumber: Int?
    let service: Service?
    let assignments: [Assignment]?
    let acknowledgements: [Acknowledgement]?
    let lastStatusChangeAt: String?
    var accountId: String? // Added for multi-account support

    enum CodingKeys: String, CodingKey {
        case id, type, summary, status, urgency, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlUrl = "html_url"
        case incidentNumber = "incident_number"
        case service, assignments, acknowledgements
        case lastStatusChangeAt = "last_status_change_at"
        // accountId is not in API response, set programmatically
    }
}

enum IncidentStatus: String, Codable {
    case triggered
    case acknowledged
    case resolved
}

struct Service: Codable {
    let id: String
    let type: String
    let summary: String
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, type, summary
        case htmlUrl = "html_url"
    }
}

struct Assignment: Codable {
    let at: String
    let assignee: User
}

struct Acknowledgement: Codable {
    let at: String
    let acknowledger: User
}

struct User: Codable {
    let id: String
    let type: String
    let summary: String
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, type, summary
        case htmlUrl = "html_url"
    }
}

// MARK: - On-Call Models

struct PagerDutyOncallsResponse: Codable {
    let oncalls: [Oncall]
    let limit: Int
    let offset: Int
    let more: Bool
}

struct Oncall: Codable, Identifiable {
    let escalationPolicy: EscalationPolicy
    let escalationLevel: Int
    let schedule: Schedule?
    let user: User
    let start: String?
    let end: String?

    var id: String {
        user.id + (schedule?.id ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case escalationPolicy = "escalation_policy"
        case escalationLevel = "escalation_level"
        case schedule, user, start, end
    }
}

struct EscalationPolicy: Codable {
    let id: String
    let type: String
    let summary: String
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, type, summary
        case htmlUrl = "html_url"
    }
}

struct Schedule: Codable {
    let id: String
    let type: String
    let summary: String
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, type, summary
        case htmlUrl = "html_url"
    }
}

// MARK: - Current User

struct PagerDutyUserResponse: Codable {
    let user: UserDetail
}

struct UserDetail: Codable {
    let id: String
    let type: String
    let name: String
    let email: String
    let timeZone: String?
    let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, email
        case timeZone = "time_zone"
        case htmlUrl = "html_url"
    }
}

// MARK: - Multi-Account Models

enum ServiceType: String, Codable, CaseIterable {
    case pagerDuty = "PagerDuty"
    // Future services:
    // case atlassianCompass = "Atlassian Compass"
    // case jiraServiceManagement = "Jira Service Management"
    // case victorOps = "VictorOps"
    // case alertmanager = "Alertmanager"
    // case customWebhook = "Custom Webhook"

    var displayName: String {
        rawValue
    }
}

struct Account: Codable, Identifiable, Equatable {
    let id: String // UUID
    var name: String // User-friendly name
    let serviceType: ServiceType
    var isEnabled: Bool

    init(id: String = UUID().uuidString, name: String, serviceType: ServiceType, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.serviceType = serviceType
        self.isEnabled = isEnabled
    }

    static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - App State Models

struct AlertSummary {
    var totalAlerts: Int
    var acknowledgedCount: Int
    var unacknowledgedCount: Int
    var isOnCall: Bool
    var nextOnCallShift: Date?
    var incidents: [Incident]
    var accountSummaries: [String: AccountAlertSummary] // accountId -> summary

    init() {
        totalAlerts = 0
        acknowledgedCount = 0
        unacknowledgedCount = 0
        isOnCall = false
        nextOnCallShift = nil
        incidents = []
        accountSummaries = [:]
    }
}

struct AccountAlertSummary {
    let accountId: String
    let accountName: String
    var totalAlerts: Int
    var acknowledgedCount: Int
    var unacknowledgedCount: Int
    var isOnCall: Bool
    var incidents: [Incident]
}

// MARK: - Acknowledge Request/Response Models

struct AcknowledgeIncidentRequest: Codable {
    let incident: AcknowledgeIncidentBody

    struct AcknowledgeIncidentBody: Codable {
        let type: String = "incident_reference"
        let status: String = "acknowledged"
    }
}

struct AcknowledgeIncidentResponse: Codable {
    let incident: Incident
}

// MARK: - Error Models

enum OnCallError: Error, LocalizedError {
    case invalidURL
    case noAPIToken
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(statusCode: Int)
    case apiError(technicalMessage: String, userMessage: String? = nil)
    case networkError(underlyingError: Error, userMessage: String? = nil)
    case acknowledgmentFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Configuration error. Please check your settings."
        case .noAPIToken:
            "No API token found. Please configure in Settings."
        case .invalidResponse:
            "Unable to process server response. Please try again."
        case .unauthorized:
            "Authentication failed. Please verify your API token in Settings."
        case .rateLimited:
            "Too many requests. Please wait a few minutes and try again."
        case let .serverError(statusCode):
            if statusCode >= 500 {
                "Server is temporarily unavailable. Please try again later."
            } else {
                "Unable to complete request. Please try again."
            }
        case let .apiError(_, userMessage):
            userMessage ?? "Unable to connect to PagerDuty. Please check your token and connection."
        case let .networkError(_, userMessage):
            userMessage ?? "Network connection error. Please check your internet connection."
        case let .acknowledgmentFailed(message):
            message
        }
    }

    // For logging/debugging purposes only - never show to user
    var technicalDescription: String {
        switch self {
        case .invalidURL:
            "Invalid URL construction"
        case .noAPIToken:
            "No API token in Keychain"
        case .invalidResponse:
            "Invalid HTTP response"
        case .unauthorized:
            "HTTP 401 Unauthorized"
        case .rateLimited:
            "HTTP 429 Rate Limited"
        case let .serverError(statusCode):
            "HTTP \(statusCode) Server Error"
        case let .apiError(technicalMessage, _):
            "API Error: \(technicalMessage)"
        case let .networkError(error, _):
            "Network Error: \(error.localizedDescription)"
        case let .acknowledgmentFailed(message):
            "Acknowledgment Failed: \(message)"
        }
    }
}
