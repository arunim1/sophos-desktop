# SophosScreenshot

A macOS menubar application for capturing screenshots with Anthropic Claude AI integration. The app uses OCR to extract text from screenshots and then generates flashcards using Claude's API.

## Features

- Lives in the macOS menu bar
- Not visible in the dock (LSUIElement = true)
- System-wide global keyboard shortcut (Command-Shift-8) to capture screenshots
- Interactive screenshot selection (select any area of the screen)
- OCR text extraction from images
- AI-powered flashcard generation using Anthropic's Claude API
- Securely stores your Anthropic API key in the macOS keychain
- Option to capture full screen context for better AI understanding
- Shows notification when screenshot is captured and processed
- Saves results as JSON files in the Documents folder or iCloud Drive

## How to Use

1. Build and run the application in Xcode
2. Look for the camera icon in the macOS menu bar
3. Click the icon to show the popover interface
4. Enter your Anthropic API key to enable AI features
5. Use Command-Shift-8 to capture a screenshot from anywhere in the system
6. Screenshots are processed with OCR, sent to Claude, and saved to your Documents folder or iCloud Drive

## Installation

1. Clone this repository
2. Open `SophosScreenshot.xcodeproj` in Xcode
3. Build and run the project

## Requirements

- macOS 12.0+
- Xcode 13.0+
- Swift 5.0+
- An Anthropic API key (https://console.anthropic.com/)

## Configuration

The app can be configured through the popover interface:

- **Claude API Key**: Required for AI features. The key is securely stored in the macOS keychain.
- **Capture full screen as context**: When enabled, the app will capture the full screen to provide additional context to Claude.

## JSON Output Formats

The app creates several types of JSON files:

### Flashcard Files

```json
{
  "timestamp": 1616775377.123456,
  "cardIndex": 0,
  "type": "Basic",
  "front": "Question or prompt",
  "back": "Answer or information",
  "imageWidth": 1920,
  "imageHeight": 1080
}
```

### OCR Text Files

```json
{
  "timestamp": 1616775377.123456,
  "recognizedText": "Text extracted from the screenshot",
  "imageWidth": 1920,
  "imageHeight": 1080
}
```

### Base64 Image Files (when OCR fails)

```json
{
  "timestamp": 1616775377.123456,
  "imageData": "base64_encoded_string_here..."
}
```

## Technical Details

- Written in Swift using AppKit and SwiftUI
- Uses NSStatusItem for menu bar integration
- Uses Carbon's HotKey API for reliable system-wide shortcuts
- Captures screenshots using the macOS screencapture utility
- Uses Vision framework for OCR text recognition
- Integrates with Anthropic's Claude API for flashcard generation
- Securely stores API key in macOS Keychain
- Uses UNUserNotificationCenter for notifications
- Supports iCloud Drive for file storage

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- [Anthropic](https://www.anthropic.com/) for the Claude API
- [SwiftAnthropic](https://github.com/gavinbains/swift-anthropic) for the Swift Claude API client