# AGENTS.md

This file provides guidance for AI coding agents working on the OnCall Notify macOS application.

## Project Overview

OnCall Notify is a native macOS status bar application written in Swift that monitors on-call alerts and status across multiple incident management services. Currently supporting **PagerDuty** with architecture designed for easy addition of more services. It uses SwiftUI for the UI, AppKit for menu bar integration, and the macOS Keychain for secure credential storage.

**Key Facts:**
- Language: Swift 5.0
- UI Framework: SwiftUI + AppKit
- Target: macOS 13.0+ (Ventura and later)
- Architecture: MVVM pattern with service abstraction layer
- No external dependencies (pure Swift)
- Total LOC: ~1,300 lines across 7 Swift files
- **Current Services**: PagerDuty
- **Planned Services**: Opsgenie, VictorOps, Alertmanager, Custom Webhooks

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Actions                             │
│  (Menu Bar Click, Settings Update, Manual Refresh)              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   StatusBarController                           │
│  • Manages menu bar icon and popover                            │
│  • Observes OnCallService changes via Combine                   │
│  • Updates icon color, badge, tooltip                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   OnCallService                                 │
│  • Fetches data from API every 60 seconds                       │
│  • Processes incidents and on-call schedules                    │
│  • Updates @Published alertSummary                              │
│  • Sends updates to NotificationService                         │
│  • Currently: PagerDuty implementation                          │
│  • Future: Multi-service abstraction                            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                   ┌─────────┴─────────┬───────────────────┐
                   │                   │                   │
                   ▼                   ▼                   ▼
        ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
        │  KeychainHelper  │  │  PagerDuty API   │  │ Notification     │
        │  • Get API token │  │  • GET /users/me │  │ Service          │
        │  • Secure storage│  │  • GET /incidents│  │ • Detects changes│
        │  • Service: com. │  │  • GET /oncalls  │  │ • Sends macOS    │
        │    oncall.notify │  └──────────────────┘  │   notifications  │
        └──────────────────┘           │            └──────────────────┘
                                       ▼
                              ┌──────────────────┐
                              │   Models.swift   │
                              │  • Incident      │
                              │  • Oncall        │
                              │  • AlertSummary  │
                              └──────────────────┘
                                       │
                                       ▼
                              ┌──────────────────┐
                              │   MenuView.swift │
                              │  • Displays data │
                              │  • SwiftUI UI    │
                              └──────────────────┘
```

## Build and Development Commands

### Building
```bash
# Open in Xcode
open OnCallNotify.xcodeproj

# Build using Xcode (press ⌘B in Xcode)
# Or build from command line:
xcodebuild -project OnCallNotify.xcodeproj -scheme OnCallNotify -configuration Debug build

# Build for release
xcodebuild -project OnCallNotify.xcodeproj -scheme OnCallNotify -configuration Release build

