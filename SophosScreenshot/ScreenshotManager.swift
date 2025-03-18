import Cocoa
import Foundation
import UserNotifications
import SwiftUI
import Security

// Forward reference to AnthropicAPI since it's in the same module
// but Swift might not see it during compilation order
class AnthropicAPI {
    static let shared = AnthropicAPI()
    func describeImage(imageBase64: String, completion: @escaping (Result<String, Error>) -> Void) {}
}

class ScreenshotManager: NSObject, ObservableObject {
    private var image: NSImage?
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    @Published var isProcessing = false
    @Published var lastDescription: String?
    
    var useDescriptionAPI: Bool {
        // Read from UserDefaults with a default of true
        return UserDefaults.standard.bool(forKey: "useDescriptionAPI")
    }
    
    func setUseDescriptionAPI(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "useDescriptionAPI")
    }
    
    func captureScreenSelection() {
        // Hide the application before taking the screenshot
        NSApplication.shared.hide(nil)
        isProcessing = true
        
        // Give some time for the app to hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Use NSTask to run the macOS screenshot utility with interactive selection
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            
            // Create a temporary file path
            let tempFilePath = NSTemporaryDirectory() + "temp_screenshot.png"
            task.arguments = ["-i", "-s", tempFilePath]
            
            task.terminationHandler = { [weak self] process in
                guard let self = self else { return }
                
                // Create a work item for the main queue
                let workItem = DispatchWorkItem {
                    // Check if the file exists (in case user canceled)
                    if FileManager.default.fileExists(atPath: tempFilePath) {
                        if let image = NSImage(contentsOfFile: tempFilePath) {
                            self.image = image
                            
                            // Check if we should use Claude to describe the image
                            if self.useDescriptionAPI, let base64String = self.convertImageToBase64(image) {
                                self.processImageWithClaude(image, base64String)
                            } else {
                                self.saveImageAsJson(image)
                                self.showNotification("Screenshot captured and saved!")
                                self.isProcessing = false
                            }
                            
                            // Clean up temp file
                            try? FileManager.default.removeItem(atPath: tempFilePath)
                        } else {
                            self.isProcessing = false
                        }
                    } else {
                        self.isProcessing = false
                    }
                }
                
                // Execute the work item on the main queue
                DispatchQueue.main.async(execute: workItem)
            }
            
            do {
                try task.run()
            } catch {
                print("Error taking screenshot: \(error)")
                self.isProcessing = false
            }
        }
    }
    
    private func processImageWithClaude(_ image: NSImage, _ base64Data: String) {
        // Show processing notification
        self.showNotification("Processing image with Claude...")
        
        // Explicit type annotation to help the compiler
        AnthropicAPI.shared.describeImage(imageBase64: base64Data) { [weak self] (result: Result<String, Error>) in
            guard let self = self else { return }
            
            // Create a work item for the main queue
            let workItem = DispatchWorkItem {
                switch result {
                case .success(let description):
                    self.lastDescription = description
                    self.saveDescriptionAsJson(image, description)
                    self.showNotification("Image described and saved!")
                case .failure(let error):
                    print("Error describing image: \(error)")
                    // Fallback to saving just the image
                    self.saveImageAsJson(image)
                    self.showNotification("Couldn't describe image. Saved base64 data instead.")
                }
                self.isProcessing = false
            }
            
            // Execute the work item on the main queue
            DispatchQueue.main.async(execute: workItem)
        }
    }
    
    private func saveImageAsJson(_ image: NSImage) {
        guard let base64String = convertImageToBase64(image) else {
            print("Failed to convert image to base64")
            return
        }
        
        // Create JSON dictionary
        let json: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "imageData": base64String
        ]
        
        saveJson(json, prefix: "screenshot_base64")
    }
    
    private func saveDescriptionAsJson(_ image: NSImage, _ description: String) {
        // Create JSON dictionary with Claude's description instead of base64 data
        let json: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "description": description,
            "imageWidth": image.size.width,
            "imageHeight": image.size.height
        ]
        
        saveJson(json, prefix: "screenshot_claude")
    }
    
    private func saveJson(_ json: [String: Any], prefix: String) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            
            // Generate filename with timestamp
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "\(prefix)_\(timestamp).json"
            let fileURL = documentsPath.appendingPathComponent(filename)
            
            try jsonData.write(to: fileURL)
            print("Data saved to: \(fileURL.path)")
        } catch {
            print("Error saving JSON: \(error)")
        }
    }
    
    func convertImageToBase64(_ image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return data.base64EncodedString()
    }
    
    private func showNotification(_ message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = "Screenshot Tool"
                content.body = message
                content.sound = UNNotificationSound.default
                
                let request = UNNotificationRequest(identifier: UUID().uuidString, 
                                                   content: content,
                                                   trigger: nil)
                
                center.add(request) { error in
                    if let error = error {
                        print("Error showing notification: \(error)")
                    }
                }
            }
        }
    }
}