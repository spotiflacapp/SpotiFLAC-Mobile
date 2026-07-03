# Contributing to SpotiFLAC

First off, thank you for considering contributing to SpotiFLAC! 🎉

This document provides guidelines and steps for contributing. Following these guidelines helps maintain code quality and ensures a smooth collaboration process.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Code Contributions](#code-contributions)
  - [Translations](#translations)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Coding Guidelines](#coding-guidelines)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the [existing issues](https://github.com/zarzet/SpotiFLAC-Mobile/issues) to avoid duplicates.

When creating a bug report, please use the bug report template and include:

- **Clear and descriptive title**
- **Steps to reproduce** the issue
- **Expected behavior** vs **actual behavior**
- **Screenshots or screen recordings** if applicable
- **Device information** (model, OS version)
- **App version**
- **Logs** from Settings > About > View Logs

### Suggesting Features

Feature requests are welcome! Please use the feature request template and:

- **Check existing issues** to avoid duplicates
- **Describe the feature** clearly
- **Explain the use case** - why would this be useful?
- **Consider the scope** - is this a small enhancement or a major feature?

### Code Contributions

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following our coding guidelines
3. **Test your changes** thoroughly
4. **Submit a pull request** to the `main` branch

### Translations

We use [Crowdin](https://crowdin.com/project/spotiflac-mobile) for translations. To contribute:

1. Visit our [Crowdin project](https://crowdin.com/project/spotiflac-mobile)
2. Select your language or request a new one
3. Start translating!

Translation files are located in `lib/l10n/arb/`.

## Development Setup

### Prerequisites

- **Flutter SDK** 3.10.0 or higher
- **Dart SDK** 3.10.0 or higher
- **Android Studio** or **VS Code** with Flutter extensions
- **Git**

### Getting Started

1. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR_USERNAME/SpotiFLAC-Mobile.git
   cd SpotiFLAC-Mobile
   ```

2. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/zarzet/SpotiFLAC-Mobile.git
   ```

3. **Use FVM (Flutter Version: 3.41.5)**
   ```bash
   fvm use
   ```

4. **Install dependencies**
   ```bash
   flutter pub get
   ```

5. **Generate code** (for Riverpod, JSON serialization, etc.)
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

6. **Set up Go environment (Go Version: 1.25.7)**
   ```bash
   cd go_backend 
   mkdir -p ../android/app/libs
   gomobile init
   gomobile bind -target=android -androidapi 24 -o ../android/app/libs/gobackend.aar .
   cd ..
   ```

7. **Run the app**
   ```bash
   flutter run
   ```

### Building

```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release
```

## Project Structure

```
lib/
├── l10n/               # Localization files
│   └── arb/            # ARB translation files
├── models/             # Data models
├── providers/          # Riverpod providers
├── screens/            # UI screens
│   └── settings/       # Settings sub-screens
├── services/           # Business logic services
├── theme/              # App theming
├── utils/              # Utility functions
├── widgets/            # Reusable widgets
├── app.dart            # App configuration
└── main.dart           # Entry point
```

## Coding Guidelines

### General

- Follow [Effective Dart](https://dart.dev/effective-dart) guidelines
- Use meaningful variable and function names
- Keep functions small and focused
- Add comments for complex logic

### Formatting

- Use `dart format` before committing
- Maximum line length: 80 characters
- Use trailing commas for better formatting

```bash
dart format .
```

### Linting

Ensure your code passes all lints:

```bash
flutter analyze
```

### State Management

We use **Riverpod** for state management, with hand-written `Notifier`s
(no `riverpod_annotation` code generation). Follow this pattern:

```dart
class MyNotifier extends Notifier<MyState> {
  @override
  MyState build() => MyState();

  // Methods to update state
}

final myProvider = NotifierProvider<MyNotifier, MyState>(MyNotifier.new);
```

### Localization

All user-facing strings should be localized:

```dart
// Good
Text(AppLocalizations.of(context)!.downloadComplete)

// Bad
Text('Download Complete')
```

To add new strings:
1. Add the key to `lib/l10n/arb/app_en.arb`
2. Run `flutter gen-l10n`

## Commit Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

```
feat(download): add batch download support
fix(ui): resolve overflow on small screens
docs: update contributing guidelines
chore(deps): update flutter_riverpod to 3.1.0
```

## Pull Request Process

1. **Update your fork**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feat/my-new-feature
   ```

3. **Make your changes** and commit following our guidelines

4. **Push to your fork**
   ```bash
   git push origin feat/my-new-feature
   ```

5. **Create a Pull Request**
   - Target the `main` branch
   - Fill in the PR template
   - Link related issues

6. **Address review feedback**
   - Make requested changes
   - Push additional commits
   - Request re-review when ready

### PR Requirements

- [ ] Code follows project conventions
- [ ] All tests pass
- [ ] No new linting errors
- [ ] Documentation updated (if needed)
- [ ] Commit messages follow guidelines
- [ ] PR description is clear and complete

## Questions?

If you have questions, feel free to:

- Open a [Discussion](https://github.com/zarzet/SpotiFLAC-Mobile/discussions)
- Check existing [Issues](https://github.com/zarzet/SpotiFLAC-Mobile/issues)

Thank you for contributing! 💚
