import Cocoa
import Carbon

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
        print("=== KeyboardManager Starting ===")
        
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
        
        print("KeyboardManager started successfully!")
    }
    
    // Sets up the status bar icon and menu
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use SF Symbol for keyboard icon
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyboardManager")
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
                
                // Mark current default with checkmark
//                if id == currentDefaultID {
//                    item.state = .on
//                }
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
                // Show additional alert with instructions
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let alert = NSAlert()
                    alert.messageText = "Accessibility Access Required"
                    alert.informativeText = """
                    KeyboardManager needs accessibility access to monitor window changes.
                    
                    If the app doesn't appear in the list:
                    1. Click the '+' button in Accessibility preferences
                    2. Navigate to your app and add it manually
                    3. Make sure the checkbox is checked
                    
                    Then restart the app.
                    """
                    alert.addButton(withTitle: "Open System Preferences")
                    alert.addButton(withTitle: "Quit App")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    
                    // Give user time to set permissions, then quit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
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
        
        // FIXED: Safe casting using CFString comparison
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
            }
        }
    }
    
    // Gets the localized name of the input source, or nil if unavailable
    func getInputSourceName(_ inputSource: TISInputSource) -> String? {
        guard let nameProperty = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) else {
            return nil
        }
        
        // FIXED: Safe casting using CFString
        let cfString = Unmanaged<CFString>.fromOpaque(nameProperty).takeUnretainedValue()
        return cfString as String
    }
    
    // Gets the input source ID string, or nil if unavailable
    func getInputSourceID(_ inputSource: TISInputSource) -> String? {
        guard let idProperty = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }
        
        // FIXED: Safe casting using CFString
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
    var defaultInputSource: TISInputSource? // Default input source for new apps
    var isCurrentlySwitching = false // Flag to prevent race conditions during automatic switching
    
    // Thread-safe storage for input source mappings per identifier
    private let mappingQueue = DispatchQueue(label: "com.keyboardmanager.mappings", attributes: .concurrent)
    private var _inputSourceMappings: [String: TISInputSource] = [:]
    private var currentIdentifier: String? // The current focused identifier
    
    // Application monitoring
    private var runningApps: [String: NSRunningApplication] = [:]
    
    deinit {
        // Ensure observers are properly removed to prevent leaks
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    // Registers for notifications to monitor app focus, termination, and input source changes
    func startMonitoring() {
        // Monitor active application changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Monitor application termination
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        // Monitor input source changes
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceDidChange),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        
        print("Started monitoring applications and input source changes")
    }
    
    // Handler for app activation (focus change)
    @objc func applicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        let identifier = createIdentifier(for: app)
        
        // Store reference to running app for later cleanup
        runningApps[identifier] = app
        
        // Only process if this is a different identifier
        if currentIdentifier != identifier {
            print("Application focus changed from \(currentIdentifier ?? "none") to \(identifier)")
            currentIdentifier = identifier
            
            // Small delay to ensure the window focus change is complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.delegate?.windowDidChange(identifier: identifier)
            }
        }
    }
    
    // Handler for app termination, cleans up mappings
    @objc func applicationDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        let identifier = createIdentifier(for: app)
        
        // Remove from running apps
        runningApps.removeValue(forKey: identifier)
        
        // Clear mapping for this identifier
        delegate?.windowDidClose(identifier: identifier)
    }
    
    // Handler for keyboard input source changes
    @objc func inputSourceDidChange(_ notification: Notification) {
        // Add delay to prevent race conditions with window switching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // Only update mapping if we're not in the middle of switching
            guard !self.isCurrentlySwitching else {
                print("Ignoring input source change during automatic switching")
                return
            }
            
            guard let currentId = self.currentIdentifier else { return }
            
            // Get new input source and update mapping
            if let inputSourceManager = (self.delegate as? AppDelegate)?.inputSourceManager,
               let newInputSource = inputSourceManager.getCurrentInputSource() {
                
                // Update stored mapping for current identifier
                self.setInputSource(newInputSource, for: currentId)
                
                if let name = inputSourceManager.getInputSourceName(newInputSource) {
                    print("Input source manually changed to: \(name) for \(currentId)")
                }
            }
        }
    }
    
    // Creates a string identifier for app or window, based on mode
    private func createIdentifier(for app: NSRunningApplication) -> String {
        let bundleID = app.bundleIdentifier ?? "unknown"
        
        if isPerApplication {
            // Use only bundle ID for per-app mode
            return bundleID
        } else {
            // For per-window mode, include process ID for better uniqueness
            // Note: This still has limitations - true per-window would require Accessibility API
            return "\(bundleID)-\(app.processIdentifier)"
        }
    }
    
    // Thread-safe getter for input source mapping
    func getInputSource(for identifier: String) -> TISInputSource? {
        return mappingQueue.sync {
            return _inputSourceMappings[identifier]
        }
    }
    
    // Thread-safe setter for input source mapping
    func setInputSource(_ inputSource: TISInputSource, for identifier: String) {
        mappingQueue.async(flags: .barrier) { [weak self] in
            self?._inputSourceMappings[identifier] = inputSource
        }
        print("Stored input source for: \(identifier)")
    }
    
    // Thread-safe removal of mapping for an identifier
    func removeMapping(for identifier: String) {
        mappingQueue.async(flags: .barrier) { [weak self] in
            self?._inputSourceMappings.removeValue(forKey: identifier)
        }
        print("Removed mapping for: \(identifier)")
    }
    
    // Thread-safe clears all mappings
    func clearMappings() {
        mappingQueue.async(flags: .barrier) { [weak self] in
            self?._inputSourceMappings.removeAll()
        }
        print("All mappings cleared")
    }
}
