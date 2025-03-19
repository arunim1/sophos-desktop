import Cocoa
import Foundation
import UserNotifications
import SwiftUI
import Security
import Vision

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
        print("Starting screenshot capture")
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
            print("Will save temp screenshot to: \(tempFilePath)")
            task.arguments = ["-i", "-s", tempFilePath]
            
            task.terminationHandler = { [weak self] process in
                guard let self = self else { return }
                print("Screenshot process terminated with status: \(process.terminationStatus)")
                
                // Create a work item for the main queue
                let workItem = DispatchWorkItem {
                    // Check if the file exists (in case user canceled)
                    if FileManager.default.fileExists(atPath: tempFilePath) {
                        print("Screenshot file exists at \(tempFilePath)")
                        if let image = NSImage(contentsOfFile: tempFilePath) {
                            self.image = image
                            print("Loaded image: \(image.size.width)x\(image.size.height)")
                            
                            // Check if we should use Vision OCR to process the image
                            if self.useDescriptionAPI {
                                print("Processing with Vision OCR")
                                self.processImageWithVisionOCR(image)
                            } else {
                                print("Saving image as JSON without text recognition")
                                self.saveImageAsJson(image)
                                self.showNotification("Screenshot captured and saved!")
                                self.isProcessing = false
                            }
                            
                            // Clean up temp file
                            try? FileManager.default.removeItem(atPath: tempFilePath)
                        } else {
                            print("Failed to load image from \(tempFilePath)")
                            self.isProcessing = false
                        }
                    } else {
                        print("Screenshot file doesn't exist - user probably canceled")
                        self.isProcessing = false
                    }
                }
                
                // Execute the work item on the main queue
                DispatchQueue.main.async(execute: workItem)
            }
            
            do {
                print("Launching screencapture command...")
                try task.run()
            } catch {
                print("Error taking screenshot: \(error)")
                self.isProcessing = false
            }
        }
    }
    
    private func processImageWithVisionOCR(_ image: NSImage) {
        // Show processing notification
        self.showNotification("Processing image with OCR...")
        print("Starting Vision OCR processing")
        
        // Convert NSImage to CGImage for Vision processing
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to convert NSImage to CGImage")
            self.saveImageAsJson(image)
            self.showNotification("Failed to process image. Saved as base64 instead.")
            self.isProcessing = false
            return
        }
        
        // Create a Vision text recognition request
        let request = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let self = self else { return }
            
            // Process the results on the main queue
            DispatchQueue.main.async {
                if let error = error {
                    print("Vision OCR error: \(error.localizedDescription)")
                    self.saveImageAsJson(image)
                    self.showNotification("OCR failed: \(error.localizedDescription)")
                    self.isProcessing = false
                    return
                }
                
                // Get the text observations
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("No text observations found")
                    self.saveImageAsJson(image)
                    self.showNotification("No text found in image")
                    self.isProcessing = false
                    return
                }
                
                // Extract the text from the observations
                var recognizedText = ""
                let maximumCandidates = 1  // We only want the top candidate for each observation
                
                for observation in observations {
                    guard let candidate = observation.topCandidates(maximumCandidates).first else { continue }
                    recognizedText += candidate.string + "\n"
                }
                
                if recognizedText.isEmpty {
                    print("No text recognized")
                    self.saveImageAsJson(image)
                    self.showNotification("No text recognized in image")
                    self.isProcessing = false
                } else {
                    print("Text recognized: \(recognizedText.count) characters")
                    
                    // Check if we should also summarize with Claude
                    if let savedAPIKey = UserDefaults.standard.string(forKey: "anthropic_api_key"), !savedAPIKey.isEmpty {
                        // First save the OCR text
                        self.saveOCRTextAsJson(image, recognizedText)
                        self.showNotification("Text recognized. Summarizing with Claude...")
                        
                        // Then send to Claude for summarization
                        AnthropicAPI.shared.summarizeText(recognizedText) { [weak self] result in
                            guard let self = self else { return }
                            
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let summary):
                                    // Save both OCR text and summary
                                    self.saveSummaryAsJson(image, recognizedText, summary)
                                    self.showNotification("Text summarized by Claude!")
                                case .failure(let error):
                                    print("Failed to summarize: \(error.localizedDescription)")
                                    self.showNotification("OCR text saved. Summarization failed.")
                                }
                                self.isProcessing = false
                            }
                        }
                    } else {
                        // Just save the OCR results without summarization
                        self.saveOCRTextAsJson(image, recognizedText)
                        self.showNotification("Text recognized and saved!")
                        self.isProcessing = false
                    }
                }
            }
        }
        
        // Configure the request:
        // .accurate for better quality but slower processing
        // .fast for quicker results with potential lower accuracy
        request.recognitionLevel = .accurate
        
        // You can also set specific languages if needed
        // request.recognitionLanguages = ["en-US", "fr-FR"]
        
        // Vision requests can be customized further:
        request.usesLanguageCorrection = true  // Apply language correction to recognized text
        
        // Create an image request handler and perform the request
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try requestHandler.perform([request])
            print("Vision request performed successfully")
        } catch {
            print("Failed to perform Vision request: \(error)")
            DispatchQueue.main.async {
                self.saveImageAsJson(image)
                self.showNotification("OCR processing failed: \(error.localizedDescription)")
                self.isProcessing = false
            }
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
    
    private func saveOCRTextAsJson(_ image: NSImage, _ recognizedText: String) {
        // Create JSON dictionary with OCR text
        let json: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "recognizedText": recognizedText,
            "imageWidth": image.size.width,
            "imageHeight": image.size.height
        ]
        
        saveJson(json, prefix: "screenshot_ocr")
    }
    
    private func saveSummaryAsJson(_ image: NSImage, _ originalText: String, _ summary: String) {
        // Create JSON dictionary with both OCR text and Claude's summary
        let json: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "recognizedText": originalText,
            "summary": summary,
            "imageWidth": image.size.width,
            "imageHeight": image.size.height
        ]
        
        saveJson(json, prefix: "screenshot_summary")
    }
    
    private func saveJson(_ json: [String: Any], prefix: String) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            
            // Generate filename with timestamp
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "\(prefix)_\(timestamp).json"
            let fileURL = documentsPath.appendingPathComponent(filename)
            
            print("Trying to save JSON file to: \(fileURL.path)")
            print("Documents path is: \(documentsPath.path)")
            
            // Verify the directory exists
            if FileManager.default.fileExists(atPath: documentsPath.path) {
                print("Documents directory exists")
            } else {
                print("WARNING: Documents directory doesn't exist at \(documentsPath.path)")
                // Try to create it
                try FileManager.default.createDirectory(at: documentsPath, withIntermediateDirectories: true)
                print("Created documents directory")
            }
            
            try jsonData.write(to: fileURL)
            print("SUCCESS: Data saved to: \(fileURL.path)")
            
            // Verify the file was created
            if FileManager.default.fileExists(atPath: fileURL.path) {
                print("Verified: File exists at \(fileURL.path)")
                let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64 ?? 0
                print("File size: \(fileSize) bytes")
            } else {
                print("ERROR: File was not created at \(fileURL.path)")
            }
        } catch {
            print("ERROR saving JSON: \(error)")
            print("Error details: \(error.localizedDescription)")
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