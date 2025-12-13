# Testing Native macOS Notifications

This document provides guidance for manually testing the notification feature in OnCall Notify.

## Overview

OnCall Notify now sends native macOS notifications for:
- New incidents/alerts assigned to you
- Changes in incident status (triggered → acknowledged → resolved)
- Changes in on-call status (going on-call or off-call)

## Prerequisites

1. macOS 13.0 (Ventura) or later
2. Valid PagerDuty API token configured
3. Notification permissions granted to the app

## Initial Setup

### First Launch
1. Build and run the app
2. When prompted, allow notifications (click "Allow" when the permission dialog appears)
3. Configure your PagerDuty API token in Settings
4. Wait for the first data fetch to complete

### Checking Permission Status
You can verify notification permissions at any time:
1. Open **System Settings** → **Notifications**
2. Find "OnCall Notify" in the list
3. Ensure notifications are enabled with these settings:
   - Allow Notifications: ON
   - Show in Notification Center: ON (optional)
   - Play sound for notifications: ON (optional)
   - Show notifications on lock screen: ON (optional)

## Test Scenarios

### Test 1: New Incident Notification
**Goal**: Verify that a notification is sent when a new incident is assigned.

**Steps**:
1. Launch the app with a valid API token
2. Wait for initial data fetch (icon should update)
3. Create a new incident in PagerDuty assigned to your account
4. Wait up to 60 seconds for the next auto-refresh

**Expected Result**:
- macOS notification banner appears
- Title: "New Alert"
- Subtitle: "Urgency: [high/low]"
- Body: Incident title
- Default notification sound plays
- Notification includes incident details

### Test 2: Incident Status Change Notification
**Goal**: Verify notifications for status changes.

**Steps**:
1. Have at least one triggered incident assigned to you
2. Wait for the app to fetch the current state
3. Acknowledge the incident in PagerDuty
4. Wait up to 60 seconds for the next auto-refresh

**Expected Result**:
- macOS notification appears
- Title: "Alert Acknowledged"
- Subtitle: "Status changed to acknowledged"
- Body: Incident title

**Variation A** - Resolve an acknowledged incident:
- Title: "Alert Resolved"
- Subtitle: "Status changed to resolved"

### Test 3: On-Call Status Change Notification
**Goal**: Verify notifications when on-call status changes.

**Steps**:
1. Have an on-call schedule configured in PagerDuty
2. Wait for your on-call shift to start (or manually trigger via PagerDuty)
3. Wait up to 60 seconds for auto-refresh

**Expected Result** (Going on-call):
- macOS notification appears
- Title: "Now On-Call"
- Body: "You are now on-call"
- Default notification sound

**Expected Result** (Going off-call):
- macOS notification appears
- Title: "No Longer On-Call"
- Body: "Your on-call shift has ended"

### Test 4: Multiple Simultaneous Notifications
**Goal**: Verify that multiple changes are properly detected.

**Steps**:
1. While off-call, create 2-3 new incidents
2. Wait for auto-refresh

**Expected Result**:
- Multiple notifications appear (one per incident)
- Each notification shows the correct incident details
- Notifications don't interfere with each other

### Test 5: No Duplicate Notifications
**Goal**: Verify that the same change doesn't trigger multiple notifications.

**Steps**:
1. Note the current incident count
2. Wait for multiple auto-refresh cycles (2-3 minutes)
3. No changes made in PagerDuty

**Expected Result**:
- No notifications are sent
- App continues to function normally
- Status bar icon remains accurate

### Test 6: Permission Denied Scenario
**Goal**: Verify graceful handling when notifications are disabled.

**Steps**:
1. Open System Settings → Notifications
2. Find OnCall Notify and turn OFF "Allow Notifications"
3. Create a new incident in PagerDuty
4. Wait for auto-refresh

**Expected Result**:
- No notifications appear (as expected)
- App continues to function normally
- Status bar icon still updates
- Console shows appropriate log message

### Test 7: Initial State Initialization
**Goal**: Verify that existing alerts don't trigger notifications on first launch.

**Steps**:
1. Have several existing incidents assigned to you
2. Quit the app if running
3. Launch the app fresh
4. Wait for first data fetch

**Expected Result**:
- No notifications for existing incidents
- Status bar icon shows correct state
- Future changes will trigger notifications

