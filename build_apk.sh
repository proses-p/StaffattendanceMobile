#!/bin/bash

# 1. Soma faili la pubspec.yaml
PUBSPEC="pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
    echo "Faili la pubspec.yaml halionekani!"
    exit 1
fi

# 2. Tafuta mstari wenye 'version:' (mfano: version: 1.0.0+5)
VERSION_LINE=$(grep "^version:" "$PUBSPEC")
echo "Version ya sasa: $VERSION_LINE"

# 3. Gawanya version name na build number (ambayo ipo baada ya alama ya +)
VERSION_NAME=$(echo "$VERSION_LINE" | cut -d' ' -f2 | cut -d'+' -f1)
BUILD_NUM=$(echo "$VERSION_LINE" | cut -d'+' -f2)

# 4. Ongeza namba ya build kwa 1 (Auto Increment)
NEW_BUILD_NUM=$((BUILD_NUM + 1))
NEW_VERSION="$VERSION_NAME+$NEW_BUILD_NUM"

echo "Inabadilisha kwenda version mpya: $NEW_VERSION"

# 5. Badilisha kwenye pubspec.yaml automatically
if [[ "$OSTYPE" == "darwin"* ]]; then
    # MacOS
    sed -i '' "s/^version:.*/version: $NEW_VERSION/" "$PUBSPEC"
else
    # Linux
    sed -i "s/^version:.*/version: $NEW_VERSION/" "$PUBSPEC"
fi

# 6. Safisha na u-build APK ya release
echo "Hello Proses subiri kidogo Inasafisha na ku-build APK mpya..."
flutter clean
flutter pub get
flutter build apk --release

echo "=== Imekamilisha! APK mpya imetengenezwa na Version imepandishwa kuwa $NEW_VERSION ==="