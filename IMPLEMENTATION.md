# Multi-Account Support - Implementation Details

## Overview

This document provides a comprehensive technical overview of the multi-account support implementation for OnCall Notify.

## Problem Statement

The original issue requested: "The app should support more than one pager duty account at a time. This should be the start of multi provider support and should work in the same way to allow more than one account of any type to be added at a time."

## Solution Architecture

### Design Goals

1. **Support multiple accounts per service type** (e.g., multiple PagerDuty accounts)
2. **Maintain backward compatibility** with existing single-account setups
3. **Prepare for multi-service support** (PagerDuty, VictorOps, Compass, etc.)
4. **Provide intuitive account management UI**
5. **Ensure secure credential storage** with per-account isolation
6. **Maintain or improve performance** with parallel API calls

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    StatusBarController                  │
│                  (Observes OnCallService)               │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    OnCallService                        │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐│
│   │AccountService│  │AccountService│  │AccountService││
│   │  (Account 1) │  │  (Account 2) │  │  (Account N) ││
│   └──────────────┘  └──────────────┘  └──────────────┘│
│          │                  │                  │        │
│          └──────────────────┴──────────────────┘        │
│                         │                               │
│                  Aggregate Results                      │
│                         │                               │
│                 @Published alertSummary                 │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    KeychainHelper                       │
│  • accounts-list (JSON array of Account objects)       │
│  • api-token-{accountId} (per-account credentials)     │
│  • Legacy: api-token (auto-migrated)                   │
└─────────────────────────────────────────────────────────┘
```

## Implementation Details

### 1. Data Models (Models.swift)

#### New Models

**ServiceType Enum**
```swift
enum ServiceType: String, Codable, CaseIterable {
    case pagerDuty = "PagerDuty"
    // Future: atlassianCompass, jiraServiceManagement, victorOps, etc.
}
```
- Extensible enum for different service providers
- Currently only PagerDuty is implemented
- Ready for additional services

**Account Model**
```swift
struct Account: Codable, Identifiable, Equatable {
    let id: String           // UUID
    var name: String         // User-friendly name
    let serviceType: ServiceType
    var isEnabled: Bool      // Allow disabling without deletion
}
```
- Unique identifier for each account
- User can provide friendly name
- Can be temporarily disabled
- Supports multiple accounts of same service type

**AccountAlertSummary**
```swift
struct AccountAlertSummary {
    let accountId: String
    let accountName: String
    var totalAlerts: Int
    var acknowledgedCount: Int
    var unacknowledgedCount: Int
    var isOnCall: Bool
    var incidents: [Incident]
}
```
- Per-account summary data
- Used for aggregation and display

#### Modified Models

**AlertSummary**
```swift
struct AlertSummary {
    // ... existing fields ...
    var accountSummaries: [String: AccountAlertSummary]  // NEW
}
```
- Added dictionary of per-account summaries
- Maintains backward compatibility with existing fields

**Incident**
```swift
struct Incident: Codable, Identifiable {
    // ... existing fields ...
    var accountId: String?  // NEW - set programmatically
}
```
- Tagged with source account ID
- Not part of API response, set after decoding
- Enables account-specific operations (e.g., acknowledgment)

### 2. Keychain Storage (KeychainHelper.swift)

#### Storage Structure

**Before (Single Account)**
```
Keychain:
  - service: "com.oncall.notify"
  - account: "api-token"
  - value: "user's token"
```

**After (Multi Account)**
```
Keychain:
  - service: "com.oncall.notify"
  - account: "accounts-list"
  - value: JSON array of Account objects
  
  - service: "com.oncall.notify"
  - account: "api-token-{account1.id}"
  - value: "account1's token"
  
  - service: "com.oncall.notify"
  - account: "api-token-{account2.id}"
  - value: "account2's token"
```

#### Key Methods

```swift
// Account Management
func getAccounts() -> [Account]
func addAccount(_ account: Account, apiToken: String) -> Bool
func updateAccount(_ account: Account) -> Bool
func deleteAccount(accountId: String) -> Bool

// Token Management
func saveAPIToken(_ token: String, forAccountId accountId: String) -> Bool
func getAPIToken(forAccountId accountId: String) -> String?
func deleteAPIToken(forAccountId accountId: String) -> Bool

