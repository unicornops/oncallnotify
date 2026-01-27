# Multi-Service Provider Implementation Summary

This document summarizes the implementation of multi-service provider support in OnCall Notify.

## What Was Implemented

### New Service Providers

Four new incident management platforms were added:

1. **FireHydrant** - Incident management platform
2. **Incident.io** - Modern incident management
3. **BetterStack** - Uptime monitoring and incidents
4. **AlertOps** - Alert management platform

### Architecture Changes

#### Protocol-Based Design

Created a `ServiceProvider` protocol that all service implementations must conform to:

```swift
protocol ServiceProvider {
    var account: Account { get }
    func updateAccount(_ newAccount: Account)
    func fetchData() async throws -> AccountAlertSummary
    func acknowledgeIncident(incidentId: String) async throws
    func testConnection() async -> Bool
}
```

#### Service Provider Factory

Implemented a factory pattern to create the correct provider based on service type:

```swift
class ServiceProviderFactory {
    static func createProvider(for account: Account) -> ServiceProvider {
        switch account.serviceType {
        case .pagerDuty: return PagerDutyProvider(account: account)
        case .fireHydrant: return FireHydrantProvider(account: account)
        case .incidentIO: return IncidentIOProvider(account: account)
        case .betterStack: return BetterStackProvider(account: account)
        case .alertOps: return AlertOpsProvider(account: account)
        }
    }
}
```

### File Structure

```text
OnCallNotify/Services/
├── ServiceProvider.swift          # Protocol definition and factory
├── PagerDutyProvider.swift        # PagerDuty implementation
├── FireHydrantProvider.swift      # FireHydrant implementation
├── IncidentIOProvider.swift       # Incident.io implementation
├── BetterStackProvider.swift      # BetterStack implementation
├── AlertOpsProvider.swift         # AlertOps implementation
├── OnCallService.swift            # Main orchestration service
├── KeychainHelper.swift           # Secure token storage
└── NotificationService.swift      # Desktop notifications
```

### UI Enhancements

#### ServiceType Enum Extensions

Added properties to support UI configuration:

```swift
enum ServiceType {
    case pagerDuty, fireHydrant, incidentIO, betterStack, alertOps

    var displayName: String { ... }
    var apiTokenInstructions: String { ... }
    var iconName: String { ... }
}
```

#### Icons for Each Service

- **PagerDuty**: `bell.fill`
- **FireHydrant**: `flame.fill`
- **Incident.io**: `exclamationmark.triangle.fill`
- **BetterStack**: `chart.line.uptrend.xyaxis`
- **AlertOps**: `antenna.radiowaves.left.and.right`

### API Integration Details

#### FireHydrant

- **Base URL**: `https://api.firehydrant.io/v1`
- **Auth**: Bearer token
- **Endpoints**:
  - `GET /users/me` - User info
  - `GET /incidents` - Active incidents
  - `POST /incidents/{id}/acknowledge` - Acknowledge
- **Rate Limit**: 60 req/min

#### Incident.io

- **Base URL**: `https://api.incident.io/v2`
- **Auth**: Bearer token
- **Endpoints**:
  - `GET /users` - User list
  - `GET /incidents` - Active incidents
  - `POST /incidents/{id}/actions/update_status` - Update status
- **Rate Limit**: 100 req/min

#### BetterStack

- **Base URL**: `https://uptime.betterstack.com/api/v2`
- **Auth**: Bearer token
- **Endpoints**:
  - `GET /incidents` - Active incidents
  - `POST /incidents/{id}/acknowledge` - Acknowledge
- **Rate Limit**: 1000 req/hour

#### AlertOps

- **Base URL**: `https://api.alertops.com/api/v2`
- **Auth**: Bearer token
- **Endpoints**:
  - `GET /alerts` - Active alerts
  - `POST /alerts/{id}/acknowledge` - Acknowledge
- **Rate Limit**: 500 req/hour

### Status Mapping

Each provider maps its status values to our common `IncidentStatus` enum:

| Provider     | Triggered             | Acknowledged            | Resolved        |
|--------------|-----------------------|-------------------------|-----------------|
| PagerDuty    | triggered             | acknowledged            | resolved        |
| FireHydrant  | open                  | milestone:acknowledged  | closed          |
| Incident.io  | triage                | investigating/fixing    | resolved/closed |
| BetterStack  | open (not acked)      | open (acked)            | resolved        |
| AlertOps     | new/open              | acknowledged            | closed          |

### Features Supported by Provider

| Feature         | PagerDuty | FireHydrant | Incident.io | BetterStack | AlertOps |
|-----------------|-----------|-------------|-------------|-------------|----------|
| Fetch Incidents | ✅        | ✅          | ✅          | ✅          | ✅       |
| Acknowledge     | ✅        | ✅          | ✅          | ✅          | ✅       |
| On-Call Status  | ✅        | ⚠️          | ⚠️          | ⚠️          | ⚠️       |
| Multi-Account   | ✅        | ✅          | ✅          | ✅          | ✅       |

⚠️ = Coming soon or depends on service integration

### Code Quality

- All Swift files follow the project style guide
- Proper error handling with `OnCallError` enum
- Async/await for all network operations
- Secure token storage in Keychain per account
- No external dependencies - pure Swift implementation

### Documentation

Created comprehensive documentation:

1. **SERVICES.md** - Complete setup guide for each service
2. **README.md** - Updated with new service list
3. **CHANGELOG.md** - Documented new features
4. **Code Comments** - Inline documentation for all providers

## What's Next

### Immediate Testing

To verify the implementation works:

1. Create test accounts for each service
2. Verify connection tests pass
3. Confirm incident fetching works
4. Test acknowledgment functionality
5. Verify multi-account aggregation

### Future Enhancements

1. **On-Call Schedule Support**
   - Implement on-call schedule fetching for all providers
   - Add shift notifications

2. **Advanced Features**
   - Bulk operations across services
   - Service-specific custom fields
   - Incident filtering and search

3. **Additional Providers**
   - Atlassian Compass
   - Jira Service Management
   - VictorOps
   - Alertmanager
   - Custom webhooks

## Migration Path

Existing users with PagerDuty accounts will be automatically migrated:

1. Legacy single-account setup detected on first launch
2. Automatically converted to multi-account format
3. Original PagerDuty account preserved with name "PagerDuty Account"
4. Keychain token migrated to new format
5. No user action required

## Security Considerations

All implementations follow security best practices:

- API tokens stored in macOS Keychain with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- No iCloud sync of sensitive data
- Per-account token isolation
- Generic error messages to users (technical details in logs only)
- HTTPS only for all API calls
- No token logging or printing

## Performance

- Parallel fetching across multiple accounts
- Efficient JSON parsing
- Minimal memory footprint
- 60-second refresh interval (configurable)
- URL session connection pooling

## Conclusion

This implementation provides a solid, extensible foundation for multi-service support while
maintaining backward compatibility and security. The protocol-based architecture makes it easy
to add new providers in the future.
