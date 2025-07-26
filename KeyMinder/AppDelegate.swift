import Cocoa
import Carbon
import ServiceManagement



// This functino catches all focus change notifications for apps
// we subscribe to below.
// It then launches the handleFocusChange function that figures out
// what to do next.
private func accessibilityFocusChangeCallback(
    observer: AXObserver,
    element: AXUIElement, // This will be the system-wide element
    notification: CFString,
    contextData: UnsafeMutableRawPointer?
) {
    // Re-cast the contextData back to your WindowMonitor instance
    guard let contextData = contextData else { return }
    let monitor = Unmanaged<WindowMonitor>.fromOpaque(contextData).takeUnretainedValue()

    // Ensure this is the correct notification and dispatch to main thread for processing
    if notification == kAXFocusedUIElementChangedNotification as CFString {
            DispatchQueue.main.async {
                monitor.handleFocusChange(observedElement: element, for: observer)
            }
        }
}


// AppDelegate is the main entry point for the macOS app using @main attribute
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem? // Reference to the status bar item
    var inputSourceManager: InputSourceManager! // Manages input sources
    var windowMonitor: WindowMonitor! // Monitors window and app changes
    var isPerApplication = false // Toggle between per-window and per-application mode
    var defaultInputSource: TISInputSource? // Default input source for new apps
    
    // Called on app launch
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("=== KeyMider Starting ===")
        if let window = NSApplication.shared.windows.first {
                window.setIsVisible(false)
            }
        testAccessibilitySetup()
        // Debug: Print the  app location
        let appPath = Bundle.main.bundlePath
        print("App is located at: \(appPath)")
        print("Add this path to Accessibility permissions if needed")
        
        print("Initializing managers...")
        // Initialize managers first
        inputSourceManager = InputSourceManager()
        
        // Set current input source as default if none is stored
        loadDefaultInputSource()

        print("Creating status bar item...")
        // Create status bar item
        setupStatusBar()
       
        // Initialize window monitor for app/window focus changes
        windowMonitor = WindowMonitor()
        
        print("Setting up window monitoring...")
        // Set up window monitoring
        windowMonitor.delegate = self
        windowMonitor.defaultInputSource = defaultInputSource
        
        print("Requesting accessibility permissions...")
        // Request accessibility permissions if needed
        requestAccessibilityPermissions()
        
        print("Starting monitoring...")
        // Start the monitoring of windows and input sources
        windowMonitor.startMonitoring()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if AXIsProcessTrusted() {
                    self.windowMonitor.startAXFocusMonitoring()
                } else {
                    print("Accessibility not granted. Skipping AXFocusMonitoring until next launch.")
                }
            }
        
