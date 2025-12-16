//
//  MenuView.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import SwiftUI

struct MenuView: View {
    @ObservedObject var service = OnCallService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // On-call status section
                    onCallStatusSection

                    Divider()

                    // Alert summary section
                    alertSummarySection

                    if !service.alertSummary.incidents.isEmpty {
                        Divider()

                        // Incidents list
                        incidentsSection
                    }
                }
                .padding()
            }

            Divider()

            // Footer with actions
            footerView
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "bell.fill")
                .font(.title2)
                .foregroundColor(service.alertSummary.isOnCall ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("OnCall Notify")
                    .font(.headline)

                if service.isLoading {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Updating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let error = service.lastError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else {
                    Text("Updated just now")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(
                action: {
                    service.refreshData()
                },
                label: {
                    Image(systemName: "arrow.clockwise")
                })
                .buttonStyle(.plain)
                .help("Refresh")
        }
        .padding()
    }

    // MARK: - On-Call Status

    private var onCallStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("On-Call Status", systemImage: "person.fill")
                .font(.headline)

            HStack {
                Circle()
                    .fill(service.alertSummary.isOnCall ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)

                Text(service.alertSummary.isOnCall ? "Currently On-Call" : "Not On-Call")
                    .font(.subheadline)

                Spacer()
            }

            if let nextShift = service.alertSummary.nextOnCallShift {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Next shift:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatNextShift(nextShift))
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Alert Summary

    private var alertSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Active Alerts", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)

            HStack(spacing: 20) {
                // Total alerts
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(service.alertSummary.totalAlerts)")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                // Unacknowledged
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(service.alertSummary.unacknowledgedCount)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                    Text("Unacknowledged")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                // Acknowledged
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(service.alertSummary.acknowledgedCount)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    Text("Acknowledged")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Incidents List

    private var incidentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Incidents", systemImage: "list.bullet")
                .font(.headline)

            ForEach(service.alertSummary.incidents.prefix(5)) { incident in
                IncidentRowView(incident: incident)
            }

            if service.alertSummary.incidents.count > 5 {
                Text("+ \(service.alertSummary.incidents.count - 5) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button(action: openPagerDutyWeb) {
                Label("Open PagerDuty", systemImage: "safari")
            }
            .buttonStyle(.link)

            Spacer()

            if #available(macOS 14.0, *) {
                SettingsLink {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .help("Settings")
            } else {
                Button(action: openSettings) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            Button(action: quitApp) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
        .padding()
    }

    // MARK: - Helper Methods

    private func formatNextShift(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        let components = calendar.dateComponents([.day, .hour, .minute], from: now, to: date)

        if let days = components.day, days > 0 {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if let hours = components.hour, hours > 0 {
            return "in \(hours)h \(components.minute ?? 0)m"
        } else if let minutes = components.minute, minutes > 0 {
            return "in \(minutes)m"
        } else {
            return "very soon"
        }
    }

    private func openPagerDutyWeb() {
        if let url = URL(string: "https://app.pagerduty.com/incidents") {
            NSWorkspace.shared.open(url)
        }
    }

    // Note: Currently supports PagerDuty, future versions will support additional services

    private func openSettings() {
        // For macOS 13.0+ use modern API, fallback to legacy for macOS 12 and earlier
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Incident Row View

struct IncidentRowView: View {
    let incident: Incident
    @State private var isAcknowledging = false
    @State private var acknowledgmentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(incident.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    // Service
                    if let service = incident.service {
                        Text(service.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Time
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(formatIncidentTime(incident.createdAt))
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)

                    // Error message
                    if let error = acknowledgmentError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    // Acknowledge button (only for triggered incidents)
                    if incident.status == .triggered {
                        Button(
                            action: {
                                acknowledgeIncident()
                            },
                            label: {
                                if isAcknowledging {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "checkmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            })
                            .buttonStyle(.plain)
                            .disabled(isAcknowledging)
                            .help("Acknowledge incident")
                    }

                    // Open button
                    if let urlString = incident.htmlUrl,
                       let url = URL(string: urlString) {
                        Button(
                            action: {
                                NSWorkspace.shared.open(url)
                            },
                            label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                            })
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var statusColor: Color {
        switch incident.status {
        case .triggered:
            .red
        case .acknowledged:
            .orange
        case .resolved:
            .green
        }
    }

    private func acknowledgeIncident() {
        isAcknowledging = true
        acknowledgmentError = nil

        Task {
            do {
                try await OnCallService.shared.acknowledgeIncident(incidentId: incident.id)
                // Success - the service will refresh and update the UI
            } catch {
                acknowledgmentError = error.localizedDescription
            }
            isAcknowledging = false
        }
    }

    private func formatIncidentTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return "Unknown"
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    MenuView()
}
