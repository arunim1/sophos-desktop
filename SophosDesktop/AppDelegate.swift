import Cocoa
import SwiftUI
import Carbon
import Security
import UserNotifications

// MARK: - NSImage Extension for Rotation
extension NSImage {
    func rotated(by degrees: CGFloat) -> NSImage? {
        // Swap width and height for a 90° rotation
        let newSize = NSSize(width: self.size.height, height: self.size.width)
        let rotatedImage = NSImage(size: newSize)
        
        rotatedImage.lockFocus()
        
        // Set up an affine transform to rotate the image
        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byDegrees: degrees)
        transform.translateX(by: -self.size.width / 2, yBy: -self.size.height / 2)
        transform.concat()
        
        // Draw the original image into the transformed context
        self.draw(at: NSZeroPoint,
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        
        rotatedImage.unlockFocus()
        // Set the template property to true to preserve system-color awareness
        rotatedImage.isTemplate = true
        return rotatedImage
    }
}


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
        
        // Request notification permissions early
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }

        
        
        // Set up the menu bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem.button {
            // Attempt to load the SF Symbol and rotate it by 90°
            if let image = NSImage(systemSymbolName: "point.topleft.down.to.point.bottomright.curvepath",
                                accessibilityDescription: "Custom rotated curve path"),
            let rotatedImage = image.rotated(by: -90) {
                button.image = rotatedImage
            } else {
                // Fallback image if symbol or rotation fails
                button.image = NSImage(named: "MenuIcon") ?? NSImage(systemSymbolName: "camera", accessibilityDescription: "Sophos Desktop")
            }
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
        
        // Test save location access (iCloud or Documents)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        print("Documents path: \(documentsPath.path)")
        
        if FileManager.default.fileExists(atPath: documentsPath.path) {
            print("Documents folder exists and is accessible")
        } else {
            print("WARNING: Documents folder doesn't exist or isn't accessible")
        }
        
        // Check iCloud availability
        if let iCloudContainerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            print("iCloud is available at: \(iCloudContainerURL.path)")
            
            // Create Documents directory in iCloud if it doesn't exist
            let iCloudDocumentsURL = iCloudContainerURL.appendingPathComponent("Documents")
            if !FileManager.default.fileExists(atPath: iCloudDocumentsURL.path) {
                do {
                    try FileManager.default.createDirectory(at: iCloudDocumentsURL, withIntermediateDirectories: true, attributes: nil)
                    print("Created iCloud Documents directory at: \(iCloudDocumentsURL.path)")
                } catch {
                    print("Error creating iCloud Documents directory: \(error)")
                }
            }
        } else {
            print("iCloud is not available, will use local Documents directory instead")
        }
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
                print("Hotkey triggered - capturing screenshot")
                self.screenshotManager.captureScreenSelection()
            }
        }
        
        print("Global shortcut registered: Command+Shift+8")
    }
}