// Legacy Support (backward compatibility)
func saveAPIToken(_ token: String) -> Bool  // Routes to "legacy" account
func getAPIToken() -> String?                // Checks both old and new keys
func deleteAPIToken() -> Bool                // Deletes old key
func hasAPIToken() -> Bool                   // Checks for any token
```

#### Migration Logic

```swift
private func migrateLegacyAccount() -> [Account] {
    // 1. Check for legacy token
    guard let legacyToken = getKeychainString(account: "api-token") else {
        return []
    }
    
    // 2. Create default account
    let defaultAccount = Account(
        id: "legacy",
        name: "PagerDuty Account",
        serviceType: .pagerDuty,
        isEnabled: true
    )
    
    // 3. Save with new structure
    saveAPIToken(legacyToken, forAccountId: defaultAccount.id)
    saveAccounts([defaultAccount])
    
    // 4. Delete old entry
    deleteAPIToken()
    
    return [defaultAccount]
}
```
- Automatic migration on first launch
- Preserves existing credentials
- No user action required
- One-way migration (safe to delete old key)

### 3. Service Layer (OnCallService.swift)

#### OnCallService (Main Manager)

**Responsibilities:**
- Manage multiple AccountService instances
- Coordinate parallel API calls
- Aggregate results from all accounts
- Publish combined AlertSummary
- Handle account lifecycle (add/remove/enable/disable)

**Key Methods:**
```swift
// Account Management
func initializeAccountServices()     // Create services for all accounts
func reloadAccounts()                // Refresh account list and services

// Data Fetching
func fetchAllData() async           // Fetch from all enabled accounts in parallel

// Account-specific operations
func acknowledgeIncident(incidentId: String, accountId: String) async throws
func testConnection(accountId: String) async -> Bool
```

**Parallel Fetching with TaskGroup:**
```swift
await withTaskGroup(of: (String, AccountAlertSummary?, Error?).self) { group in
    for (accountId, service) in accountServices {
        group.addTask {
            do {
                let summary = try await service.fetchData()
                return (accountId, summary, nil)
            } catch {
                return (accountId, nil, error)
            }
        }
    }
    
    // Collect results
    for await (accountId, summary, error) in group {
        // Process results...
    }
}
```
- Fetches from all accounts concurrently
- Handles partial failures gracefully
- Returns as soon as all complete

#### AccountService (Per-Account Handler)

**Responsibilities:**
- Manage API calls for a single account
- Maintain per-account state (user ID, previous status, etc.)
- Detect changes and trigger notifications
- Tag incidents with account ID

**Key Methods:**
```swift
func fetchData() async throws -> AccountAlertSummary
func acknowledgeIncident(incidentId: String) async throws
func testConnection() async -> Bool
```

**State Management:**
```swift
private var currentUserId: String?                              // Cached user ID
private var previousIncidentStatuses: [String: IncidentStatus]  // For change detection
private var previousOnCallStatus: Bool                          // For notifications
private var isFirstFetch: Bool                                  // Skip notifications on first fetch
```

### 4. User Interface

#### SettingsView (Complete Rewrite)

**Structure:**
```
SettingsView
├── Accounts Section
│   ├── Account List (ForEach)
│   │   └── AccountRowView (for each account)
│   └── Add Account Button
└── Information Section
    ├── Auto-refresh interval
    ├── Data storage info
    └── Active account count
```

**AccountRowView:**
```
[Icon] Account Name        [Test] [Toggle] [Delete]
       Service Type
       Status (enabled/disabled)
```

**AddAccountView (Sheet):**
- Account name input
- Service type picker (extensible)
- API token secure field
- Service-specific instructions
- Validation
- Save/Cancel buttons

**Key Features:**
- Add multiple accounts
- Enable/disable without deleting
- Test connection per account
- Visual feedback for all operations
- Error handling and display

#### MenuView (Enhanced)

**Changes:**
- Account badges on incidents
- Account-aware acknowledgment
- Unchanged: aggregated counts and status

**Incident Display:**
```
● Incident Title
  Service Name • Account Name    [✓] [↗]
  ⏰ 2h ago
