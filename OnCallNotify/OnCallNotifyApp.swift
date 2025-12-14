//
//  OnCallNotifyApp.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//

import SwiftUI

@main
struct OnCallNotifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        // Request notification permission
        Task {
            await NotificationService.shared.requestPermission()
        }
    }
}