//        if let bundleID = Bundle.main.bundleIdentifier {
//            let success = SMLoginItemSetEnabled(bundleID as CFString, true)
//            print(success ? "✅ Launch at login enabled." : "❌ Failed to enable launch at login.")
//        } else {
//            print("❌ Could not get bundle identifier.")
//        }
        maybeInstallLaunchAgent()
        
        print("KeyMider started successfully!")
    }
    
    // Test functions that I used to figure out what's possible in terms of
    // subscriptions. I kept it just in case for the future.
    func testAccessibilitySetup() {
        print("--- Running Accessibility Setup Test ---")
        // Use the explicit prompt to be sure
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            print("[TEST] ❌ Accessibility not granted. Aborting test.")
            return
        }
        print("[TEST] ✅ Accessibility is granted.")

        var testObserver: AXObserver?
        // A dummy callback that just prints a message
        let callback: AXObserverCallback = { _, _, _, _ in
            print("[TEST CALLBACK] Focus changed!")
        }

        // 1. Create Observer
        let createResult = AXObserverCreate(getpid(), callback, &testObserver)
        guard createResult == .success, let observer = testObserver else {
            print("[TEST] ❌ FAILED to create observer. Error: \(createResult.rawValue)")
            return
        }
        print("[TEST] Observer created successfully.")

        // 2. Add to Run Loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        print("[TEST] Observer added to current run loop.")

        // 3. Add Notification (The failing step)
        // Unfortunatelly I wasn't able to add system wide notifications
        // to an observer. Doesn't seem to be possible or I don't
        // know how. I had to subscribe to every app instead. But kept this
        // for future. Maybe someone else will figure this out.
        let systemElement = AXUIElementCreateSystemWide()
        let notification = kAXFocusedUIElementChangedNotification as CFString
        let addResult = AXObserverAddNotification(observer, systemElement, notification, nil)

        if addResult == .success {
            print("[TEST] ✅ SUCCESS! Notification added.")
        } else {
            print("[TEST] ❌ FAILED to add notification. Error code: \(addResult.rawValue)")
        }
        print("--- End of Test ---")
    }
    
    
    func maybeInstallLaunchAgent() {
            let label = "com.alextuby.KeyMinder"
            let plistPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(label).plist")

            if FileManager.default.fileExists(atPath: plistPath.path) {
                print("🚫 LaunchAgent already exists, skipping installation.")
                return
            }

            installLaunchAgent(label: label)
        }

    func installLaunchAgent(label: String) {
        let launchAgentDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let plistURL = launchAgentDir.appendingPathComponent("\(label).plist")
        guard let executablePath = Bundle.main.executablePath else {
            print("❌ Could not determine executable path")
            return
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        do {
            try FileManager.default.createDirectory(at: launchAgentDir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
            print("✅ LaunchAgent installed at \(plistURL.path)")
        } catch {
            print("❌ Failed to install LaunchAgent: \(error)")
        }
    }
    
    // Sets up the status bar icon and menu
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
//            // Use SF Symbol for keyboard icon
//            if let customImage = NSImage(named: "32.png") {
//                    button.image = customImage
//                } else {
//                    // Fallback to system symbol if custom image fails to load
                    button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyMinder")
//                }
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        
        setupMenu()
    }
    
    // Builds the menu for the status bar item
    func setupMenu() {
        let menu = NSMenu()
        
        // Top-level: Default input source selection
        let defaultSourceItem = NSMenuItem(title: "Default Input Source", action: nil, keyEquivalent: "")
        let defaultSourceSubmenu = NSMenu()
        
        // Get all available input sources - add nil check
        guard let inputSourceManager = inputSourceManager else {
            print("Warning: inputSourceManager is nil, cannot setup menu")
            return
        }
        
        let inputSources = inputSourceManager.getAllInputSources()
        let currentDefaultID = getDefaultInputSourceID()
        print("Current default ID: \(currentDefaultID ?? "nil")")
        
        // Add each available input source as a menu item
        for inputSource in inputSources {
            if let name = inputSourceManager.getInputSourceName(inputSource),
               let id = inputSourceManager.getInputSourceID(inputSource) {
                
                let item = NSMenuItem(title: name, action: #selector(setDefaultInputSource(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = inputSource
                
                if id.trimmingCharacters(in: .whitespacesAndNewlines) == currentDefaultID?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    item.state = .on
                }
                print("Checking input source: \(name) with ID: \(id)")
                defaultSourceSubmenu.addItem(item)
            }
        }
        
        defaultSourceItem.submenu = defaultSourceSubmenu
        menu.addItem(defaultSourceItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add toggle for application vs. window mode
        let modeTitle = isPerApplication ? "Switch to Per-Window Mode" : "Switch to Per-Application Mode"
        let modeItem = NSMenuItem(title: modeTitle, action: #selector(toggleMode), keyEquivalent: "")
        modeItem.target = self
        modeItem.tag = 1 // Tag for easy identification
        menu.addItem(modeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem.separator())
        
        // Clear all mappings
        let clearItem = NSMenuItem(title: "Clear All Mappings", action: #selector(clearMappings), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    // Handler for the status bar button; menu is shown automatically
    @objc func statusBarButtonClicked() {
        // Menu will show automatically
    }
    
    // Handler to switch between per-app and per-window mode
    @objc func toggleMode() {
        isPerApplication.toggle()
        windowMonitor.isPerApplication = isPerApplication
        windowMonitor.clearMappings()
        
        // Update menu item title instead of rebuilding entire menu
        if let menu = statusItem?.menu,
           let modeItem = menu.items.first(where: { $0.tag == 1 }) {
            modeItem.title = isPerApplication ? "Switch to Per-Window Mode" : "Switch to Per-Application Mode"
        }
        
        let mode = isPerApplication ? "per-application" : "per-window"
        print("Switched to \(mode) mode")
    }
    
    // Handler for when a user selects a new default input source
    @objc func setDefaultInputSource(_ sender: NSMenuItem) {
        let inputSource = sender.representedObject as! TISInputSource
        
        defaultInputSource = inputSource
        windowMonitor.defaultInputSource = defaultInputSource
        
        // Save to UserDefaults for persistence after restarts
        if let id = inputSourceManager.getInputSourceID(inputSource) {
            UserDefaults.standard.set(id, forKey: "DefaultInputSourceID")
            
            if let name = inputSourceManager.getInputSourceName(inputSource) {
                print("Default input source set to: \(name)")
            }
        }
        
        // Rebuild menu to update checkmarks
        setupMenu()
    }
    
    @objc func clearMappings() {
        windowMonitor.clearMappings()
        print("All mappings cleared")
    }
    
    // Loads the saved default input source, or sets current as default if none is saved
    func loadDefaultInputSource() {
        // Check if a default is saved in UserDefaults
        if let savedID = UserDefaults.standard.string(forKey: "DefaultInputSourceID") {
            defaultInputSource = inputSourceManager.getInputSourceByID(savedID)
        }
        
        // If not found or invalid, use the current input source
        if defaultInputSource == nil {
            defaultInputSource = inputSourceManager.getCurrentInputSource()
            
            // Save as new default for next launch
            if let currentSource = defaultInputSource,
               let id = inputSourceManager.getInputSourceID(currentSource) {
                UserDefaults.standard.set(id, forKey: "DefaultInputSourceID")
            }
        }
        
        if let defaultSource = defaultInputSource,
           let name = inputSourceManager.getInputSourceName(defaultSource) {
            print("Default input source loaded: \(name)")
        }
    }
    
    // Gets the input source ID of the default input source
    func getDefaultInputSourceID() -> String? {
        if let defaultSource = defaultInputSource {
            return inputSourceManager.getInputSourceID(defaultSource)
        }
        return nil
    }
    
    
    // Prompts the user for accessibility permissions if not granted
    func requestAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("Accessibility permissions required. Please grant them in System Preferences.")
            
            // Try to prompt for permissions first
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let promptResult = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            if !promptResult {
//                // Show additional alert with instructions
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//                    let alert = NSAlert()
//                    alert.messageText = "Accessibility Access Required"
//                    alert.informativeText = """
//                    KeyMider needs accessibility access to monitor window changes.
//                    
//                    If the app doesn't appear in the list:
//                    1. Click the '+' button in Accessibility preferences
//                    2. Navigate to your app and add it manually
//                    3. Make sure the checkbox is checked
//                    
//                    Then restart the app.
//                    """
//                    alert.addButton(withTitle: "Open System Preferences")
//                    alert.addButton(withTitle: "Quit App")
//                    
//                    if alert.runModal() == .alertFirstButtonReturn {
//                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
//                    }
//                    
//                    // Give user time to set permissions, then quit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApplication.shared.terminate(nil)
                    }
                }
//            }
        }
    }
}

// MARK: - WindowMonitorDelegate
extension AppDelegate: WindowMonitorDelegate {
    // Called when window/app focus changes
    func windowDidChange(identifier: String) {
        // Ensure we're on the main thread for UI operations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Get the stored input source for this window/app
            if let inputSource = self.windowMonitor.getInputSource(for: identifier) {
                self.inputSourceManager.switchToInputSource(inputSource)
            } else {
                // New window/app - use default input source
                if let defaultSource = self.defaultInputSource {
                    self.inputSourceManager.switchToInputSource(defaultSource)
                    self.windowMonitor.setInputSource(defaultSource, for: identifier)
                    
                    if let name = self.inputSourceManager.getInputSourceName(defaultSource) {
                        print("New app/window \(identifier) assigned default input source: \(name)")
                    }
                } else {
                    print("Warning: No default input source available for identifier: \(identifier)")
                }
            }
        }
    }
    
    // Called when window/app has closed
    func windowDidClose(identifier: String) {
        // Remove mapping when window/app closes
        windowMonitor.removeMapping(for: identifier)
    }
}