```
- Shows account badge in blue
- Separator dot between service and account
- Account info retrieved from KeychainHelper

### 5. Error Handling

**Account-Level Errors:**
- Individual account failures don't crash the app
- Errors are collected and first error is shown
- Other accounts continue to work

**User-Facing Errors:**
- Connection test failures show red X icon
- Invalid tokens show validation errors
- Network errors show user-friendly messages
- Failed API calls don't affect other accounts

### 6. Performance Considerations

**Optimization Strategies:**
1. **Parallel API Calls**: All accounts fetch simultaneously
2. **Per-Account State**: Cached user IDs prevent redundant calls
3. **Efficient Aggregation**: Single pass through results
4. **Lazy Initialization**: Services created only for enabled accounts

**Expected Performance:**
- Memory: +5-10 MB per additional account
- CPU: Same as single account (parallel calls)
- Network: Linear increase (one request set per account)
- Startup: Negligible impact (lazy loading)

### 7. Security

**Enhancements:**
- Per-account credential isolation
- Separate keychain entries prevent cross-account contamination
- Account deletion removes all associated credentials
- No credentials in memory longer than necessary

**Validation:**
- Token format validation (length, characters)
- Service-specific rules enforced
- Clear error messages without exposing internals

## Testing Strategy

### Unit Testing (Conceptual)
- Account model serialization
- KeychainHelper CRUD operations
- Migration logic
- Aggregation algorithms

### Integration Testing
- Multi-account data fetching
- Account enable/disable
- Parallel API call coordination
- Error handling with partial failures

### Manual Testing
- Fresh installation
- Migration from single account
- Multiple account scenarios
- UI interactions
- See TESTING_MULTI_ACCOUNT.md for detailed test cases

## Migration Path

### For Existing Users

**Scenario 1: User has configured account**
1. App launches
2. KeychainHelper.getAccounts() is called
3. No "accounts-list" found in keychain
4. migrateLegacyAccount() is called
5. Legacy "api-token" is found
6. New account created with ID "legacy"
7. Token copied to "api-token-legacy"
8. Account list saved
9. Old "api-token" deleted
10. User sees "PagerDuty Account" in Settings

**Scenario 2: User has no account**
1. App launches
2. No accounts found
3. Settings shows "No accounts configured"
4. User clicks "Add Account"
5. Fresh account creation flow

### For New Users

1. Install app
2. Open Settings
3. See "No accounts configured" message
4. Click "Add Account"
5. Fill in details
6. Start using

## Future Extensions

### Adding New Service Types

**Steps:**
1. Add to ServiceType enum:
   ```swift
   case victorOps = "VictorOps"
   ```

2. Update AddAccountView instructions:
   ```swift
   case .victorOps:
       "Create an API key in VictorOps Settings..."
   ```

3. Create service-specific implementation:
   ```swift
   class VictorOpsService {
       // Similar to AccountService but for VictorOps API
   }
   ```

4. Update OnCallService to instantiate correct service type:
   ```swift
   switch account.serviceType {
   case .pagerDuty:
       return PagerDutyAccountService(account: account)
   case .victorOps:
       return VictorOpsAccountService(account: account)
   }
   ```

### Potential Features

1. **Account Ordering**: Drag to reorder accounts in Settings
2. **Account Grouping**: Group accounts by team or organization
3. **Account-Specific Filters**: Filter menu view by account
4. **Account Colors**: Color-code accounts for easy identification
5. **Account Notes**: Add notes/description to accounts
6. **Account Sharing**: Import/export account configurations (without tokens)

## Breaking Changes

None. The implementation is fully backward compatible through automatic migration.

## Known Limitations

1. **One-way Migration**: Cannot downgrade back to single-account
2. **Account Name Editing**: Cannot rename accounts after creation (workaround: delete and re-add)
3. **No Account Ordering**: Accounts displayed in order added
4. **Service Type Fixed**: Cannot change service type after creation

## Dependencies

No new dependencies added. Implementation uses only:
- Foundation (URLSession, JSONEncoder/Decoder, etc.)
- SwiftUI
- AppKit (for menu bar)
- Security (for Keychain)
- Combine (for reactive updates)

## Code Quality

- ✅ All Swift files pass syntax check
- ✅ Follows existing code style conventions
- ✅ Proper error handling throughout
- ✅ Async/await for all async operations
- ✅ @MainActor for UI updates
- ✅ Secure logging (no sensitive data)
- ✅ Comments on complex logic
- ⏳ SwiftLint checks (requires installation)

## Lines of Code

**New/Modified:**
- Models.swift: ~70 lines added
- KeychainHelper.swift: ~180 lines added/modified
- OnCallService.swift: ~420 lines added/modified  
- SettingsView.swift: ~390 lines (complete rewrite)
- MenuView.swift: ~30 lines modified

**Total: ~1,090 lines changed/added**

## Review Checklist

For reviewers, please verify:

- [ ] Code follows Swift and project conventions
- [ ] Migration logic is safe and tested
- [ ] Multi-account data fetching works correctly
- [ ] UI is intuitive and matches project style
- [ ] Error handling covers edge cases
- [ ] No security vulnerabilities introduced
- [ ] Performance is acceptable with multiple accounts
- [ ] Documentation is clear and complete
- [ ] No breaking changes for existing users

## Conclusion

This implementation provides a robust, extensible foundation for multi-account support while maintaining backward compatibility and preparing for future multi-service expansion. The architecture cleanly separates concerns, uses modern Swift concurrency features, and follows the existing project patterns.
