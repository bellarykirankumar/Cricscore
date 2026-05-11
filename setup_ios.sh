#!/bin/bash
# Run this after flutter pub get and before building for iOS

echo "Setting up iOS configuration..."

# Fix Info.plist
PLIST="ios/Runner/Info.plist"

# Add privacy strings if not already present
if ! grep -q "NSCameraUsageDescription" "$PLIST"; then
python3 << 'PYEOF'
import re
with open('ios/Runner/Info.plist', 'r') as f:
    content = f.read()

additions = """
	<key>NSCameraUsageDescription</key>
	<string>CricScore uses the camera to record match deliveries for AI-assisted scoring.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>CricScore accesses your photo library to attach match videos and images.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>CricScore uses the microphone to record audio during match video capture.</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
"""
content = content.replace('</dict>\n</plist>', additions + '</dict>\n</plist>')
with open('ios/Runner/Info.plist', 'w') as f:
    f.write(content)
print("Info.plist updated successfully")
PYEOF
fi

echo "iOS setup complete!"
echo ""
echo "Next steps:"
echo "1. Open Xcode: open ios/Runner.xcworkspace"
echo "2. Set Team to: Kiran Kumar Bellary (Developer Team)"
echo "3. Set Bundle ID to: com.bellark.cricscore"
echo "4. Run: flutter run"
