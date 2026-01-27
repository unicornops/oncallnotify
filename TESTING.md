# Testing Guide for Multi-Service Provider Support

This guide helps testers verify the new multi-service provider functionality in OnCall Notify.

## Prerequisites

To test each service provider, you will need:

1. **macOS 13.0 or later**
2. **Xcode** (for building the app)
3. **Active accounts** on the services you want to test
4. **Valid API tokens** from each service

## Setting Up Test Accounts

### Option 1: Test All Services

Create accounts on all supported platforms:

- PagerDuty (free trial available)
- FireHydrant (free tier available)
- Incident.io (demo available)
- BetterStack (free tier available)
- AlertOps (trial available)

### Option 2: Test Subset

You can test with just one or two services. The app is designed to work with any combination.

## Building the App

```bash
cd /path/to/oncallnotify
./build.sh
open build/Release/OnCallNotify.app
```

## Test Plan

### 1. Fresh Installation Test

**Purpose**: Verify the app works correctly with no existing configuration.

**Steps**:

1. Build and launch the app
2. Click the menu bar icon
3. Click the Settings gear icon
4. Verify "No accounts configured" message appears
5. Click "Add Account" button

**Expected Result**: Settings window opens with empty account list.

---

### 2. Add Account Test (per Service)

**Purpose**: Verify each service provider can be added successfully.

**Steps** (repeat for each service):

1. Click "Add Account"
2. Enter a descriptive name (e.g., "Production PagerDuty")
3. Select service type from dropdown
4. Read the API token instructions
5. Paste a valid API token
6. Click "Add Account"

**Expected Results**:

- Account appears in the list
- Account is enabled by default (green checkmark)
- Service icon appears correctly
- Settings window closes

**Service-Specific Checks**:

| Service     | Icon                                          | Name to Use            |
|-------------|-----------------------------------------------|------------------------|
| PagerDuty   | Bell (`bell.fill`)                            | "PagerDuty Account"    |
| FireHydrant | Flame (`flame.fill`)                          | "FireHydrant Account"  |
| Incident.io | Triangle (`exclamationmark.triangle.fill`)    | "Incident.io Account"  |
| BetterStack | Chart (`chart.line.uptrend.xyaxis`)           | "BetterStack Account"  |
| AlertOps    | Antenna (`antenna.radiowaves.left.and.right`) | "AlertOps Account"     |

---

### 3. Connection Test

**Purpose**: Verify API connectivity for each service.

**Steps** (per account):

1. Open Settings
2. Locate the account in the list
3. Click the network icon
4. Wait for the test to complete

**Expected Results**:

- Loading indicator appears
- After a few seconds, result icon appears:
  - Green checkmark ✅ = Success
  - Red X ❌ = Failure
- If failure, check:
  - Token is valid and not expired
  - Token has correct permissions
  - Network connectivity is available

---

### 4. Incident Fetching Test

**Purpose**: Verify incidents are fetched and displayed correctly.

**Prerequisites**: Have at least one active incident in the service.

**Steps**:

1. Ensure account is enabled
2. Wait up to 60 seconds for auto-refresh (or restart app)
3. Click menu bar icon
4. View the incident list

**Expected Results**:

- Menu bar badge shows incident count
- Menu bar icon color reflects status:
  - Red = Triggered incidents
  - Orange = Acknowledged incidents only
  - Blue = On-call but no incidents
  - Gray = Not on-call, no incidents
- Incidents appear in the popover
- Each incident shows:
  - Title/summary
  - Status (Triggered/Acknowledged)
  - Urgency level
  - Account name it belongs to

---

### 5. Acknowledge Incident Test

**Purpose**: Verify incidents can be acknowledged from the app.

**Prerequisites**: Have at least one triggered (unacknowledged) incident.

**Steps**:

1. Open menu popover
2. Find a triggered incident
3. Click "Acknowledge" button
4. Wait for action to complete

**Expected Results**:

- Button shows loading state
- After completion, incident status changes to "Acknowledged"
- Menu bar badge count decreases
- Icon color may change (if no more triggered incidents)

---

### 6. Acknowledge All Test

**Purpose**: Verify bulk acknowledgment works across services.

**Prerequisites**: Have multiple triggered incidents across different accounts.

**Steps**:

1. Open menu popover
2. Click "Acknowledge All" button at the top
3. Wait for action to complete

**Expected Results**:

- All triggered incidents become acknowledged
- Menu bar badge updates
- Icon color changes appropriately

---

