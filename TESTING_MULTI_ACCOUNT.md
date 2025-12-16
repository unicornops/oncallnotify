# Multi-Account Support Testing Guide

## Overview

This document provides testing instructions for the multi-account support feature.

## Test Scenarios

### 1. Fresh Installation (No Existing Account)

**Steps:**
1. Build and run the app
2. Click the menu bar icon
3. Click the gear icon to open Settings
4. Verify "No accounts configured" message is displayed
5. Click "Add Account"
6. Enter account details:
   - Name: "Test Account 1"
   - Service Type: PagerDuty
   - API Token: (valid token)
7. Click "Add Account"
8. Verify account appears in the list
9. Click the network icon to test connection
10. Verify connection test passes
11. Close Settings
12. Verify incidents appear in the menu

**Expected Results:**
- ✅ Account is added successfully
- ✅ Connection test passes
- ✅ Incidents are displayed with account badge
- ✅ Status bar updates with alert counts

### 2. Migration from Single Account

**Steps:**
1. If you have an existing installation with a single account configured
2. Build and run the updated app
3. Click the menu bar icon
4. Click the gear icon to open Settings
5. Verify your existing account appears as "PagerDuty Account"
6. Verify incidents continue to display correctly

**Expected Results:**
- ✅ Existing account is migrated automatically
- ✅ Account name is "PagerDuty Account"
- ✅ All existing functionality continues to work
- ✅ No data loss

### 3. Adding Multiple Accounts

**Steps:**
1. Have at least one account configured
2. Open Settings
3. Click "Add Account"
4. Add a second account with different credentials
5. Verify both accounts appear in the list
6. Test connection for both accounts
7. Close Settings
8. Verify incidents from both accounts appear in the menu
9. Verify each incident shows the correct account badge

**Expected Results:**
- ✅ Both accounts can be added
- ✅ Both connections can be tested independently
- ✅ Incidents from both accounts appear
- ✅ Account badges correctly identify the source account
- ✅ Aggregate counts are correct

### 4. Disabling an Account

**Steps:**
1. Have at least two accounts configured
2. Open Settings
3. Click the checkmark icon on one account to disable it
4. Verify the icon changes to an empty circle
5. Verify "Disabled" label appears
6. Close Settings
7. Verify incidents from the disabled account no longer appear
8. Verify aggregate counts are updated

**Expected Results:**
- ✅ Account can be disabled
- ✅ Disabled account's incidents are not fetched
- ✅ Other accounts continue to work normally
- ✅ Re-enabling the account restores functionality

### 5. Deleting an Account

**Steps:**
1. Have at least two accounts configured
2. Open Settings
3. Click the trash icon on one account
4. Verify account is removed from the list
5. Close Settings
6. Verify incidents from the deleted account no longer appear
7. Reopen Settings
8. Verify the account is still not present

**Expected Results:**
- ✅ Account is deleted
- ✅ API token is removed from Keychain
- ✅ Incidents from deleted account are not displayed
- ✅ Deletion is persistent across app restarts

### 6. Acknowledging Incidents

**Steps:**
1. Have at least one account with unacknowledged incidents
2. Click the menu bar icon
3. Find an incident with status "triggered"
4. Note the account badge on the incident
5. Click the checkmark icon to acknowledge
6. Wait for the operation to complete
7. Verify the incident updates to "acknowledged" status

**Expected Results:**
- ✅ Incident can be acknowledged
- ✅ Correct account is used for the API call
- ✅ UI updates after acknowledgment
- ✅ No errors occur

### 7. Test Connection Failure

**Steps:**
1. Open Settings
2. Click "Add Account"
3. Enter invalid API token
4. Add the account
5. Click the network icon to test connection
6. Verify error indicator (red X) appears

**Expected Results:**
- ✅ Invalid token can be added (for later fixing)
- ✅ Connection test fails appropriately
- ✅ Error is displayed clearly
- ✅ App doesn't crash

### 8. Empty State

**Steps:**
1. Delete all accounts
2. Verify Settings shows "No accounts configured"
3. Verify menu shows appropriate message
4. Verify status bar icon shows gray/inactive state

**Expected Results:**
- ✅ Empty state is handled gracefully
- ✅ No errors or crashes
- ✅ Clear instructions to add an account

## Edge Cases to Test

### Multiple Accounts with Same Credentials
- Add two accounts with the same API token
- Verify both work independently
- Verify incidents are not duplicated

### Account with No Incidents
- Add an account that has no active incidents
- Verify it doesn't cause errors
- Verify on-call status still works

### Network Failure
- Disable network connectivity
- Verify app handles failures gracefully
- Verify appropriate error messages are shown
- Re-enable network and verify recovery

### Rapid Account Changes
- Quickly add/remove multiple accounts
- Verify no race conditions occur
- Verify UI remains responsive

## Performance Testing

### Memory Usage
- Add 3-5 accounts
- Monitor memory usage (should remain under 30 MB)
- Verify no memory leaks over time

### CPU Usage
- With multiple accounts configured
- Verify CPU usage is minimal when idle (<1%)
- Verify CPU usage during refresh is acceptable (<5%)

### Network Usage
- Monitor network traffic during refresh
- Should be approximately 10-20 KB per account per refresh

## Security Testing

### Keychain Storage
1. Add multiple accounts
2. Open Keychain Access app
3. Search for "com.oncall.notify"
4. Verify each account has a separate keychain entry
5. Verify tokens are encrypted

### Token Validation
1. Try to add an account with:
   - Too short token (<20 chars) - should fail
   - Too long token (>100 chars) - should fail
   - Token with special characters - should fail
   - Valid token - should succeed

## Regression Testing

Verify that all existing functionality still works:
- ✅ Status bar icon updates
- ✅ Color coding (red/orange/blue/gray)
- ✅ Alert counts are correct
- ✅ On-call status detection
- ✅ Next shift display
- ✅ Auto-refresh every 60 seconds
- ✅ Manual refresh button
- ✅ Opening PagerDuty web interface
- ✅ Quit functionality

## Known Limitations

- Migration is one-way (single → multi-account)
- Currently only PagerDuty is supported
- Cannot edit account name after creation (workaround: delete and re-add)
- Account order in list is not configurable

## Reporting Issues

When reporting issues, please include:
- macOS version
- App version
- Number of accounts configured
- Steps to reproduce
- Screenshots if applicable
- Console logs (check Console.app and filter for "OnCallNotify")