// MARK: - Input Source Manager
// Encapsulates all interactions with keyboard input sources
class InputSourceManager {
    
    // Returns the current active input source or nil if unavailable
    func getCurrentInputSource() -> TISInputSource? {
        guard let inputSource = TISCopyCurrentKeyboardInputSource() else {
            print("Failed to get current keyboard input source")
            return nil
        }
        return inputSource.takeUnretainedValue()
    }
    
    // Returns all available keyboard input sources
    func getAllInputSources() -> [TISInputSource] {
        guard let inputSources = TISCreateInputSourceList(nil, false) else {
            print("Failed to get input source list")
            return []
        }
        
        let inputSourceArray = inputSources.takeUnretainedValue() as! [TISInputSource]
        // Filter to include only keyboard input sources
        return inputSourceArray.filter { inputSource in
            return isKeyboardInputSource(inputSource)
        }
    }
    
    // Helper: Checks if input source is a keyboard input source
    private func isKeyboardInputSource(_ inputSource: TISInputSource) -> Bool {
        guard let category = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceCategory) else {
            return false
        }
        
        let categoryString = Unmanaged<CFString>.fromOpaque(category).takeUnretainedValue()
        let targetCategory = kTISCategoryKeyboardInputSource
        
        return CFStringCompare(categoryString, targetCategory, []) == .compareEqualTo
    }
    
    // Returns input source with the specified ID, or nil if not found
    func getInputSourceByID(_ id: String) -> TISInputSource? {
        let inputSources = getAllInputSources()
        return inputSources.first { inputSource in
            return getInputSourceID(inputSource) == id
        }
    }
    
    // Switches to the given input source, handling race condition flag
    func switchToInputSource(_ inputSource: TISInputSource) {
        // Set flag to prevent race conditions
        print("🔄 switchToInputSource called")
        if let windowMonitor = (NSApp.delegate as? AppDelegate)?.windowMonitor {
            windowMonitor.isCurrentlySwitching = true
        }
        
        let result = TISSelectInputSource(inputSource)
        
        // Log switch result for diagnostics
        if result == noErr {
            if let name = getInputSourceName(inputSource) {
                print("Successfully switched to input source: \(name)")
            } else {
                print("Successfully switched to input source (name unavailable)")
            }
        } else {
            print("Failed to switch input source with error: \(result)")
        }
        
        // Clear flag after short delay to prevent handling our own change notification
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let windowMonitor = (NSApp.delegate as? AppDelegate)?.windowMonitor {
                    windowMonitor.isCurrentlySwitching = false
                    windowMonitor.expectedInputSourceID = nil
                    print("Input source switching flag reset.")
                }
            }
    }
    
    // Gets the localized name of the input source, or nil if unavailable
    func getInputSourceName(_ inputSource: TISInputSource) -> String? {
        guard let nameProperty = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) else {
            return nil
        }
        
        let cfString = Unmanaged<CFString>.fromOpaque(nameProperty).takeUnretainedValue()
        return cfString as String
    }
    
    // Gets the input source ID string, or nil if unavailable
    func getInputSourceID(_ inputSource: TISInputSource) -> String? {
        guard let idProperty = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }
        
        let cfString = Unmanaged<CFString>.fromOpaque(idProperty).takeUnretainedValue()
        return cfString as String
    }
}