### 7. Multi-Account Test

**Purpose**: Verify multiple accounts work simultaneously.

**Steps**:

1. Add accounts from at least 2 different services
2. Ensure both are enabled
3. Wait for data to refresh
4. Open menu popover

**Expected Results**:

- Incidents from all accounts appear
- Incidents are properly labeled with account name
- Total counts aggregate across accounts
- Each account's incidents are distinguishable

---

### 8. Enable/Disable Account Test

**Purpose**: Verify accounts can be enabled/disabled without deletion.

**Steps**:

1. Open Settings
2. Click the checkmark icon on an account to disable it
3. Wait 60 seconds or restart app
4. Open menu popover
5. Re-enable the account
6. Wait for refresh

**Expected Results**:

- When disabled:
  - Account shows "Disabled" label
  - Account's incidents don't appear in popover
  - Badge count excludes disabled account
- When re-enabled:
  - Account becomes active again
  - Incidents reappear
  - Badge count includes the account

---

### 9. Delete Account Test

**Purpose**: Verify accounts can be removed cleanly.

**Steps**:

1. Open Settings
2. Click the trash icon on an account
3. Wait for refresh

**Expected Results**:

- Account disappears from list
- Related incidents disappear from popover
- Badge count updates
- No crashes or errors

---

### 10. Error Handling Test

**Purpose**: Verify error conditions are handled gracefully.

**Test Cases**:

#### Invalid Token

1. Add account with invalid API token
2. Attempt connection test

**Expected**: Red X with error message

#### Network Disconnect

1. Disable network connection
2. Wait for auto-refresh

**Expected**: Error message in popover, last data still visible

#### Rate Limiting

1. Manually trigger many refreshes quickly

**Expected**: Rate limit error shown, app continues working

#### Service Outage

1. Wait during service maintenance window (if applicable)

**Expected**: Error message shown, app remains stable

---

## Performance Testing

### Memory Usage Test

**Steps**:

1. Launch app with all 5 services configured
2. Open Activity Monitor
3. Monitor "OnCall Notify" process

**Expected**: Memory usage < 50 MB

### CPU Usage Test

**Steps**:

1. Monitor CPU during idle
2. Monitor CPU during refresh

**Expected**:

- Idle: < 1%
- During refresh: < 5%
- Returns to idle after refresh

### Refresh Timing Test

**Steps**:

1. Note current time
2. Watch for auto-refresh in Console logs
3. Verify refresh happens every 60 seconds

**Expected**: Consistent 60-second intervals

---

## Regression Testing

Ensure existing PagerDuty functionality still works:

1. **Legacy Account Migration**
   - If testing upgrade, verify old PagerDuty account migrates
   - Account should appear as "PagerDuty Account"
   - Token should work without re-entering

2. **PagerDuty On-Call**
   - Verify on-call status shows correctly
   - Verify shift information displays

3. **PagerDuty Incidents**
   - Verify all incident types work
   - Verify acknowledgment works
   - Verify incident details show correctly

---

## Known Limitations to Verify

Document these as expected behavior, not bugs:

1. **On-Call Status**: Only PagerDuty shows on-call status currently
   - FireHydrant, Incident.io, BetterStack, AlertOps: Always show "Not on-call"

2. **Read-Only**: Cannot resolve incidents, only acknowledge

3. **Rate Limits**: Each service has different limits (documented in SERVICES.md)

4. **No Desktop Notifications**: Notifications only work for PagerDuty currently

---

## Bug Reporting Template

If you find issues, report with this template:

```markdown
**Service**: [PagerDuty/FireHydrant/etc.]
**OS Version**: [macOS version]
**App Version**: [from About dialog]

**Steps to Reproduce**:
1.
2.
3.

**Expected Behavior**:

**Actual Behavior**:

**Screenshots**: [if applicable]

**Console Logs**: [from Console.app filtered to "OnCall"]
```

---

## Success Criteria

The implementation is successful if:

- ✅ All 5 services can be added
- ✅ Connection tests pass with valid tokens
- ✅ Incidents fetch and display correctly
- ✅ Acknowledgment works for all services
- ✅ Multi-account support works
- ✅ No crashes or data loss
- ✅ Performance is acceptable
- ✅ Error handling is graceful
- ✅ Documentation is accurate

---

## Support

If you need help during testing:

- Check **SERVICES.md** for service-specific setup
- Check **TROUBLESHOOTING.md** for common issues
- Check **README.md** for general information
- Report bugs via GitHub Issues