## Notification Content Verification

For each notification, verify:

### New Incident
- ✅ Title: "New Alert"
- ✅ Subtitle: Shows urgency level
- ✅ Body: Shows incident title
- ✅ Sound plays
- ✅ Clicking notification does not crash app

### Status Change
- ✅ Title: Appropriate status change message
- ✅ Subtitle: Describes the change
- ✅ Body: Shows incident title
- ✅ Sound plays

### On-Call Change
- ✅ Title: "Now On-Call" or "No Longer On-Call"
- ✅ Body: Appropriate message
- ✅ Sound plays

## Troubleshooting

### No Notifications Appearing

1. **Check Permissions**:
   - System Settings → Notifications → OnCall Notify
   - Ensure "Allow Notifications" is ON

2. **Check Console Logs**:
   ```bash
   log stream --predicate 'process == "OnCallNotify"' --level debug
   ```
   Look for messages about notification permissions or failures

3. **Reset Notification State**:
   - Quit the app
   - Open Terminal and run:
     ```bash
     tccutil reset Notifications com.oncall.notify
     ```
   - Launch app again and allow permissions

4. **Check API Connection**:
   - Open Settings in the app
   - Click "Test Connection"
   - Verify it succeeds

### Notifications Not Updating

1. **Verify Auto-Refresh**:
   - Check status bar icon tooltip
   - Should update every 60 seconds
   - Manual refresh via popover refresh button

2. **Check Network Connection**:
   - Ensure internet connectivity
   - Verify PagerDuty is accessible

3. **Review Logs**:
   - Check for API errors
   - Look for rate limiting issues

## Performance Testing

Monitor these aspects during testing:

1. **Memory Usage**: Should remain under 30 MB
2. **CPU Usage**: 
   - Idle: < 1%
   - During refresh: < 5%
3. **Responsiveness**: UI should remain responsive during notifications
4. **Battery Impact**: Minimal (verify in Activity Monitor)

## Known Behaviors

1. **First Launch**: No notifications for existing incidents (intentional)
2. **60-Second Delay**: Changes detected during auto-refresh cycle
3. **Permission Dialog**: Only appears once per fresh install
4. **State Persistence**: Notification state resets when app restarts

## Test Results Template

Use this template to record your test results:

```
Date: [DATE]
macOS Version: [VERSION]
App Build: [BUILD]

Test 1 - New Incident: [ ] PASS [ ] FAIL
Notes: 

Test 2 - Status Change: [ ] PASS [ ] FAIL
Notes: 

Test 3 - On-Call Change: [ ] PASS [ ] FAIL
Notes: 

Test 4 - Multiple Notifications: [ ] PASS [ ] FAIL
Notes: 

Test 5 - No Duplicates: [ ] PASS [ ] FAIL
Notes: 

Test 6 - Permission Denied: [ ] PASS [ ] FAIL
Notes: 

Test 7 - Initial State: [ ] PASS [ ] FAIL
Notes: 

Overall Result: [ ] PASS [ ] FAIL
Additional Comments:
```

## Regression Testing

Ensure these existing features still work:

- [ ] Status bar icon updates correctly
- [ ] Icon color reflects alert status
- [ ] Popover displays correctly
- [ ] Settings window opens and functions
- [ ] API token can be saved/loaded
- [ ] Test Connection works
- [ ] Manual refresh works
- [ ] Auto-refresh continues working
- [ ] On-call status displays correctly
- [ ] Incident list shows correctly
- [ ] App quits cleanly

## CI/CD Verification

After merging, verify:
1. Build workflow passes
2. CI workflow passes
3. No new warnings or errors in build logs
4. App archive size is reasonable
5. No regression in existing functionality

## Documentation

Verify documentation is updated:
- [x] README.md mentions notifications
- [x] AGENTS.md includes NotificationService
- [x] CHANGELOG.md has entry
- [ ] Screenshots include notification examples (future)

## Future Enhancements

Consider testing these when implemented:
- Notification preferences in Settings
- Custom sounds per notification type
- Notification grouping
- Rich notification content (buttons/actions)
- Notification history

---

**Note**: This is a manual testing guide. Automated tests for notifications are challenging due to macOS permission requirements and testing environment limitations.
