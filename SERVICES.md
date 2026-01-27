# Supported Services

OnCall Notify supports multiple incident management and on-call platforms. This guide helps you set up each service.

## Table of Contents

- [PagerDuty](#pagerduty)
- [FireHydrant](#firehydrant)
- [Incident.io](#incidentio)
- [BetterStack](#betterstack)
- [AlertOps](#alertops)
- [Multi-Account Setup](#multi-account-setup)

---

## PagerDuty

### Overview

Full support for PagerDuty's incident management and on-call scheduling features.

### Features Supported

- ✅ Fetch active incidents (triggered and acknowledged)
- ✅ Acknowledge incidents
- ✅ On-call schedule monitoring
- ✅ Real-time status updates
- ✅ Multiple account support

### Setup Instructions

1. **Create API Token**
   - Log in to your PagerDuty account
   - Go to **User Settings** → **API Access Keys**
   - Click **Create API User Token**
   - Copy the generated token

2. **Add Account in OnCall Notify**
   - Open OnCall Notify Settings
   - Click **Add Account**
   - Enter a descriptive name (e.g., "Work PagerDuty")
   - Select **PagerDuty** as service type
   - Paste your API token
   - Click **Add Account**

3. **Test Connection**
   - Click the network icon next to your account
   - Wait for the green checkmark confirming successful connection

### API Endpoints Used

- `GET /users/me` - Current user information
- `GET /incidents` - Active incidents
- `GET /oncalls` - On-call schedules
- `PUT /incidents/{id}` - Acknowledge incidents

### Rate Limits

- 120 requests per minute per API token

---

## FireHydrant

### Overview

Support for FireHydrant's incident management platform.

### Features Supported

- ✅ Fetch active incidents
- ✅ Acknowledge incidents
- ⚠️ On-call schedules (limited - requires integration setup)
- ✅ Real-time status updates
- ✅ Multiple account support

### Setup Instructions

1. **Create API Token**
   - Log in to your FireHydrant account
   - Go to **Settings** → **API Tokens**
   - Click **Generate Token**
   - Select scopes:
     - `read:incidents`
     - `write:incidents`
   - Copy the generated token

2. **Add Account in OnCall Notify**
   - Open OnCall Notify Settings
   - Click **Add Account**
   - Enter a descriptive name (e.g., "Production FireHydrant")
   - Select **FireHydrant** as service type
   - Paste your API token
   - Click **Add Account**

3. **Test Connection**
   - Click the network icon next to your account
   - Verify successful connection

### API Endpoints Used

- `GET /v1/users/me` - Current user information
- `GET /v1/incidents` - Active incidents
- `POST /v1/incidents/{id}/acknowledge` - Acknowledge incidents

### Rate Limits

- 60 requests per minute per token

### Notes

- FireHydrant's on-call feature depends on third-party integrations (PagerDuty, Opsgenie)
- The app shows on-call status as false by default unless integrated

---

## Incident.io

### Overview

Support for Incident.io's modern incident management platform.

### Features Supported

- ✅ Fetch active incidents
- ✅ Update incident status (acknowledge)
- ⚠️ On-call schedules (coming soon)
- ✅ Real-time status updates
- ✅ Multiple account support

### Setup Instructions

1. **Create API Key**
   - Log in to your Incident.io account
   - Go to **Settings** → **API Keys**
   - Click **Create API Key**
   - Select permissions:
     - `incidents:read`
     - `incidents:write`
   - Copy the generated key

2. **Add Account in OnCall Notify**
   - Open OnCall Notify Settings
   - Click **Add Account**
   - Enter a descriptive name (e.g., "Company Incident.io")
   - Select **Incident.io** as service type
   - Paste your API key
   - Click **Add Account**

3. **Test Connection**
   - Click the network icon to verify connection

### API Endpoints Used

- `GET /v2/users` - User information
- `GET /v2/incidents` - Active incidents
- `POST /v2/incidents/{id}/actions/update_status` - Update incident status

### Rate Limits

- 100 requests per minute per API key

### Status Mapping

| Incident.io Status | OnCall Notify Status |
|--------------------|----------------------|
| Triage             | Triggered            |
| Investigating      | Acknowledged         |
| Fixing             | Acknowledged         |
| Resolved/Closed    | Resolved             |

---

## BetterStack

### Overview

Support for BetterStack's uptime monitoring and incident management.

### Features Supported

- ✅ Fetch active incidents
- ✅ Acknowledge incidents
- ⚠️ On-call schedules (coming soon)
- ✅ Real-time status updates
- ✅ Multiple account support

### Setup Instructions

1. **Create API Token**
   - Log in to your BetterStack account
   - Go to **Account** → **API Tokens**
   - Click **Generate Token**
   - Select **Incidents** scope
   - Copy the generated token

2. **Add Account in OnCall Notify**
   - Open OnCall Notify Settings
   - Click **Add Account**
   - Enter a descriptive name (e.g., "Production BetterStack")
   - Select **BetterStack** as service type
   - Paste your API token
   - Click **Add Account**

3. **Test Connection**
   - Click the network icon to verify connection

### API Endpoints Used

- `GET /v2/incidents` - Active incidents
- `POST /v2/incidents/{id}/acknowledge` - Acknowledge incidents

### Rate Limits

- 1000 requests per hour per token

### Notes

- BetterStack focuses on uptime monitoring
- Incidents are generated from monitor failures
- The app displays incident acknowledgment status

---

## AlertOps

### Overview

Support for AlertOps alert management and notification platform.

### Features Supported

- ✅ Fetch active alerts
- ✅ Acknowledge alerts
- ⚠️ On-call schedules (coming soon)
- ✅ Real-time status updates
- ✅ Multiple account support

### Setup Instructions

1. **Create API Key**
   - Log in to your AlertOps account
   - Go to **Settings** → **API Configuration**
   - Click **Create API Key**
   - Select permissions:
     - `Read Alerts`
     - `Acknowledge Alerts`
   - Copy the generated key

2. **Add Account in OnCall Notify**
   - Open OnCall Notify Settings
   - Click **Add Account**
   - Enter a descriptive name (e.g., "Team AlertOps")
   - Select **AlertOps** as service type
   - Paste your API key
   - Click **Add Account**

3. **Test Connection**
   - Click the network icon to verify connection

### API Endpoints Used

- `GET /api/v2/alerts` - Active alerts
- `POST /api/v2/alerts/{id}/acknowledge` - Acknowledge alerts

### Rate Limits

- 500 requests per hour per API key

### Status Mapping

| AlertOps State | OnCall Notify Status |
|----------------|----------------------|
| New/Open       | Triggered            |
| Acknowledged   | Acknowledged         |
| Closed         | Resolved             |

---

## Multi-Account Setup

OnCall Notify supports multiple accounts across different services simultaneously.

### Use Cases

1. **Multiple Teams**: Monitor different teams' PagerDuty accounts
2. **Multi-Service**: Combine PagerDuty, FireHydrant, and other services
3. **Development vs Production**: Separate accounts for different environments

### Setting Up Multiple Accounts

1. **Add First Account**
   - Follow the service-specific instructions above
   - Give it a descriptive name (e.g., "Production PagerDuty")

2. **Add Additional Accounts**
   - Click **Add Account** again
   - Select the same or different service type
   - Use a different descriptive name (e.g., "Staging PagerDuty")
   - Enter the corresponding API token

3. **Manage Accounts**
   - **Enable/Disable**: Toggle accounts on/off without deleting
   - **Test Connection**: Verify each account separately
   - **Delete**: Remove accounts you no longer need

### Account Display

- All active accounts are monitored simultaneously
- The menu bar shows aggregated counts across all accounts
- The popover menu groups incidents by account
- Each incident shows which account it belongs to

### Best Practices

1. **Naming Convention**: Use clear, descriptive names
   - ✅ "Production PagerDuty", "Staging FireHydrant"
   - ❌ "Account 1", "Test"

2. **Token Management**
   - Each account stores its API token securely in macOS Keychain
   - Tokens are never shared between accounts
   - Rotating a token requires updating only that account

3. **Performance**
   - Multiple accounts are fetched in parallel
   - Minimal impact on refresh time
   - Recommended limit: 5-10 active accounts for best performance

---

## Troubleshooting

### Connection Test Fails

#### PagerDuty

- Verify token has not expired
- Check token permissions include API access
- Ensure token is a User Token, not REST API v2 token

#### FireHydrant

- Verify token has `read:incidents` and `write:incidents` scopes
- Check organization settings allow API access

#### Incident.io

- Verify token has `incidents:read` and `incidents:write` permissions
- Ensure API access is enabled for your organization

#### BetterStack

- Verify token has Incidents scope selected
- Check token has not been revoked

#### AlertOps

- Verify API key has Read Alerts and Acknowledge Alerts permissions
- Check API is enabled in organization settings

### No Incidents Showing

1. **Check Account Status**
   - Ensure account is enabled (green checkmark)
   - Test connection is successful

2. **Verify Filters**
   - OnCall Notify shows only active (open/triggered/acknowledged) incidents
   - Resolved incidents are automatically removed

3. **Check User Assignment**
   - Most services filter incidents by assigned user
   - Ensure you have incidents assigned to you

### Rate Limiting

If you see rate limit errors:

1. **Reduce Refresh Frequency**: Default is 60 seconds
2. **Disable Unused Accounts**: Turn off accounts you don't actively monitor
3. **Check API Limits**: See service-specific sections above

---

## Contributing

Want to add support for another service? See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:

- Adding new service providers
- Implementing the ServiceProvider protocol
- Testing multi-service support
- Submitting pull requests

---

## Security

All API tokens are stored securely in macOS Keychain with:

- Per-account isolation
- No iCloud sync
- Device-only accessibility
- Encrypted storage

Never share API tokens or commit them to version control.

---

## Support

- **Issues**: [GitHub Issues](https://github.com/unicornops/oncall-notify/issues)
- **Documentation**: [README.md](README.md)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)
