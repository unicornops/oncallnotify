//
//  StatusBarController.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import AppKit
import SwiftUI
import Combine

// MARK: - Custom Hosting Controller

class PopoverHostingController: NSViewController {
    private let rootView: MenuView

    init(rootView: MenuView) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.view = hostingView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.setFrameSize(NSSize(width: 400, height: 500))
    }
}

// MARK: - Status Bar Controller

@MainActor
class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupStatusItem()
        setupPopover()
        observeAlertChanges()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusBarButton()
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = false

        // Create the view controller once during setup
        let menuViewController = PopoverHostingController(rootView: MenuView())
        popover?.contentViewController = menuViewController
    }

    private func observeAlertChanges() {
        OnCallService.shared.$alertSummary
            .sink { [weak self] _ in
                self?.updateStatusBarButton()
            }
            .store(in: &cancellables)
    }

    // MARK: - Update Status Bar

    private func updateStatusBarButton() {
        guard let button = statusItem?.button else { return }

        let summary = OnCallService.shared.alertSummary

        // Create attributed string with icon and counts
        let attributedTitle = NSMutableAttributedString()

        // Add icon
        let iconAttachment = NSTextAttachment()
        let iconImage: NSImage

        if summary.isOnCall {
            guard let image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "On Call") else {
                return
            }
            iconImage = image
        } else {
            guard let image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Not On Call") else {
                return
            }
            iconImage = image
        }

        // Set icon color based on alert status
        let iconColor: NSColor
        if summary.unacknowledgedCount > 0 {
            iconColor = .systemRed
        } else if summary.acknowledgedCount > 0 {
            iconColor = .systemOrange
        } else if summary.isOnCall {
            iconColor = .systemBlue
        } else {
            iconColor = .controlTextColor
        }

        iconImage.isTemplate = true
        iconAttachment.image = iconImage.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        )

        let iconString = NSAttributedString(attachment: iconAttachment)
        attributedTitle.append(iconString)

        // Add counts if there are any alerts
        if summary.totalAlerts > 0 {
            let countString = NSMutableAttributedString(string: " \(summary.totalAlerts)")
            countString.addAttribute(.foregroundColor, value: iconColor, range: NSRange(location: 0, length: countString.length))
            countString.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), range: NSRange(location: 0, length: countString.length))
            attributedTitle.append(countString)
        }

        button.attributedTitle = attributedTitle

        // Set tooltip
        var tooltipParts: [String] = []

        if summary.isOnCall {
            tooltipParts.append("Currently On-Call")
        }

        if summary.totalAlerts > 0 {
            tooltipParts.append("\(summary.totalAlerts) total alert\(summary.totalAlerts == 1 ? "" : "s")")

            if summary.unacknowledgedCount > 0 {
                tooltipParts.append("\(summary.unacknowledgedCount) unacknowledged")
            }

            if summary.acknowledgedCount > 0 {
                tooltipParts.append("\(summary.acknowledgedCount) acknowledged")
            }
        } else {
            tooltipParts.append("No active alerts")
        }

        button.toolTip = tooltipParts.joined(separator: "\n")
    }

    // MARK: - Popover Actions

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Refresh data when opening
            OnCallService.shared.refreshData()
        }
    }
}
