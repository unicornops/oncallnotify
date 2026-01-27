//
//  ServiceProvider.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation

/// Protocol defining the interface all service providers must implement
protocol ServiceProvider {
    /// The account this service provider is associated with
    var account: Account { get }

    /// Update the account information
    func updateAccount(_ newAccount: Account)

    /// Fetch incidents and on-call data for this service
    func fetchData() async throws -> AccountAlertSummary

    /// Acknowledge a specific incident
    func acknowledgeIncident(incidentId: String) async throws

    /// Test the connection to the service
    func testConnection() async -> Bool
}

/// Service provider factory
class ServiceProviderFactory {
    static func createProvider(for account: Account) -> ServiceProvider {
        switch account.serviceType {
        case .pagerDuty:
            return PagerDutyProvider(account: account)
        case .fireHydrant:
            return FireHydrantProvider(account: account)
        case .incidentIO:
            return IncidentIOProvider(account: account)
        case .betterStack:
            return BetterStackProvider(account: account)
        case .alertOps:
            return AlertOpsProvider(account: account)
        }
    }
}
