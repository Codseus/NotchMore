# NotchMore

NotchMore is a macOS utility that turns the area around the menu bar notch into a compact control surface, and also adds some neat background features.

This project started because I got tired of installing tiny apps that each do exactly one thing. One app for clipboard history. One app for media controls. One app for window switching. One app for file utilities. After a while you end up with a desktop full of little helpers that all solve one narrow problem. I wanted to bring some of these utilities together into one app.

Contributions and feedback are welcome, if you have any issues, open an issue using the "Bug" label.

If you have any feature requests, open an issue using the "Feature Request" label. Please don't request features that is out of this project's scope.

### Screens with a notch
<img width="1024" height="342" alt="notchpanel" src="https://github.com/user-attachments/assets/9cacb7ad-6516-49a2-8b41-88c983a6f5ba" />

### Screens without a notch

<img width="1024" height="364" alt="floatingpanel" src="https://github.com/user-attachments/assets/e006ffb5-41e5-4b43-988f-5b4b08afede7" />


## Notch Utilities

- Media playback controls with live track information
- Clipboard history with support for text, images, and files
![clipboard](https://github.com/user-attachments/assets/2a1ce79c-961e-4fbb-ac08-d3c25263f8d2)
- File shelf for drag-and-drop access to frequently used files
![file shelf](https://github.com/user-attachments/assets/3d472969-1726-439c-be77-a02b0677f160)


## Background Features

- Window switcher with live previews
![windowswitcher](https://github.com/user-attachments/assets/f7d08f05-52bb-491a-aa34-2c44e5470f36)
- Paste without formatting
- Cut and paste files in Finder like on Windows with Command+X / Command+V
![commandx](https://github.com/user-attachments/assets/a340417e-7f1c-4f38-ad9d-6b86cefce2b9)
- Three-finger middle click support (doesn't work with 3 finger tap yet)
- Scroll inversion (very useful if you use a mouse and the trackpad with different scroll directions)
- Eye resting reminder
![restscreen](https://github.com/user-attachments/assets/1ae20693-f139-4abb-b34d-c0e3c9f7e4af)
![resteyespopup](https://github.com/user-attachments/assets/abb65956-0be5-4c32-83bc-0e32227ac2b1)

## Requirements

- macOS 15.4 or later
- Accessibility permission (required for global input features: scroll inversion, three-finger middle click, paste without formatting, and parts of the window switcher)
- Screen Recording permission (required for window switcher live previews)
- Input Monitoring permission (required for cut-paste and other features)


## Installation

Install the latest dmg file from the releases page.
- Double click to open the dmg file
- Drag the app icon to applications folder
- Close the NotchMore Installer window
- Search for NotchMore in spotlight or go to the applications folder in finder and run NotchMore.app
- After you got the security warning click Done and go to the "Privacy & Security" section in system settings
- Scroll down and you will see under Security, " "NotchMore.app" was blocked " click Open Anyway.

### From Source

1. Clone the repository.
2. Open `NotchMore.xcodeproj` in Xcode.
3. Build and run the `NotchMore` scheme.

## Dependency

NotchMore currently uses one Swift Package dependency:

- `MediaRemoteAdapter`
  - Source: `https://github.com/ejbills/mediaremote-adapter`
  - Used for media playback metadata and controls
- `DynamicNotchKit`
  - Source: `https://github.com/MrKai77/DynamicNotchKit`
  - Used for notch panel display

## Contributing

Issues and pull requests are welcome.

If you contribute a new feature, try to keep it aligned with the current project structure:

- keep feature-specific logic inside `Features/<FeatureName>`
- keep settings wiring in `Settings/SettingsView.swift`

## License

This project is licensed under the GNU General Public License v3.0 only.

See the [LICENSE](LICENSE) file for the full text.

