//
//  MenuView.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import SwiftUI

struct MenuView: View {
    @ObservedObject var service = OnCallService.shared

    private var demoAccount: Account? {
        service.primaryDemoAccount()
    }

    private var liveAccount: Account? {
        service.primaryLiveAccount()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let demoAccount {
                        demoModeSection(account: demoAccount)
                        Divider()
                    }

                    onCallStatusSection

                    Divider()

                    alertSummarySection

                    if !service.alertSummary.incidents.isEmpty {
                        Divider()
                        incidentsSection
                    }
                }
                .padding()
            }

            Divider()

            footerView
        }
        .frame(width: 420, height: 540)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: service.alertSummary.isOnCall ? "bell.fill" : "bell")
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
                        .lineLimit(2)
                } else if let demoAccount,
                          let configuration = service.demoConfiguration(for: demoAccount.id) {
                    Text("Demo Mode • \(configuration.selectedScenario.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Updated just now")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                service.refreshData(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding()
    }

    // MARK: - Demo Mode

    private func demoModeSection(account: Account) -> some View {
        let configuration = service.demoConfiguration(for: account.id) ?? DemoConfiguration()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Demo Mode", systemImage: "play.square.fill")
                    .font(.headline)
                    .foregroundColor(.blue)

                Spacer()

                Text(account.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(
                "This demo runs without PagerDuty credentials and exercises the same " +
                    "menu, refresh, on-call, and acknowledge flows used by live accounts."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Picker("Scenario", selection: demoScenarioBinding(for: account.id)) {
                ForEach(DemoScenario.allCases) { scenario in
                    Text(scenario.displayName).tag(scenario)
                }
            }
            .pickerStyle(.menu)

            Text(configuration.selectedScenario.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    service.resetDemoScenario(for: account.id)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    service.advanceDemoScenario(for: account.id)
                } label: {
                    Label("Next Scenario", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.07))
        )
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
            HStack {
                Label("Active Alerts", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)

                Spacer()

                if service.alertSummary.unacknowledgedCount > 0 {
                    AcknowledgeAllButton()
                }
            }

            HStack(spacing: 20) {
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
            if liveAccount != nil || demoAccount != nil {
                Button(action: openDashboard) {
                    Label(footerButtonTitle, systemImage: "safari")
                }
                .buttonStyle(.link)
            }

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

    private func demoScenarioBinding(for accountId: String) -> Binding<DemoScenario> {
        Binding(
            get: {
                service.demoConfiguration(for: accountId)?.selectedScenario ?? .reviewOverview
            },
            set: { scenario in
                service.setDemoScenario(scenario, for: accountId)
            }
        )
    }

    private var footerButtonTitle: String {
        if liveAccount != nil {
            return "Open PagerDuty"
        }

        return "Demo Guide"
    }

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

    private func openDashboard() {
        let urlString: String
        if liveAccount != nil {
            urlString = "https://app.pagerduty.com/incidents"
        } else {
            urlString = "https://github.com/unicornops/oncall-notify#demo-mode"
        }

        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func openSettings() {
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

// MARK: - Acknowledge All Button

struct AcknowledgeAllButton: View {
    @ObservedObject var service = OnCallService.shared
    @State private var isAcknowledging = false
    @State private var acknowledgmentError: String?

    var body: some View {
        Button {
            acknowledgeAll()
        } label: {
            if isAcknowledging {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text("Acknowledging...")
                        .font(.caption)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text("Acknowledge All")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(.orange)
        .disabled(isAcknowledging)
        .help("Acknowledge all unacknowledged incidents")
    }

    private func acknowledgeAll() {
        isAcknowledging = true
        acknowledgmentError = nil

        Task {
            do {
                try await service.acknowledgeAllIncidents()
            } catch {
                acknowledgmentError = error.localizedDescription
            }
            isAcknowledging = false
        }
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
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(incident.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        if let service = incident.service {
                            Text(service.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let accountId = incident.accountId,
                           let account = getAccount(for: accountId) {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(account.name)
                                .font(.caption)
                                .foregroundColor(account.isDemoAccount ? .blue : .primary)
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(formatIncidentTime(incident.createdAt))
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)

                    if let error = acknowledgmentError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if incident.status == .triggered {
                        Button {
                            acknowledgeIncident()
                        } label: {
                            if isAcknowledging {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isAcknowledging)
                        .help("Acknowledge incident")
                    }

                    if let urlString = incident.htmlUrl,
                       let url = URL(string: urlString) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
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
        guard let accountId = incident.accountId else {
            acknowledgmentError = "Unable to identify account for this incident"
            return
        }

        isAcknowledging = true
        acknowledgmentError = nil

        Task {
            do {
                try await OnCallService.shared.acknowledgeIncident(
                    incidentId: incident.id,
                    accountId: accountId
                )
            } catch {
                acknowledgmentError = error.localizedDescription
            }
            isAcknowledging = false
        }
    }

    private func getAccount(for accountId: String) -> Account? {
        KeychainHelper.shared.getAccounts().first { $0.id == accountId }
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
