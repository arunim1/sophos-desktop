# Sophos Desktop iCloud Setup Instructions

This app has been updated to save files to iCloud Drive instead of the local Documents folder. To enable this functionality, you need to configure the app's entitlements in Xcode.

## Steps to Enable iCloud in Xcode

1. Open the project in Xcode
2. Select the project in the Project Navigator (left sidebar)
3. Select the "SophosScreenshot" target
4. Go to the "Signing & Capabilities" tab
5. Click the "+" button to add a capability
6. Search for and add "iCloud" capability
7. Under iCloud, check "iCloud Documents"
8. Make sure the container is set to "iCloud.com.sophos.desktop" (or create a new one)
9. Ensure the app is signed with your Apple Developer account

## How It Works

- The app will attempt to save files to the iCloud Drive in a folder called "Documents"
- If iCloud is not available, it will automatically fall back to the local Documents folder
- The UI will indicate where files are being saved

## Testing iCloud Integration

1. Build and run the app
2. Take a screenshot using Command+Shift+8
3. Check the console logs to see where the file is being saved
4. Verify that the files appear in iCloud Drive (may take a moment to sync)

## Troubleshooting

- If files are not appearing in iCloud, check the console logs to see if there are any errors
- Make sure your Mac is signed in to iCloud and iCloud Drive is enabled
- Verify that the app has the correct entitlements by examining the SophosDesktop.entitlements file

## Note for Development

The entitlements file has been created at:
`/SophosScreenshot/SophosScreenshot/SophosDesktop.entitlements`

You need to select this file in Xcode as the entitlements file for the target.
