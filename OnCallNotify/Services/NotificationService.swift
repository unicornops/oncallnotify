//
//  NotificationService.swift
//  OnCallNotify
//
//  Handles macOS native notifications for incidents and on-call status changes
//

import AppKit
import Foundation
import OSLog
import UserNotifications

class NotificationService: NSObject {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var notificationPermissionGranted = false
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.oncall.notify",
        category: "NotificationService"
    )

    // Cached DateFormatter for performance (DateFormatter initialization is expensive)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Request notification permission from the user
    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationPermissionGranted = granted

            if granted {
                Self.logger.info("Notification permission granted")
            } else {
                Self.logger.warning("Notification permission denied")
            }
        } catch {
            Self.logger.error("Error requesting notification permission: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Send notification for a new incident
    func sendIncidentNotification(incident: Incident) {
        guard notificationPermissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "New PagerDuty Incident"
        content.body = incident.title
        content.sound = .default

        // Add incident details
        var subtitle = "Status: \(incident.status.rawValue.capitalized)"
        if let service = incident.service {
            subtitle += " • \(service.summary)"
        }
        content.subtitle = subtitle

        // Add URL if available
        if let urlString = incident.htmlUrl {
            content.userInfo = ["url": urlString]
        }

        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: "incident-\(incident.id)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        center.add(request) { error in
            if let error = error {
                Self.logger.error("Error sending incident notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Send notification for an acknowledged incident
    func sendIncidentAcknowledgedNotification(incident: Incident) {
        guard notificationPermissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Incident Acknowledged"
        content.body = incident.title
        content.sound = nil  // Silent notification for acknowledgments

        if let service = incident.service {
            content.subtitle = service.summary
        }

        let request = UNNotificationRequest(
            identifier: "incident-ack-\(incident.id)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                Self.logger.error("Error sending acknowledgment notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Send notification for a resolved incident
    func sendIncidentResolvedNotification(incident: Incident) {
        guard notificationPermissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Incident Resolved"
        content.body = incident.title
        content.sound = nil  // Silent notification for resolutions

        if let service = incident.service {
            content.subtitle = service.summary
        }

        let request = UNNotificationRequest(
            identifier: "incident-resolved-\(incident.id)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                Self.logger.error("Error sending resolution notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Send notification when going on-call
    func sendOnCallStartNotification(nextShift: Date?) {
        guard notificationPermissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "You Are Now On-Call"
        content.sound = .default

        if let nextShift = nextShift {
            content.body = "Your on-call shift has started"
            content.subtitle = "Next shift: \(Self.dateFormatter.string(from: nextShift))"
        } else {
            content.body = "Your on-call shift has started"
        }

        let request = UNNotificationRequest(
            identifier: "oncall-start",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                Self.logger.error("Error sending on-call start notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Send notification when going off-call
    func sendOnCallEndNotification(nextShift: Date?) {
        guard notificationPermissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "On-Call Shift Ended"
        content.body = "You are no longer on-call"
        content.sound = nil  // Silent notification for shift end

        if let nextShift = nextShift {
            content.subtitle = "Next shift: \(Self.dateFormatter.string(from: nextShift))"
        }

        let request = UNNotificationRequest(
            identifier: "oncall-end",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                Self.logger.error("Error sending on-call end notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Remove all delivered notifications
    func removeAllNotifications() {
        center.removeAllDeliveredNotifications()
    }

    /// Remove specific incident notification
    func removeIncidentNotification(incidentId: String) {
        center.removeDeliveredNotifications(withIdentifiers: [
            "incident-\(incidentId)",
            "incident-ack-\(incidentId)",
            "incident-resolved-\(incidentId)"
        ])
    }

    /// Remove on-call start notification
    func removeOnCallStartNotification() {
        center.removeDeliveredNotifications(withIdentifiers: ["oncall-start"])
    }

    /// Remove on-call end notification
    func removeOnCallEndNotification() {
        center.removeDeliveredNotifications(withIdentifiers: ["oncall-end"])
    }

    /// Remove all on-call notifications
    func removeAllOnCallNotifications() {
        center.removeDeliveredNotifications(withIdentifiers: ["oncall-start", "oncall-end"])
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationService: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification interaction (user clicked on notification)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Open incident URL if available
        // Note: We allow both HTTP and HTTPS URLs. While HTTPS is preferred for security,
        // some internal/self-hosted incident management tools may use HTTP within secure
        // corporate networks. Since the user explicitly configured and trusts this service,
        // we trust URLs provided by it.
        if let urlString = userInfo["url"] as? String,
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http" {
            Self.logger.info("Opening incident URL from notification: \(scheme, privacy: .public)://...")
            NSWorkspace.shared.open(url)
        } else if let urlString = userInfo["url"] as? String {
            Self.logger.warning("Ignoring notification URL with invalid or missing scheme: \(urlString, privacy: .public)")
        }

        completionHandler()
    }
}