// MARK: - Window Monitor Protocol
// Used for receiving window/app focus change and close notifications
protocol WindowMonitorDelegate: AnyObject {
    func windowDidChange(identifier: String)
    func windowDidClose(identifier: String)
}

// MARK: - Window Monitor
// Monitors app/window focus, termination, and input source changes
class WindowMonitor {
    weak var delegate: WindowMonitorDelegate?
    var isPerApplication = false
    var defaultInputSource: TISInputSource?
    var isCurrentlySwitching = false
    var isFirstManualSwitch = true
    var expectedInputSourceID: String?
    

    private let mappingQueue = DispatchQueue(label: "com.KeyMider.mappings", attributes: .concurrent)
    private var _inputSourceMappings: [String: TISInputSource] = [:]
    private var currentIdentifier: String?

    private var appObservers: [pid_t: AXObserver] = [:]
    private var activeAppPIDs: Set<pid_t> = []
    var systemWideObserver: AXObserver?
    private let systemWideElement = AXUIElementCreateSystemWide()


    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        stopAXFocusMonitoring()
    }

    func startMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
            
        
        print("NSWorkspace monitoring started")
    }

    
    private func primeNotificationSystem() {
        print("🔧 Priming notification system...")
        
        guard let inputSourceManager = (delegate as? AppDelegate)?.inputSourceManager,
              let currentSource = inputSourceManager.getCurrentInputSource() else {
            print("🔧 ❌ Cannot prime - no input source manager")
            return
        }
        
        // Get all input sources
        let allSources = inputSourceManager.getAllInputSources()
        
        // Find a different input source to switch to temporarily
        if let otherSource = allSources.first(where: { source in
            inputSourceManager.getInputSourceID(source) != inputSourceManager.getInputSourceID(currentSource)
        }) {
            print("🔧 Switching to different input source temporarily to prime notifications")
            
            // Switch away and back to prime the notification system
            TISSelectInputSource(otherSource)
            
            // Switch back after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                TISSelectInputSource(currentSource)
                print("🔧 Notification system primed - returned to original input source")
            }
        } else {
            print("🔧 Only one input source available - cannot prime")
        }
    }
    
    func startAXFocusMonitoring() {
            print("Initializing AX focus monitoring for per-application changes...")
            // Register for application launch notification to add observers for new apps
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleApplicationLaunch(_:)),
                name: NSWorkspace.didLaunchApplicationNotification,
                object: nil
            )
            
            // Add observers for all currently running applications
        for app in NSWorkspace.shared.runningApplications {
                    // Monitor regular apps and accessory apps (includes menubar apps)
                    if app.activationPolicy == .regular || app.activationPolicy == .accessory {
                        addAXObserver(for: app)
                    }
                }
            print("AX focus monitoring initialized for existing applications.")
        }
    
    func stopAXFocusMonitoring() {
        if let observer = systemWideObserver {
            let notification = kAXFocusedUIElementChangedNotification as CFString
            AXObserverRemoveNotification(observer, systemWideElement, notification)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            systemWideObserver = nil
        }
        
        
            // Remove observer for application launch notifications
            NSWorkspace.shared.notificationCenter.removeObserver(
                self,
                name: NSWorkspace.didLaunchApplicationNotification,
                object: nil
            )

            // Remove all per-application AX observers
            for (_, observer) in appObservers {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            }
            appObservers.removeAll()
            activeAppPIDs.removeAll()
            print("AX focus monitoring stopped for all applications.")
        }
    
    // Handles focus changes from any observed application
        // 'observedElement' is the actual UI element that gained focus within an app.
        // 'observer' is the AXObserver associated with that app.
        func handleFocusChange(observedElement: AXUIElement, for observer: AXObserver) {
            var pid: pid_t = 0
            let getPidResult = AXUIElementGetPid(observedElement, &pid)

            guard getPidResult == .success, pid != 0 else {
                print("❌ handleFocusChange: Could not get PID for focused element.")
                return
            }


            guard let app = NSRunningApplication(processIdentifier: pid) else {
                print("❌ handleFocusChange: Could not find running application for pid: \(pid)")
                return
            }

            let newIdentifier = createIdentifier(for: app)

            // Only act if the identifier has truly changed to avoid redundant operations
            if currentIdentifier != newIdentifier {
                print("AX Focus changed from \(currentIdentifier ?? "none") to \(newIdentifier)")
                currentIdentifier = newIdentifier
                delegate?.windowDidChange(identifier: newIdentifier)
            }
            if isFirstManualSwitch == true {
                self.primeNotificationSystem()
                isFirstManualSwitch = false
            }
        }


        // MARK: - NSWorkspace Callbacks for Application Lifecycle

        @objc func handleApplicationLaunch(_ notification: Notification) {
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Only add observer for regular applications
            if app.activationPolicy == .regular {
                addAXObserver(for: app)
            }
        }
    
    
    @objc func applicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

        let identifier = createIdentifier(for: app)
