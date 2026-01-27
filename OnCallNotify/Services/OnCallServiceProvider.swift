//
//  OnCallServiceProvider.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation

/// Protocol that all on-call service providers must implement
/// This abstraction allows supporting multiple on-call services (PagerDuty, AlertOps, etc.)
protocol OnCallServiceProvider: AnyObject {
    /// The account this service is managing
    var account: Account { get }

    /// Fetch all data (incidents and on-call status) for this account
    /// - Returns: AccountAlertSummary containing aggregated data
    /// - Throws: OnCallError for API failures, authentication issues, etc.
    func fetchData() async throws -> AccountAlertSummary

    /// Acknowledge an incident
    /// - Parameter incidentId: The ID of the incident to acknowledge
    /// - Throws: OnCallError if acknowledgment fails
    func acknowledgeIncident(incidentId: String) async throws

    /// Test the API connection with the stored credentials
    /// - Returns: true if connection is successful, false otherwise
    func testConnection() async -> Bool

    /// Update the account information
    /// - Parameter newAccount: The updated account details
    func updateAccount(_ newAccount: Account)
}
