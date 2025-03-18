import Cocoa
import SwiftUI
import Carbon
import Security

// Carbon-based HotKey implementation for global shortcuts
class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID()
    private var keyDownHandler: (() -> Void)?
    
    init(keyCode: Int, modifiers: Int, keyDownHandler: @escaping () -> Void) {
        // Generate a unique ID for this hotkey
        hotKeyID.signature = fourCharCode("SOPH")
        hotKeyID.id = UInt32(keyCode)
        
        self.keyDownHandler = keyDownHandler
        
        // Register for events
        registerEventHandler()
        
        // Register the hotkey
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("Error registering hotkey: \(status)")
        }
    }
    
    deinit {
        unregister()
    }
    
    func unregister() {
        guard let hotKeyRef = hotKeyRef else { return }
        
        let status = UnregisterEventHotKey(hotKeyRef)
        if status != noErr {
            print("Error unregistering hotkey: \(status)")
        }
        
        self.hotKeyRef = nil
    }
    
    private func registerEventHandler() {
        // Create the callback
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // Install handler
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                
                // Extract hotkey reference from user data
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                
                // Extract hotkey ID from event
                var eventHotKeyID = EventHotKeyID()
                let error = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )
                
                // Check if the hotkey ID matches
                if error == noErr && eventHotKeyID.id == hotKey.hotKeyID.id {
                    hotKey.keyDownHandler?()
                    return noErr
                }
                
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
    
    // Helper to convert a four-character string to OSType
    private func fourCharCode(_ string: String) -> OSType {
        guard string.count == 4 else { return 0 }
        
        var result: UInt32 = 0
        for char in string.utf8 {
            result = (result << 8) + UInt32(char)
        }
        return result
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var screenshotManager: ScreenshotManager!
    var globalHotKey: HotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize screenshot manager
        screenshotManager = ScreenshotManager()
        
        // Set up the menu bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "Screenshot Tool")
            button.action = #selector(togglePopover)
        }
        
        // Set up the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        
        // Connect the ContentView
        let contentView = ContentView()
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Register global shortcut
        registerGlobalShortcut()
    }
    
    @objc func togglePopover() {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    func registerGlobalShortcut() {
        // Key code 28 is the '8' key
        // Use Carbon modifier constants for Command (cmdKey) and Shift (shiftKey)
        let modifiers = Int(cmdKey | shiftKey)
        
        globalHotKey = HotKey(keyCode: 28, modifiers: modifiers) {
            DispatchQueue.main.async {
                self.screenshotManager.captureScreenSelection()
            }
        }
        
        print("Global shortcut registered: Command+Shift+8")
    }
}