# GitHub Actions Workflows

## Overview

This directory contains GitHub Actions workflows for the OnCall Notify project.

## Workflows

### Release on Merge to Main (`release-on-merge.yml`)

This workflow handles both **automatic** and **manual** release creation for OnCall Notify.
It builds, signs, notarizes, and publishes macOS app releases.

#### Triggers

##### 1. Automatic Release (Push to Main)

Automatically creates a release when code is merged to the `main` branch:

```yaml
on:
  push:
    branches:
      - main
```

**How it works:**

1. Detects conventional commits since the last tag
2. Automatically bumps version using [Cocogitto](https://docs.cocogitto.io/)
3. Creates a new git tag (e.g., `v1.2.3`)
4. Builds, signs, and notarizes the app
5. Creates a GitHub release with DMG and ZIP files

**Requirements:**

- At least one [conventional commit](https://www.conventionalcommits.org/) since the last release
- Commits must follow the format: `type(scope): description`
- Examples: `feat: Add new feature`, `fix: Resolve bug`, `docs: Update README`

**Version Bumping:**

- `feat:` commits trigger a **minor** version bump (1.0.0 → 1.1.0)
- `fix:` commits trigger a **patch** version bump (1.0.0 → 1.0.1)
- `BREAKING CHANGE:` in commit body triggers a **major** version bump (1.0.0 → 2.0.0)

**What happens if there are no conventional commits?**

- The workflow will exit gracefully without creating a release
- This prevents unnecessary releases when only non-conventional commits exist (e.g., manual changes)

##### 2. Manual Release (Workflow Dispatch)

Manually trigger a release from the GitHub Actions UI:

```yaml
on:
  workflow_dispatch:
    inputs:
      version:
        description: "Version to release (e.g., 1.2.3 or leave empty for auto-bump)"
        required: false
        type: string
```

**How to trigger manually:**

1. Go to **Actions** tab in GitHub
2. Select **"Release on Merge to Main"** workflow
3. Click **"Run workflow"** button
4. Choose the branch (usually `main`)
5. Optionally enter a specific version number (e.g., `1.2.3` or `v1.2.3`)
6. Click **"Run workflow"**

**Manual Version Options:**

- **Leave empty**: Automatically bumps version based on conventional commits (same as automatic trigger)
- **Specify version**: Creates a release with the exact version you specify
  - Examples: `1.2.3`, `v1.2.3`, `2.0.0-beta.1`
  - The workflow will add the `v` prefix if you don't include it

**Use Cases for Manual Releases:**

- **Hotfix releases**: Create an urgent patch without waiting for a merge
- **Custom version numbers**: Override auto-versioning for special releases
- **Re-release**: Rebuild and release without new code changes
- **Recovery**: Recover from a failed automatic release
- **Pre-release/Beta**: Create pre-release versions (e.g., `1.2.0-beta.1`)

#### Workflow Steps

1. **Checkout code**: Fetches the repository with full history
2. **Configure git**: Sets up git user for automated commits
3. **Determine version strategy**: Checks if manual or auto-bump
4. **Check conventional commits**: Validates commit format (auto-bump only)
5. **Get next version**: Calculates the next version (auto-bump only)
6. **Bump version**: Creates a new version tag
7. **Push tags**: Pushes the new tag to GitHub
8. **Generate changelog**: Creates release notes from conventional commits
9. **Build environment**: Shows Xcode, Swift, and macOS versions
10. **Setup code signing**: Imports Apple Developer certificate
11. **Build and sign**: Compiles and signs the macOS app
12. **Verify signature**: Ensures code signature is valid
13. **Notarize app**: Submits to Apple for notarization (required for macOS)
14. **Create DMG**: Packages app in a DMG installer
15. **Create ZIP**: Creates a ZIP archive of the app
16. **Calculate checksums**: Generates SHA-256 checksums
17. **Create release**: Publishes GitHub release with assets
18. **Cleanup**: Removes imported certificates

#### Required Secrets

The workflow requires the following GitHub secrets to be configured:

- `GITHUB_TOKEN`: Automatically provided by GitHub Actions
- `APPLE_CERTIFICATE_BASE64`: Base64-encoded Apple Developer ID certificate (.p12)
- `APPLE_CERTIFICATE_PASSWORD`: Password for the certificate
- `APPLE_TEAM_ID`: Apple Developer Team ID (10 characters, e.g., `ABCD123456`)
- `APPLE_DEVELOPER_ID`: Apple ID email for notarization
- `APPLE_APP_PASSWORD`: App-specific password for notarization

#### Security Features

- **Branch protection**: Only runs on `main` branch (for push trigger)
- **Certificate cleanup**: Always removes imported certificates after build
- **Login keychain**: Uses macOS login keychain for better xcodebuild compatibility
- **Token permissions**: Minimal required permissions (id-token, contents, packages)
- **Secrets isolation**: Secrets only accessible on main branch

#### Build Outputs

Each release creates:

1. **DMG Installer** (`OnCallNotify-x.y.z.dmg`):
   - Professional macOS installer
   - Custom background and layout
   - Drag-to-Applications shortcut

2. **ZIP Archive** (`OnCallNotify-x.y.z.zip`):
   - Alternative distribution format
   - Smaller file size
   - Suitable for automated deployments

3. **Checksums** (`checksums.txt`):
   - SHA-256 hashes for both DMG and ZIP
   - Verify download integrity

4. **Release Notes**:
   - Auto-generated from conventional commits
   - Installation instructions
   - Build information and checksums

#### Troubleshooting

##### "No conventional commits found"

**Cause**: No commits with conventional format since last tag.

**Solutions**:

- Add conventional commits (e.g., `feat: Add feature`, `fix: Fix bug`)
- Use manual release with a specific version number
- Amend the last commit to use conventional format

##### "Certificate import failed"

**Cause**: Invalid certificate or password.

**Solutions**:

- Verify `APPLE_CERTIFICATE_BASE64` is correct base64 encoding
- Check `APPLE_CERTIFICATE_PASSWORD` matches certificate
- Re-export certificate from Keychain Access as .p12

##### "Notarization failed"

**Cause**: Invalid credentials or app not properly signed.

**Solutions**:

- Verify `APPLE_DEVELOPER_ID` (Apple ID email)
- Check `APPLE_APP_PASSWORD` is an app-specific password (not account password)
- Ensure code signing succeeded before notarization step

##### "DMG creation failed"

**Cause**: Missing dependencies or invalid app bundle.

**Solutions**:

- Ensure `create-dmg.sh` script exists and is executable
- Verify app was built successfully
- Check build logs for errors

#### Example Workflows

##### Automatic Release Flow

```bash
# 1. Make changes with conventional commits
git commit -m "feat: Add sound alerts"
git commit -m "fix: Resolve icon update bug"

# 2. Merge to main
git push origin main

# 3. Workflow automatically:
#    - Detects 1 feat + 1 fix = minor version bump
#    - Creates v1.1.0 tag
#    - Builds and releases OnCallNotify-1.1.0.dmg
```

##### Manual Release Flow

```bash
# Scenario: Need to create v1.2.0 without new commits

# 1. Go to GitHub Actions UI
# 2. Click "Run workflow"
# 3. Enter version: 1.2.0
# 4. Workflow creates v1.2.0 tag and release
```

##### Hotfix Release Flow

```bash
# Scenario: Critical bug fix needs immediate release

# 1. Create hotfix branch
git checkout -b hotfix/critical-fix

# 2. Fix bug
git commit -m "fix(critical): Resolve crash on startup"

# 3. Merge to main
git push origin main

# 4. Automatic release creates v1.0.1 (patch bump)
```

#### Best Practices

1. **Use conventional commits**: Always follow the format for automatic versioning
2. **Test before merge**: Ensure builds succeed locally before merging to main
3. **Monitor Actions**: Check workflow runs in the Actions tab
4. **Verify releases**: Test downloaded DMG/ZIP after release
5. **Manual releases sparingly**: Use for special cases, prefer automatic releases
6. **Document breaking changes**: Use `BREAKING CHANGE:` in commit body for major bumps

#### References

- [Conventional Commits](https://www.conventionalcommits.org/)
- [Cocogitto Documentation](https://docs.cocogitto.io/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Apple Notarization Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Xcode Code Signing](https://developer.apple.com/documentation/xcode/code-signing)
