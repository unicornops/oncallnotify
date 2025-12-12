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

    enum CodingKeys: String, CodingKey {
        case id, type, summary, status, urgency, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlUrl = "html_url"
        case incidentNumber = "incident_number"
        case service, assignments, acknowledgements
        case lastStatusChangeAt = "last_status_change_at"
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

// MARK: - App State Models

struct AlertSummary {
    var totalAlerts: Int
    var acknowledgedCount: Int
    var unacknowledgedCount: Int
    var isOnCall: Bool
    var nextOnCallShift: Date?
    var incidents: [Incident]

    init() {
        self.totalAlerts = 0
        self.acknowledgedCount = 0
        self.unacknowledgedCount = 0
        self.isOnCall = false
        self.nextOnCallShift = nil
        self.incidents = []
    }
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

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Configuration error. Please check your settings."
        case .noAPIToken:
            return "No API token found. Please configure in Settings."
        case .invalidResponse:
            return "Unable to process server response. Please try again."
        case .unauthorized:
            return "Authentication failed. Please verify your API token in Settings."
        case .rateLimited:
            return "Too many requests. Please wait a few minutes and try again."
        case .serverError(let statusCode):
            if statusCode >= 500 {
                return "Server is temporarily unavailable. Please try again later."
            } else {
                return "Unable to complete request. Please try again."
            }
        case .apiError(_, let userMessage):
            return userMessage ?? "Unable to connect to PagerDuty. Please check your token and connection."
        case .networkError(_, let userMessage):
            return userMessage ?? "Network connection error. Please check your internet connection."
        }
    }

    // For logging/debugging purposes only - never show to user
    var technicalDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL construction"
        case .noAPIToken:
            return "No API token in Keychain"
        case .invalidResponse:
            return "Invalid HTTP response"
        case .unauthorized:
            return "HTTP 401 Unauthorized"
        case .rateLimited:
            return "HTTP 429 Rate Limited"
        case .serverError(let statusCode):
            return "HTTP \(statusCode) Server Error"
        case .apiError(let technicalMessage, _):
            return "API Error: \(technicalMessage)"
        case .networkError(let error, _):
            return "Network Error: \(error.localizedDescription)"
        }
    }
}
