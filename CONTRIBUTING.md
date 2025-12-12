# Contributing to OnCall Notify

Thank you for your interest in contributing to OnCall Notify! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for all contributors.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected behavior** vs actual behavior
- **Screenshots** if applicable
- **Environment details**:
  - macOS version
  - Xcode version (if building from source)
  - App version
  - PagerDuty account type (if relevant)

### Suggesting Enhancements

Enhancement suggestions are welcome! Please include:

- **Clear use case** - why is this enhancement needed?
- **Detailed description** of the proposed functionality
- **Alternative solutions** you've considered
- **Mockups or examples** if applicable

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Follow the coding standards** outlined below
3. **Test your changes** thoroughly
4. **Update documentation** as needed
5. **Write clear commit messages**
6. **Submit the pull request** with a comprehensive description

## Development Setup

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Git
- A PagerDuty account for testing

### Getting Started

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/oncall-notify.git
   cd oncall-notify
   ```

2. Open the project in Xcode:
   ```bash
   open OnCallNotify.xcodeproj
   ```

3. Build and run:
   - Press `⌘R` in Xcode
   - Or use the build script: `./build.sh Debug`

## Coding Standards

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

Key points:

- **Naming**: Use clear, descriptive names
  ```swift
  // Good
  func fetchIncidents() async throws -> [Incident]
  
  // Bad
  func getStuff() -> [Any]
  ```

- **Indentation**: 4 spaces (no tabs)
- **Line length**: Aim for 100 characters, max 120
- **Comments**: Use `//` for single-line, `/* */` for multi-line
- **Documentation**: Add doc comments for public APIs

### SwiftUI Conventions

- Use `@State` for view-local state
- Use `@ObservedObject` for shared objects
- Keep views focused and composable
- Extract reusable components

### Code Organization

```
OnCallNotify/
├── Models/           # Data models and types
├── Services/         # Business logic and API clients
├── Views/            # SwiftUI views
└── Assets.xcassets/  # Images and resources
```

## Project Structure

### Key Files

- **OnCallNotifyApp.swift**: App entry point
- **StatusBarController.swift**: Menu bar integration
- **PagerDutyService.swift**: PagerDuty API client
- **KeychainHelper.swift**: Secure credential storage
- **Models.swift**: Data models
- **SettingsView.swift**: Settings interface
- **MenuView.swift**: Popover menu interface

### Adding New Features

1. **Plan the feature**: Discuss in an issue first
2. **Create a branch**: `git checkout -b feature/your-feature-name`
3. **Implement the feature**:
   - Add models if needed (Models/)
   - Add business logic (Services/)
   - Add UI components (Views/)
4. **Test thoroughly**
5. **Update documentation**
6. **Submit pull request**

## Testing

### Manual Testing Checklist

Before submitting a PR, test:

- [ ] Menu bar icon displays correctly
- [ ] Settings window opens and saves data
- [ ] API connection works with valid token
- [ ] Popover shows correct information
- [ ] Auto-refresh works (wait 60+ seconds)
- [ ] On-call status updates correctly
- [ ] Incident list displays properly
- [ ] Error handling works (try invalid token)
- [ ] App quits cleanly

### API Testing

Test with different PagerDuty states:

- No incidents
- Multiple incidents (triggered and acknowledged)
- Currently on-call
- Not on-call
- Invalid API token
- Network disconnection

## Documentation

### Code Documentation

Use Swift documentation comments for public APIs:

```swift
/// Fetches all active incidents from PagerDuty
///
/// This method retrieves incidents with status 'triggered' or 'acknowledged'
/// and filters them by the current user.
///
/// - Returns: An array of `Incident` objects
/// - Throws: `PagerDutyError` if the API request fails
func fetchIncidents() async throws -> [Incident]
```

### README Updates

If your change affects user-facing features:

- Update README.md with new features
- Add screenshots if UI changed
- Update QUICKSTART.md if setup changed
- Update roadmap section if feature was planned

## Commit Messages

Follow this format:

```
<type>: <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Example**:
```
feat: Add desktop notifications for new incidents

- Implement NSUserNotification integration
- Add notification preferences to settings
- Show notification when new triggered incident appears
- Include incident title and service in notification

Closes #42
```

## Pull Request Process

1. **Update your fork**:
   ```bash
   git checkout main
   git pull upstream main
   git checkout your-feature-branch
   git rebase main
   ```

2. **Push your changes**:
   ```bash
   git push origin your-feature-branch
   ```

3. **Create pull request** on GitHub

4. **Fill out the PR template** with:
   - Description of changes
   - Related issue(s)
   - Testing performed
   - Screenshots (if UI changes)

5. **Address review feedback**

6. **Wait for approval** and merge

## Version Numbering

We use [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

## Release Process

Maintainers will:

1. Update version in Info.plist
2. Update CHANGELOG.md
3. Create Git tag
4. Build release binary
5. Publish GitHub release

## Getting Help

- **Questions?** Open a discussion on GitHub
- **Stuck?** Comment on the relevant issue
- **Security concerns?** Email maintainers directly

## Recognition

Contributors will be:

- Listed in release notes
- Credited in the README
- Thanked in the community

## Additional Resources

- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [PagerDuty API Documentation](https://developer.pagerduty.com/docs/rest-api-v2/rest-api/)
- [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos)

---

Thank you for contributing to OnCall Notify! Your efforts help make on-call life better for everyone. 🚀