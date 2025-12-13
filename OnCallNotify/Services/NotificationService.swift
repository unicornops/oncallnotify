//
//  NotificationService.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import Foundation
import UserNotifications
import os.log

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    private var previousAlertSummary: AlertSummary?
    private var previousIncidentIds: Set<String> = []
    private var notificationsEnabled = false
    
    private static let logger = Logger(subsystem: "com.oncall.notify", category: "notifications")
    
    private init() {
        Task {
            await requestNotificationPermissions()
        }
    }
    
    // MARK: - Permission Management
    
    func requestNotificationPermissions() async {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsEnabled = granted
            
            if granted {
                Self.logger.info("Notification permissions granted")
            } else {
                Self.logger.warning("Notification permissions denied")
            }
        } catch {
            Self.logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            notificationsEnabled = false
        }
    }
    
    func checkNotificationPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
        return notificationsEnabled
    }
    
    // MARK: - Alert Detection
    
    func processAlertChanges(currentSummary: AlertSummary) {
        guard notificationsEnabled else { return }
        
        // First time initialization
        if previousAlertSummary == nil {
            previousAlertSummary = currentSummary
            previousIncidentIds = Set(currentSummary.incidents.map { $0.id })
            return
        }
        
        // Check for on-call status changes
        if let previous = previousAlertSummary {
            if previous.isOnCall != currentSummary.isOnCall {
                notifyOnCallStatusChange(isNowOnCall: currentSummary.isOnCall)
            }
        }
        
        // Check for new incidents
        let currentIncidentIds = Set(currentSummary.incidents.map { $0.id })
        let newIncidentIds = currentIncidentIds.subtracting(previousIncidentIds)
        
        for incidentId in newIncidentIds {
            if let incident = currentSummary.incidents.first(where: { $0.id == incidentId }) {
                notifyNewIncident(incident)
            }
        }
        
        // Check for incident status changes
        for incident in currentSummary.incidents {
            if let previousIncident = previousAlertSummary?.incidents.first(where: { $0.id == incident.id }) {
                if previousIncident.status != incident.status {
                    notifyIncidentStatusChange(incident, from: previousIncident.status, to: incident.status)
                }
            }
        }
        
        // Update state for next comparison
        previousAlertSummary = currentSummary
        previousIncidentIds = currentIncidentIds
    }
    
    // MARK: - Notification Sending
    
    private func notifyNewIncident(_ incident: Incident) {
        let content = UNMutableNotificationContent()
        content.title = "New Alert"
        content.body = incident.title
        content.sound = .default
        
        // Add urgency to subtitle with proper formatting
        let urgencyDisplay: String
        switch incident.urgency.lowercased() {
        case "high":
            urgencyDisplay = "High"
        case "low":
            urgencyDisplay = "Low"
        default:
            // Handle any unexpected urgency values
            urgencyDisplay = incident.urgency.capitalized
        }
        content.subtitle = "Urgency: \(urgencyDisplay)"
        
        // Add incident URL to userInfo for potential future action handling
        if let url = incident.htmlUrl {
            content.userInfo = ["url": url, "incidentId": incident.id]
        }
        
        let request = UNNotificationRequest(
            identifier: "incident-\(incident.id)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.error("Failed to send new incident notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Sent notification for new incident: \(incident.id)")
            }
        }
    }
    
    private func notifyIncidentStatusChange(_ incident: Incident, from oldStatus: IncidentStatus, to newStatus: IncidentStatus) {
        let content = UNMutableNotificationContent()
        
        switch newStatus {
        case .acknowledged:
            content.title = "Alert Acknowledged"
            content.body = incident.title
            content.subtitle = "Status changed to acknowledged"
        case .resolved:
            content.title = "Alert Resolved"
            content.body = incident.title
            content.subtitle = "Status changed to resolved"
        case .triggered:
            // Shouldn't happen (going back to triggered), but handle it
            content.title = "Alert Re-triggered"
            content.body = incident.title
            content.subtitle = "Status changed back to triggered"
        }
        
        content.sound = .default
        
        if let url = incident.htmlUrl {
            content.userInfo = ["url": url, "incidentId": incident.id]
        }
        
        let request = UNNotificationRequest(
            identifier: "incident-status-\(incident.id)-\(newStatus.rawValue)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.error("Failed to send status change notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Sent notification for incident status change: \(incident.id) -> \(newStatus.rawValue)")
            }
        }
    }
    
    private func notifyOnCallStatusChange(isNowOnCall: Bool) {
        let content = UNMutableNotificationContent()
        
        if isNowOnCall {
            content.title = "Now On-Call"
            content.body = "You are now on-call"
            content.sound = .default
        } else {
            content.title = "No Longer On-Call"
            content.body = "Your on-call shift has ended"
            content.sound = .default
        }
        
        let request = UNNotificationRequest(
            identifier: "oncall-status-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.error("Failed to send on-call status notification: \(error.localizedDescription)")
            } else {
                Self.logger.info("Sent notification for on-call status change: \(isNowOnCall)")
            }
        }
    }
    
    // MARK: - Utility Methods
    
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        Self.logger.info("Cleared all delivered notifications")
    }
    
    func resetState() {
        previousAlertSummary = nil
        previousIncidentIds = []
        Self.logger.info("Reset notification state")
    }
}