# Using the build script
./build.sh           # Builds Release by default
./build.sh Debug     # Builds Debug configuration
```

### Running
```bash
# Run in Xcode (press ⌘R)
# Or run built app:
open build/Release/OnCallNotify.app
```

### Cleaning
```bash
# Clean in Xcode: Product → Clean Build Folder (⇧⌘K)
# Or from command line:
rm -rf build/
rm -rf ~/Library/Developer/Xcode/DerivedData/OnCallNotify-*
```

## Project Structure

```
OnCallNotify/
├── OnCallNotifyApp.swift         # App entry point, AppDelegate setup
├── StatusBarController.swift     # Menu bar icon, popover management, UI updates
├── Info.plist                    # App configuration (bundle ID, minimum OS, etc.)
├── Models/
│   └── Models.swift              # All data models: Incident, Oncall, User, etc.
├── Services/
│   ├── OnCallService.swift       # Service abstraction layer (currently PagerDuty)
│   ├── NotificationService.swift # Native macOS notification management
│   └── KeychainHelper.swift      # Secure API token storage in macOS Keychain
├── Views/
│   ├── MenuView.swift            # Popover menu UI with alerts and on-call status
│   └── SettingsView.swift        # Settings window for API token configuration
└── Assets.xcassets/              # App icons and color assets
```

## Code Style and Conventions

### Swift Style
- **Indentation**: 4 spaces (no tabs)
- **Line length**: Aim for 100 characters, max 120
- **Naming**: Use clear, descriptive names following Swift API Design Guidelines
- **Access control**: Use `private` for internal implementation details
- **Optional handling**: Prefer `guard let` over `if let` for early returns
- **NO force unwraps**: Always handle optionals safely with `?`, `??`, or `guard`

### SwiftUI Conventions
- Use `@State` for view-local state
- Use `@ObservedObject` for shared observable objects
- Use `@Published` in ObservableObject classes for reactive properties
- Keep views focused and composable
- Extract complex views into separate components
- Use `@MainActor` when needed for UI updates
- Use `SettingsLink` for opening Settings (macOS 14.0+), with fallback for macOS 13.0

### Architecture Patterns
- **MVVM**: Models (data), Views (UI), ViewModels/Services (business logic)
- **Reactive**: Use Combine's `@Published` and `.sink()` for data flow
- **Async/Await**: Use modern concurrency for all API calls
- **Single Responsibility**: Each file/class should have one clear purpose
- **Service Abstraction**: Design for multi-service support from the start

### Naming Conventions
- Classes/Structs: `PascalCase` (e.g., `OnCallService`)
- Functions/Variables: `camelCase` (e.g., `fetchIncidents`)
- Constants: `camelCase` (e.g., `baseURL`)
- Enum cases: `camelCase` (e.g., `.triggered`, `.acknowledged`)

## API Integration Details

### PagerDuty REST API v2 (Current)
- Base URL: `https://api.pagerduty.com`
- Authentication: Bearer token in `Authorization` header format: `Token token=YOUR_TOKEN`
- All requests require: `Accept: application/json` and `Content-Type: application/json` headers

### Endpoints Used
1. `GET /users/me` - Get current user info (cached after first fetch)
2. `GET /incidents` - Fetch incidents with filters: `statuses[]=triggered&statuses[]=acknowledged&user_ids[]=<user_id>&limit=100`
3. `GET /oncalls` - Fetch on-call schedules with `user_ids[]=<user_id>&include[]=users&include[]=schedules`

### Data Models
- All API responses use `Codable` for JSON parsing
- Use `ISO8601DateFormatter` for date/time parsing
- CodingKeys map snake_case (API) to camelCase (Swift)
- Models prefixed with `PagerDuty` for service-specific responses
- Generic models like `AlertSummary` are service-agnostic

### Future Service Integration Guidelines
When adding new services:
1. Create service-specific response models (e.g., `OpsgenieIncidentsResponse`)
2. Map to common internal models (`Incident`, `Oncall`, `AlertSummary`)
3. Consider creating a protocol for service abstraction
4. Use separate Keychain entries per service
5. Maintain backward compatibility with existing PagerDuty integration

## Testing Instructions

### Manual Testing Checklist
Before committing changes, verify:
- [ ] Menu bar icon appears and updates correctly
- [ ] Icon color changes based on alert status (red/orange/blue/gray)
- [ ] Badge shows correct alert count
- [ ] Popover opens and displays all sections
- [ ] Settings window opens via gear icon
- [ ] API token can be saved to Keychain
- [ ] Test Connection button works with valid token
- [ ] Auto-refresh works (wait 60+ seconds)
- [ ] On-call status displays correctly
- [ ] Incidents list shows recent alerts
- [ ] Error states display user-friendly messages
- [ ] App quits cleanly without crashes

### Test with Different States
- No API token configured
- Invalid API token
- Valid token but no incidents
- Multiple incidents (both triggered and acknowledged)
- Currently on-call vs not on-call
- Network disconnection (test error handling)

### Console Logging
Check Console.app for errors when debugging:
```bash
# Filter for app logs
log stream --predicate 'process == "OnCallNotify"' --level debug
```

