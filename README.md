# OnCall Notify

A native macOS status bar application for monitoring your on-call alerts and status across multiple services.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)
![License](https://img.shields.io/badge/license-GPLv3-blue.svg)
[![Build](https://github.com/unicornops/oncall-notify/actions/workflows/build.yml/badge.svg)](https://github.com/unicornops/oncall-notify/actions/workflows/build.yml)
[![CI](https://github.com/unicornops/oncall-notify/actions/workflows/ci.yml/badge.svg)](https://github.com/unicornops/oncall-notify/actions/workflows/ci.yml)

## Overview

OnCall Notify is your unified on-call status monitor for macOS. Currently supporting **PagerDuty** with
plans to add support for additional on-call and incident management platforms in future releases.

## Features

- 🔔 **Real-time Alert Monitoring**: Display current incidents directly in your menu bar
- 📊 **Alert Categorization**: Separate counts for acknowledged and unacknowledged alerts
- ✅ **Quick Acknowledge**: Acknowledge unacknowledged incidents with a single click
- 👤 **On-Call Status**: Visual indicator showing if you're currently on-call
- 📅 **Next Shift Information**: See when your next on-call shift starts
- 🔐 **Multi-Account Support**: Monitor multiple accounts across services simultaneously
- ▶️ **Full Demo Mode**: Explore the app without PagerDuty credentials or a paid account
- 🔒 **Secure Storage**: API tokens stored securely in macOS Keychain
- 🔄 **Auto-refresh**: Automatically updates every 60 seconds
- 🎨 **Native macOS UI**: Built with SwiftUI for a native look and feel
- ⚡ **Lightweight**: Minimal resource usage, lives in your menu bar
- 🔌 **Multi-Service Ready**: Architecture designed for easy addition of new services

## Supported Services

### Currently Supported

- ✅ **Demo Mode** - Full local walkthrough for App Store review and evaluation
- ✅ **PagerDuty** - Full support for incidents and on-call schedules

### Coming Soon

- 🚧 **Atlassian Compass** - Planned
- 🚧 **Atlassian Jira Service Management** - Planned
- 🚧 **VictorOps/Splunk On-Call** - Planned
- 🚧 **Alertmanager** - Planned
- 🚧 **Custom webhooks** - Planned

Want to see support for another service?
[Open an issue](https://github.com/unicornops/oncall-notify/issues) and let us know!

## Screenshots

### Status Bar Icon

The app displays a bell icon in your menu bar with:

- Filled bell when on-call
- Red color for unacknowledged alerts
- Orange color for acknowledged alerts
- Blue color when on-call with no alerts
- Alert count badge

### Menu Popover

Click the menu bar icon to see:

- Current on-call status
- Next on-call shift time
- Alert summary (total, unacknowledged, acknowledged)
- List of recent incidents with quick links
- One-click acknowledge button for unacknowledged incidents
- Refresh button for manual updates

### Settings Window

Manage your accounts with:

- Add multiple accounts per service type
- Enable/disable accounts individually
- Test connection for each account
- Secure token input and storage
- Account management (add, edit, delete)

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for building)
- Optional: PagerDuty account and API token for live data

## Installation

### Option 1: Build from Source

1. Clone the repository:

```bash
git clone https://github.com/unicornops/oncall-notify.git
cd oncall-notify
```

2. Open the Xcode project:

```bash
open OnCallNotify.xcodeproj
```

3. Build and run the application:
   - Select "OnCallNotify" scheme
   - Press `Cmd + R` to build and run
   - Or press `Cmd + B` to build only

4. The app will appear in your menu bar

### Option 2: Download Release (Coming Soon)

Pre-built releases will be available in the GitHub Releases section.

## Configuration

### Getting Your PagerDuty API Token

1. Log in to your PagerDuty account
2. Go to **User Settings** → **User Settings**
3. Navigate to **API Access Keys** tab
4. Click **Create API User Token**
5. Give it a description (e.g., "OnCall Notify macOS App")
6. Copy the generated token

### Setting Up the App

1. Launch OnCall Notify (it will appear in your menu bar)
2. Click the menu bar icon
3. Click the gear icon (⚙️) to open Settings
4. Use the seeded **App Store Demo** account for an immediate walkthrough, or click "Add Account"
5. Enter a friendly name for the account (e.g., "Work PagerDuty")
6. Select the service type (`Demo Mode` or `PagerDuty`)
7. If you selected PagerDuty, paste your API token
8. Click "Add Account"
9. Test the connection using the network icon
10. Add additional accounts as needed by repeating steps 4-9

The app will now automatically fetch and display your alerts and on-call status from all enabled accounts.

## Demo Mode

On first launch, OnCall Notify creates a default **App Store Demo** account so the app is usable without
external credentials. Demo Mode is intended for:

- App Store review
- Product evaluation before connecting PagerDuty
- UI and notification testing without touching a live incident system

Demo Mode includes:

- Local sample incidents with triggered and acknowledged states
- On-call and next-shift examples
- Working acknowledge actions
- Scenario switching from both the menu bar popover and Settings
- No network sign-in requirement

### App Review Flow

1. Launch the app and click the menu bar icon.
2. Verify the seeded **App Store Demo** account loads automatically.
3. Use the **Demo Mode** section in the popover to switch scenarios.
4. Review active alerts, on-call state, next shift, and acknowledge actions.
5. Open **Settings** to confirm demo mode is available without credentials.

### Managing Multiple Accounts

- **Add Account**: Click "Add Account" to add additional accounts
- **Enable/Disable**: Click the checkmark icon to enable or disable an account
- **Test Connection**: Click the network icon to verify the account credentials
- **Delete Account**: Click the trash icon to remove an account
- **Account Badges**: Incidents in the menu show which account they belong to

## Usage

### Menu Bar Icon

The icon in your menu bar provides at-a-glance information:

- **Bell Icon**:
  - Outline: Not currently on-call
  - Filled: Currently on-call

- **Icon Color**:
  - Red: Unacknowledged alerts present
  - Orange: Only acknowledged alerts
  - Blue: On-call with no alerts
  - Gray: Not on-call, no alerts

- **Number Badge**: Total count of active alerts

### Popover Menu

Click the menu bar icon to see detailed information:

- **On-Call Status**: Green dot when on-call, gray when not
- **Next Shift**: Displays when your next on-call shift begins
- **Alert Summary**: Total, unacknowledged, and acknowledged counts
- **Recent Incidents**: List of up to 5 most recent incidents
  - Click the arrow icon to open the incident in your browser
  - Shows incident title, service, and time created

### Keyboard Shortcuts

- **Refresh Data**: Click the refresh icon in the popover
- **Open Settings**: Click the gear icon
- **Quit App**: Click the X icon in the popover

## API Integration

### PagerDuty

The application uses the following PagerDuty API v2 endpoints:

- `GET /users/me` - Get current user information
- `GET /incidents` - Fetch active incidents (triggered and acknowledged)
- `GET /oncalls` - Fetch current on-call schedule information

## Security

### Current Security Features

- ✅ API tokens are stored securely in the macOS Keychain
- ✅ All API requests use HTTPS
- ✅ No data is sent to any third-party services
- ✅ Each service's credentials are isolated in the Keychain
- ✅ Hardened Runtime enabled
- ✅ No third-party dependencies (reduced supply chain risk)

### Reporting Security Issues

If you discover a security vulnerability, please report it responsibly:

- **DO NOT** open a public GitHub issue
- Use GitHub Security Advisories for private reporting
- Or email: <rob@unicornops.ie>

We take security seriously and will respond promptly to all reports.

## Troubleshooting

### App doesn't show any data

1. Check that you've entered a valid API token in Settings
2. Click "Test Connection" to verify the token
3. Check your internet connection
4. Verify your account has active incidents or on-call schedules

### Connection test fails

- Verify the API token is correct
- Check that the token hasn't been revoked
- Ensure you have network access to the service API
- Check firewall or VPN settings

### Menu bar icon doesn't appear

- Make sure the app is running (check Activity Monitor)
- Try quitting and restarting the app
- Check that you haven't hidden menu bar icons in macOS settings

### App uses too much CPU/Memory

- The app refreshes every 60 seconds by default
- Each refresh makes 2-3 API calls
- If you have hundreds of incidents, consider filtering in your service first

## Development

### Project Structure

```text
OnCallNotify/
├── OnCallNotifyApp.swift      # App entry point
├── StatusBarController.swift   # Menu bar icon and popover controller
├── Info.plist                  # App configuration
├── Models/
│   └── Models.swift           # Data models for API responses
├── Services/
│   ├── OnCallService.swift    # API service layer (currently PagerDuty)
│   └── KeychainHelper.swift   # Secure storage
├── Views/
│   ├── MenuView.swift         # Popover menu UI
│   └── SettingsView.swift     # Settings window UI
└── Assets.xcassets/           # App icons and assets

Documentation/
├── README.md                  # This file - main documentation
├── AGENTS.md                  # AI coding agent guidelines
├── QUICKSTART.md              # 5-minute setup guide
├── FEATURES.md                # Detailed feature documentation
├── TROUBLESHOOTING.md         # Problem-solving guide
├── CONTRIBUTING.md            # Contribution guidelines
├── PROJECT_OVERVIEW.md        # Complete project summary
└── CHANGELOG.md               # Version history
```

### Building

```bash
# Build for debugging
xcodebuild -project OnCallNotify.xcodeproj -scheme OnCallNotify -configuration Debug

# Build for release
xcodebuild -project OnCallNotify.xcodeproj -scheme OnCallNotify -configuration Release

# Use the build script
./build.sh           # Builds Release by default
./build.sh Debug     # Builds Debug configuration
```

### Code Quality and Pre-commit Hooks

This project uses pre-commit hooks to maintain code quality:

```bash
# Install pre-commit (one-time)
pip install pre-commit
# or
brew install pre-commit

# Set up the hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

**What gets checked:**

- File quality (whitespace, EOF newlines)
- Swift syntax and linting (SwiftLint)
- YAML/JSON/XML validation
- Markdown formatting
- Secret detection
- Shell script validation

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Read [AGENTS.md](AGENTS.md) for AI coding agent guidelines
3. Create your feature branch (`git checkout -b feature/amazing-feature`)
4. Commit your changes (`git commit -m 'Add some amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

#### Adding Support for New Services

We welcome contributions to add support for additional on-call and incident management platforms! The
codebase is designed with extensibility in mind. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on
adding new service integrations.

## Roadmap

### Near Term

- [ ] Customizable refresh interval
- [ ] Desktop notifications for new incidents
- [ ] Incident acknowledgment from the app
- [ ] Dark mode optimizations

### Future Services

- [ ] Atlassian Compass integration
- [ ] Atlassian Jira Service Management integration
- [ ] VictorOps/Splunk On-Call integration
- [ ] Alertmanager integration
- [ ] Support for multiple accounts across services
- [ ] Custom webhook support

### Advanced Features

- [ ] Customizable alert filtering
- [ ] Historical incident view
- [ ] Export incident data
- [ ] Configurable keyboard shortcuts
- [ ] Multi-team support

## License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.

## Acknowledgments

- Built with SwiftUI and macOS AppKit
- Currently integrates with PagerDuty REST API v2
- Inspired by the need for unified on-call status visibility across multiple platforms

## Documentation

This project includes comprehensive documentation:

- **[README.md](README.md)** - You are here! Main documentation and overview
- **[AGENTS.md](AGENTS.md)** - Guidelines for AI coding agents (follows [agents.md](https://agents.md/) format)
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development and contribution guidelines
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and release notes

## Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/unicornops/oncall-notify/issues) page
2. Create a new issue with details about your problem
3. Include macOS version, app version, and steps to reproduce

## Privacy

This application:

- Only communicates with official APIs of configured services
- Does not collect or transmit any user data to third parties
- Stores API tokens locally in macOS Keychain
- Does not include any analytics or tracking

---

Made with ❤️ for on-call engineers everywhere
