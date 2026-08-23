# NotchMore

NotchMore is a free, open-source macOS utility that turns the area around the menu bar notch into a compact control surface and adds practical tools for everyday Mac workflows.

Instead of installing a separate app for clipboard history, media controls, window switching, file utilities, and other small improvements, NotchMore brings them together in one native app. Every feature is optional and can be enabled or disabled independently.

[Website](https://codseus.github.io/NotchMore/) · [Download](https://github.com/Codseus/NotchMore/releases/latest) · [Report a bug](https://github.com/Codseus/NotchMore/issues) · [Request a feature](https://github.com/Codseus/NotchMore/issues)

## Features

### Notch Panel

- Media playback controls with track information and artwork
- Clipboard history for text, images, and files
- Clipboard item previews, pinned items, plain-text paste, and image OCR
- File shelf with multi-select, copy, copy path, share, and remove actions
- AirDrop and LocalSend drop targets
- Quick camera mirror
- Desktop icon visibility toggle
- Notch-style HUDs for volume, brightness, battery state, and rest reminders
- Support for Macs with and without a physical notch
- Customizable panel trigger area and hover delay

### Window and Dock Tools

- Window switcher with live previews
- Dock previews for open applications
- Close, minimize, maximize, and quit controls from Dock previews

### Input and Finder Tools

- Paste without formatting
- Cut and paste files in Finder with `Command+X` and `Command+V`
- Independent mouse and trackpad scroll direction
- Three-finger middle click support
- Caps Lock no-delay mode

### Additional Utilities

- Eye-rest reminders with delay and skip controls
- Automatic screenshot copying to the clipboard
- First-run onboarding for feature selection and permission setup
- Automatic updates through Sparkle

## Requirements

- macOS 15.4 or later
- Accessibility permission for global input and window-management features
- Screen Recording permission for live window and Dock previews
- Input Monitoring permission for keyboard-driven features and hardware-key HUD handling
- Camera permission only when using the mirror feature
- Local Network permission only when using LocalSend integration

NotchMore requests permissions only when they are required by an enabled feature. Permissions and features can be reviewed later from Settings.

## Installation

1. Download the latest signed and notarized version from [GitHub Releases](https://github.com/Codseus/NotchMore/releases/latest).
2. Move NotchMore to the Applications folder.
3. Open the app and complete the first-run feature and permission setup.

NotchMore checks for updates automatically using Sparkle.

## Build From Source

1. Clone the repository.
2. Open `NotchMore.xcodeproj` in Xcode.
3. Build and run the `NotchMore` scheme.

You can also build from Terminal:

```bash
xcodebuild -scheme NotchMore -configuration Debug -derivedDataPath .build build
```

Debug and release builds use different app names and bundle identifiers so they can have separate macOS permissions:

```text
.build/Build/Products/Debug/NotchMoreDebug.app
.build/Build/Products/Release/NotchMore.app
```

## Dependencies

- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) for media metadata and playback controls
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) for notch panel presentation
- [Sparkle](https://github.com/sparkle-project/Sparkle) for automatic updates

## Contributing

Issues and pull requests are welcome.

- Use the `Bug` label when reporting a problem.
- Use the `Feature Request` label when proposing functionality within the project's scope.
- Keep feature-specific code under `Features/<FeatureName>`.
- Add settings integration in `Settings/SettingsView.swift` when needed.
- Include user-facing features in the onboarding flow when they require initial setup or permissions.

## License

NotchMore is licensed under the [GNU General Public License v3.0](LICENSE).