## Common Development Tasks

### Adding a New API Endpoint
1. Add response model to `Models/Models.swift` (conform to `Codable`)
2. Add fetch method to `OnCallService.swift`
3. Use async/await pattern: `func fetchNewData() async throws -> [Model]`
4. Update `AlertSummary` model if needed
5. Update UI in `MenuView.swift` or create new view

### Modifying the Menu Bar Icon
Edit `StatusBarController.swift`:
- `updateStatusBarButton()` method controls icon appearance
- Use SF Symbols for icons: `NSImage(systemSymbolName: "...")`
- Color: `iconImage.isTemplate = true` + set tint color

### Adding a Settings Field
Edit `SettingsView.swift`:
- Add `@State` variable for the field
- Add UI in the appropriate `Section`
- Implement save/load logic (use UserDefaults or Keychain)

### Opening Settings Window
Use conditional availability to support both macOS 13.0 and 14.0+:
```swift
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

private func openSettings() {
    if #available(macOS 14.0, *) {
        // SettingsLink handles this automatically
    } else {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```
This provides SettingsLink on macOS 14+ while maintaining macOS 13.0 compatibility.

### Changing Refresh Interval
Edit `OnCallService.swift`:
- Find `Timer.scheduledTimer(withTimeInterval: 60, ...)`
- Change `60` to desired seconds
- Consider making this user-configurable in Settings

### Adding Support for a New Service

When adding support for a new on-call service:

1. **Create Service-Specific Models** in `Models/Models.swift`:
   ```swift
   struct OpsgenieIncidentsResponse: Codable {
       // Service-specific structure
   }
   ```

2. **Map to Common Models**: Convert service-specific data to common `Incident` and `Oncall` models

3. **Update OnCallService.swift**:
   - Add service selection logic
   - Implement service-specific API calls
   - Keep PagerDuty implementation as reference

4. **Update KeychainHelper.swift**:
   - Add service-specific token storage if needed
   - Use different account identifiers per service

5. **Update SettingsView.swift**:
   - Add service selection UI
   - Add service-specific configuration fields

6. **Test Thoroughly**:
   - Ensure switching between services works
   - Verify data isolation
   - Check error handling for each service

## Security Considerations

### API Token Storage
- **ALWAYS** use KeychainHelper for API tokens
- **NEVER** store tokens in UserDefaults, plain text, or logs
- **NEVER** print tokens to console (even in debug mode)
- Display only last 4 characters in UI
- Use service-specific keychain entries to isolate credentials

### Keychain Access
- Service identifier: `com.oncall.notify`
- Account identifier: `api-token` (currently, will need service-specific identifiers for multi-service)
- Accessibility: `kSecAttrAccessibleAfterFirstUnlock`

### Network Security
- All API calls must use HTTPS
- Validate SSL certificates (URLSession default behavior)
- Handle authentication failures gracefully

## Error Handling

### Pattern
```swift
do {
    let data = try await fetchData()
    // Process data
} catch let error as OnCallError {
    // Handle specific app errors
    DispatchQueue.main.async {
        self.lastError = error
    }
} catch {
    // Handle unexpected errors
    DispatchQueue.main.async {
        self.lastError = OnCallError.networkError(error)
    }
}
```

