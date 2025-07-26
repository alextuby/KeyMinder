# KeyMinder

**KeyMinder** is a macOS status bar utility that remembers your preferred keyboard input source (keyboard language layout) **per application** or **per window** and switches it automatically when you change focus. No more typing in the wrong language when switching between apps!

---

## ✨ Features

- 📦 Tracks input source **per app** or **per window**
- 🔄 Automatically switches keyboard layout based on focus
- 🧠 Remembers your last used input source for each app/window
- 🌐 Simple macOS menu bar interface
- 🔒 Secure & private: all mappings are stored in memory
- 🛠 Runs automatically at login via LaunchAgent
- ⚙️ No external dependencies, 100% Swift/Cocoa

---

## 🔧 Installation

> **Note:** This app requires **Accessibility permissions** to function.

1. **Build** the project in Xcode (macOS target).
2. **Run** the app. It will prompt for Accessibility permissions.
3. Go to `System Settings > Privacy & Security > Accessibility`
   - Add the app if it's not listed
   - Ensure the checkbox is enabled
4. The KeyMinder icon will appear in your macOS menu bar.
5. Choose your **default input source** and toggle between **per-app** or **per-window** mode.

---

## 🧪 Development & Debug

- Logging is printed to the console (`stdout`)
- Accessibility setup can be tested via the `testAccessibilitySetup()` function
- `maybeInstallLaunchAgent()` installs a `LaunchAgent` plist to auto-start on login

---

## 🧠 How It Works

- Listens to `AXFocusedUIElementChangedNotification` from each active app
- Identifies the focused window or app (based on mode)
- Checks if an input source is stored for that identifier
  - If yes → switches to it
  - If no → assigns the default input source
- Tracks user-initiated input source changes and updates mappings

---

## 📂 Project Structure

- `AppDelegate.swift`: Main app entry point, sets up menu and managers
- `InputSourceManager class`: Manages keyboard input sources
- `WindowMonitor class`: Tracks window/app focus changes and manages mappings

---

## ⚠️ Accessibility Permissions

KeyMinder relies on macOS Accessibility APIs to detect app/window focus. You **must** grant access for it to function:

- Go to **System Settings > Privacy & Security > Accessibility**
- Add your app binary manually if it's not listed
- Enable the checkbox
- Restart the app

---

## 🚀 Launch at Login

KeyMinder installs a `LaunchAgent` plist file in:
~/Library/LaunchAgents/com.alextuby.KeyMinder.plist


## License

This project is licensed under the [MIT License](LICENSE).

## Author

**Oleksandr Tubolets**  
Feel free to open issues or suggestions via GitHub.