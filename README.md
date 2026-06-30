# NotchMore

NotchMore is a macOS utility that turns the area around the menu bar notch into a compact control surface, and also adds small background tools for everyday Mac workflows.

This project started because I got tired of installing tiny apps that each do exactly one thing. One app for clipboard history. One app for media controls. One app for window switching. One app for file utilities. After a while you end up with a desktop full of little helpers that all solve one narrow problem. I wanted to bring some of these utilities together into one app.

Contributions and feedback are welcome, if you have any issues, open an issue using the "Bug" label.

If you have any feature requests, open an issue using the "Feature Request" label. Please don't request features that are out of this project's scope.

### Screens with a notch

<img width="1024" height="342" alt="notchpanel" src="https://github.com/user-attachments/assets/9cacb7ad-6516-49a2-8b41-88c983a6f5ba" />

### Screens without a notch

<img width="1024" height="364" alt="floatingpanel" src="https://github.com/user-attachments/assets/e006ffb5-41e5-4b43-988f-5b4b08afede7" />

## Notch Utilities

- Media playback controls with live track information and artwork
- Clipboard history with support for text, images, files, pinned items, and plain-text paste
  ![clipboard](https://github.com/user-attachments/assets/2a1ce79c-961e-4fbb-ac08-d3c25263f8d2)
- File shelf for drag-and-drop access to frequently used files, with multi-select, copy, copy path, share, and remove actions
  ![file shelf](https://github.com/user-attachments/assets/3d472969-1726-439c-be77-a02b0677f160)
- Notch-style HUD for volume, brightness, battery state, and rest reminders

## Background Features

- Window switcher with live previews
![windowswitcher](https://github.com/user-attachments/assets/f7d08f05-52bb-491a-aa34-2c44e5470f36)

- Dock previews for open apps, with window controls
- Paste without formatting
- Cut and paste files in Finder like on Windows with Command+X / Command+V
  ![commandx](https://github.com/user-attachments/assets/a340417e-7f1c-4f38-ad9d-6b86cefce2b9)
- Three-finger middle click support (doesn't work with 3 finger tap yet)
- Scroll inversion (very useful if you use a mouse and the trackpad with different scroll directions)
- Caps Lock no-delay mode
- Eye resting reminder
  ![restscreen](https://github.com/user-attachments/assets/1ae20693-f139-4abb-b34d-c0e3c9f7e4af)
  ![resteyespopup](https://github.com/user-attachments/assets/abb65956-0be5-4c32-83bc-0e32227ac2b1)
- First-run onboarding that lets you choose which features to enable and request the required permissions up front

## Requirements

- macOS 15.4 or later
- Accessibility permission for global input features such as scroll inversion, three-finger middle click, paste tools, Dock previews, and parts of the window switcher
- Screen Recording permission for live window and Dock previews
- Input Monitoring permission for keyboard-driven features such as file cut/paste and hardware-key HUD handling

## Installation

Download the latest signed release from the [Releases](https://github.com/Codseus/NotchMore/releases) page, open the downloaded package, and move NotchMore to your Applications folder.

On first launch, NotchMore shows onboarding so you can choose the features you want and grant the permissions they need. You can change enabled features later from Settings.

## Updates

NotchMore uses Sparkle for automatic updates.

### From Source

1. Clone the repository.
2. Open `NotchMore.xcodeproj` in Xcode.
3. Build and run the `NotchMore` scheme.

Or build from Terminal:

```bash
xcodebuild -scheme NotchMore -configuration Debug -derivedDataPath .build build
```

The built app will be available under:

```bash
.build/Build/Products/Debug/NotchMoreDebug.app
```

Release builds use the normal app name:

```bash
.build/Build/Products/Release/NotchMore.app
```

## Dependency

NotchMore currently uses these Swift Package dependencies:

- `MediaRemoteAdapter`
  - Source: `https://github.com/ejbills/mediaremote-adapter`
  - Used for media playback metadata and controls
- `DynamicNotchKit`
  - Source: `https://github.com/MrKai77/DynamicNotchKit`
  - Used for notch panel display
- `Sparkle`
  - Source: `https://github.com/sparkle-project/Sparkle`
  - Used for automatic updates

## Contributing

Issues and pull requests are welcome.

If you contribute a new feature, try to keep it aligned with the current project structure:

- keep feature-specific logic inside `Features/<FeatureName>`
- keep settings wiring in `Settings/SettingsView.swift`
- include the new feature in the onboarding flow in `Onboarding/OnboardingView.swift`

## License

This project is licensed under the GNU General Public License v3.0 only.

See the [LICENSE](LICENSE) file for the full text.