### User Feedback
- Show errors in UI (don't just log)
- Use descriptive error messages (see `OnCallError.errorDescription`)
- Provide actionable suggestions when possible
- Use generic error messages that don't expose service internals

## Threading and Concurrency

### Rules
- **API calls**: Background thread (handled automatically by async/await)
- **UI updates**: ALWAYS on main thread using `DispatchQueue.main.async` or `@MainActor`
- **Timer callbacks**: May run on background thread, dispatch UI updates to main

### Example
```swift
Task {
    let incidents = try await fetchIncidents() // Background
    DispatchQueue.main.async {
        self.alertSummary.incidents = incidents // Main thread
    }
}
```

## Dependencies and Frameworks

### System Frameworks (no imports needed beyond these)
- `SwiftUI` - UI framework
- `AppKit` - Menu bar integration, NSStatusBar, NSPopover
- `Combine` - Reactive programming (@Published, .sink())
- `Foundation` - URLSession, JSON, dates, etc.
- `Security` - Keychain access

### NO External Dependencies
- Do not add Swift Package Manager dependencies without discussion
- Keep the app lightweight and self-contained

## Documentation Standards

### Code Comments
```swift
// MARK: - Section Name (for organizing code sections)

/// Brief description of public method
///
/// Detailed explanation if needed.
///
/// - Parameter name: Description
/// - Returns: Description
/// - Throws: Error description
func publicMethod(name: String) throws -> Result
```

### File Headers
Each Swift file should have:
```swift
//
//  FileName.swift
//  OnCallNotify
//
//  Created by OnCall Notify
//
```

### Documentation Files
When modifying features:
- Update README.md if user-facing
- Update FEATURES.md for technical details
- Update QUICKSTART.md if setup changes
- Add to CHANGELOG.md for releases
- Update TROUBLESHOOTING.md for new issues/solutions

## Pull Request Guidelines

### Before Submitting
1. Build and run the app to verify it works
2. Test all modified functionality manually
3. Check Console.app for any errors or warnings
4. Ensure code follows style guidelines
5. Update documentation if needed

### Commit Message Format
```
<type>: <subject>

<body>

<footer>
```

**Types**: feat, fix, docs, style, refactor, test, chore

**Example**:
```
feat: Add sound alerts for new incidents

- Implement AVFoundation integration
- Add sound preference to settings
- Play alert sound when new triggered incident appears
- Include system sound selection UI

Closes #42
```

### PR Title Format
```
[Component] Brief description
```
Examples:
- `[Settings] Add refresh interval configuration`
- `[API] Fix rate limiting error handling`
- `[UI] Improve incident list layout`
- `[Service] Add Opsgenie integration`

## Debugging Tips

### Xcode Breakpoints
- Set breakpoints in `OnCallService.swift` to inspect API responses
- Use `po` command to print object details in debugger
- Check `alertSummary` state in `StatusBarController`

### Common Issues
- **Icon not updating**: Check Combine subscription in `StatusBarController`
- **API errors**: Verify token in Keychain, check network
- **UI not refreshing**: Ensure updates on main thread
- **Popover issues**: Check `NSPopover` configuration
- **Layout recursion warning**: Harmless SwiftUI/AppKit integration warning, no impact on functionality
- **SettingsLink availability**: Use conditional `#available(macOS 14.0, *)` check for SettingsLink, fallback for macOS 13.0

### Console Commands
```bash
# View Keychain entry
security find-generic-password -s com.oncall.notify -w

# Check app is running
ps aux | grep OnCallNotify

# View app logs
log show --predicate 'process == "OnCallNotify"' --last 5m
```

## Performance Considerations

### Optimization Goals
- Memory usage: <30 MB
- CPU idle: <1%
- CPU during refresh: <5%
- Network per refresh: ~10-20 KB (per service)
- Startup time: <1 second

### Best Practices
- Cache user ID after first fetch (don't refetch every time)
- Use pagination limits (100 items max)
- Process data on background thread
- Update UI only when data actually changes
- Avoid excessive UI redraws
- When multi-service support is added, fetch in parallel where possible

## Known Limitations

Current constraints to be aware of:
- Read-only access (cannot acknowledge/resolve incidents from app)
- Single service support (PagerDuty only, multi-service coming)
- Single account per service
- Fixed 60-second refresh interval (code change required)
- Shows only user's assigned incidents
- No offline mode (requires internet connection)

## Future Enhancements Roadmap

### Phase 1 (Current - PagerDuty)
- [x] PagerDuty integration
- [x] Basic alert monitoring
- [x] On-call status display
- [x] Native macOS notifications

### Phase 2 (Near Term)
1. Customizable refresh interval in Settings
2. Incident acknowledgment from app
3. Sound alerts (customizable)
4. Notification preferences in Settings

### Phase 3 (Multi-Service)
1. Service abstraction layer
2. Opsgenie integration
3. VictorOps/Splunk On-Call integration
4. Service selection UI in Settings
5. Per-service configuration

### Phase 4 (Advanced)
1. Multiple account support across services
2. Alertmanager integration
3. Custom webhook support
4. Advanced filtering (by service, urgency, team)
5. Historical incident view
6. Keyboard shortcuts
7. Export incident data
8. Multi-team support

## Multi-Service Architecture Guidelines

When implementing multi-service support:

### Service Protocol
Consider defining a protocol for service implementations:
```swift
protocol OnCallServiceProtocol {
    func fetchIncidents() async throws -> [Incident]
    func fetchOncalls() async throws -> [Oncall]
    func testConnection() async -> Bool
}
```

### Service Registry
- Use a factory pattern or service registry
- Allow runtime switching between services
- Maintain separate state per service if supporting multiple accounts

### Configuration Management
- Store service selection in UserDefaults
- Store credentials separately per service in Keychain
- Use service-specific account identifiers like `pagerduty-api-token`, `opsgenie-api-token`

### UI Considerations
- Add service selection dropdown in Settings
- Show service-specific instructions
- Display service name in menu popover
- Use service-specific colors/icons where appropriate

## Security Documentation

**IMPORTANT**: A comprehensive security audit has been completed. Before implementing any features, review:

- **[SECURITY.md](SECURITY.md)** - Complete security audit with detailed implementation checklist (43KB)
  - Full vulnerability descriptions with exact file locations
  - Complete code implementations for all fixes
  - Testing verification steps for each change
  - Risk assessments and priority levels

- **[SECURITY_QUICKREF.md](SECURITY_QUICKREF.md)** - Quick reference guide (5KB)
  - Fast overview of all security issues
  - Implementation order and time estimates
  - Quick test checklist
  - Common mistakes to avoid

- **[SECURITY_AUDIT_SUMMARY.md](SECURITY_AUDIT_SUMMARY.md)** - Executive summary (11KB)
  - Overall security rating: 6.5/10 (target: 9.0/10)
  - Risk assessment and CVSS scores
  - Implementation roadmap
  - Compliance status

- **[SECURITY_TODO.md](SECURITY_TODO.md)** - Simple task checklist (7KB)
  - Checkbox list of all security tasks
  - Progress tracking by phase
  - Current status and milestones

### Security Implementation Priority

**🔴 CRITICAL (Do First - 9 hours):**
1. Fix API token exposure in SettingsView
2. Implement secure API request logging  
3. Enable App Sandbox with entitlements

**🟠 HIGH (Before v1.0 - 11.5 hours):**
4. Update Keychain accessibility level
5. Implement certificate pinning
6. Add API token input validation
7. Sanitize error messages

**Agent Instructions:** Work through security fixes in order (CRITICAL → HIGH → MEDIUM) before adding new features.

## Contact and Resources

- **Repository**: https://github.com/unicornops/oncall-notify
- **Security Issues**: Use GitHub Security Advisories (private reporting)
- **PagerDuty API Docs**: https://developer.pagerduty.com/docs/rest-api-v2/
- **Swift Language Guide**: https://docs.swift.org/swift-book/
- **SwiftUI Tutorials**: https://developer.apple.com/tutorials/swiftui
- **macOS HIG**: https://developer.apple.com/design/human-interface-guidelines/macos
- **Apple Security Framework**: https://developer.apple.com/documentation/security
- **App Sandbox Guide**: https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/

---

**Last Updated**: 2024-12-09  
**Project Version**: 1.0.0  
**Current Service Support**: PagerDuty  
**Security Status**: 🔴 Critical fixes needed (see SECURITY.md)  
**Agent-Friendly**: This file is designed to help AI coding agents understand and contribute to the project effectively.