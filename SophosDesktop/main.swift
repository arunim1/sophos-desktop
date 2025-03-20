import Cocoa
import UserNotifications

// Set up default preferences
if UserDefaults.standard.object(forKey: "useDescriptionAPI") == nil {
    UserDefaults.standard.set(true, forKey: "useDescriptionAPI")
}

// Request notification permissions at startup
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

// Create an instance of NSApplication and set the delegate
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Run the app
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)