//        runningApps[identifier] = app
        if appObservers[app.processIdentifier] == nil {
                     addAXObserver(for: app)
                }

        if currentIdentifier != identifier {
            print("NSWorkspace: Application focus changed from \(currentIdentifier ?? "none") to \(identifier)")
            currentIdentifier = identifier
            delegate?.windowDidChange(identifier: identifier)
        }
    }
    


    @objc func applicationDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let identifier = createIdentifier(for: app)

//        runningApps.removeValue(forKey: identifier)
        removeAXObserver(for: app.processIdentifier) // Remove the specific observer for this app
        delegate?.windowDidClose(identifier: identifier)
    }

    
    private func addAXObserver(for app: NSRunningApplication) {
            let pid = app.processIdentifier
            guard appObservers[pid] == nil else {
                // Observer already exists for this PID
                return
            }
            
        
        // Skip prohibited apps (like loginwindow)
            guard app.activationPolicy != .prohibited else {
            return
            }
        
            var observer: AXObserver?
            let context = Unmanaged.passUnretained(self).toOpaque()

            let createResult = AXObserverCreate(pid, accessibilityFocusChangeCallback, &observer)

            guard createResult == .success, let axObserver = observer else {
                print("❌ Failed to create AXObserver for PID \(pid) (\(app.localizedName ?? "Unknown")): \(createResult.rawValue)")
                return
            }

            // Store the observer
            appObservers[pid] = axObserver

            // Add observer to current run loop
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)

            // Get the application's AXUIElement
            let appElement = AXUIElementCreateApplication(pid)
            let notification = kAXFocusedUIElementChangedNotification as CFString

            // Add the notification for this specific application
            let addResult = AXObserverAddNotification(axObserver, appElement, notification, context)

            if addResult == .success {
                print("✅ Successfully added AX notification for \(notification) for app: \(app.localizedName ?? "Unknown") (PID: \(pid))")
                activeAppPIDs.insert(pid)
            } else {
                print("❌ Failed to add AX notification for \(notification) for app: \(app.localizedName ?? "Unknown") (PID: \(pid)). Error: \(addResult.rawValue). Removing observer.")
                // Clean up if adding notification fails
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
                appObservers.removeValue(forKey: pid)
            }
        }

        private func removeAXObserver(for pid: pid_t) {
            guard let observer = appObservers[pid] else {
                return // No observer for this PID
            }
            
            // Ensure pid is in the activeAppPIDs set before removing
            guard activeAppPIDs.contains(pid) else { return }

            let appElement = AXUIElementCreateApplication(pid)
            let notification = kAXFocusedUIElementChangedNotification as CFString

            // Attempt to remove the notification. It's okay if this fails,
            // as the app might already be gone.
            AXObserverRemoveNotification(observer, appElement, notification)
            
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            appObservers.removeValue(forKey: pid)
            activeAppPIDs.remove(pid)
            print("Removed AXObserver for PID: \(pid)")
        }

    @objc func inputSourceDidChange(_ notification: Notification) {
        print("🔔 inputSourceDidChange called! Notification object: \(notification)")

        if isCurrentlySwitching {
                print("Ignoring input source change (currently switching programmatically)")
                return
            }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            print("Change of the input source detected")

            guard let inputSourceManager = (self.delegate as? AppDelegate)?.inputSourceManager,
                  let newInputSource = inputSourceManager.getCurrentInputSource(),
                  let newInputSourceID = inputSourceManager.getInputSourceID(newInputSource) else {
                print("Failed to get current input source or inputSourceManager is nil.")
                return
            }
            
            // Check if this change matches what we expected from our programmatic switch
            if let expectedID = self.expectedInputSourceID,
               expectedID == newInputSourceID {
                print("Ignoring input source change (matches expected programmatic switch).")
                return
            }
            
            // If we reach here, it's a user-initiated change
            guard let currentId = self.currentIdentifier else {
                print("No current identifier to apply input source to.")
                return
            }
            
            self.setInputSource(newInputSource, for: currentId)
            
            if let name = inputSourceManager.getInputSourceName(newInputSource) {
                print("Input source manually changed to: \(name) for \(currentId)")
            }
        }
    }
    
    
    private func createIdentifier(for app: NSRunningApplication) -> String {
        let bundleID = app.bundleIdentifier ?? "unknown"
        if isPerApplication {
            return bundleID
        } else {
            return "\(bundleID)-\(app.processIdentifier)"
        }
    }

    func getInputSource(for identifier: String) -> TISInputSource? {
        return mappingQueue.sync {
            return _inputSourceMappings[identifier]
        }
    }

    func setInputSource(_ inputSource: TISInputSource, for identifier: String) {
        mappingQueue.async(flags: .barrier) { [weak self] in
            self?._inputSourceMappings[identifier] = inputSource
        }
        print("Stored input source for: \(identifier)")
    }

    func removeMapping(for identifier: String) {
        mappingQueue.async(flags: .barrier) { [weak self] in
            self?._inputSourceMappings.removeValue(forKey: identifier)
        }
        print("Removed mapping for: \(identifier)")
    }

    func clearMappings() {
        mappingQueue.async(flags: .barrier) { [weak self] in
            self?._inputSourceMappings.removeAll()
        }
        print("All mappings cleared")
    }
}
