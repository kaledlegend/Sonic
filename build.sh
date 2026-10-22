#!/bin/bash
set -eo pipefail
mkdir -p GameData
cat Data.rsdk.part* > GameData/Data.rsdk
unzip -qo extras.zip -d GameData
mkdir -p engine/dependencies/ios
cp GameData/Data.rsdk engine/dependencies/ios/Data.rsdk
echo "== dependencies/ios contents =="
ls -la engine/dependencies/ios
echo "== Xcode projects found =="
find engine -name "*.xcodeproj" -not -path "*/dependencies/*" | tee projs.txt
PROJ=$(grep -i ios projs.txt | head -1 || true)
[ -z "$PROJ" ] && PROJ=$(head -1 projs.txt)
echo "Using: $PROJ"
xcodebuild -list -project "$PROJ" || true
SCHEME=$(xcodebuild -list -project "$PROJ" -json | python3 -c "import sys,json;d=json.load(sys.stdin)['project'];s=d['schemes'];print(next((x for x in s if 'ios' in x.lower()),s[0]))")
echo "Scheme: $SCHEME"
xcodebuild -project "$PROJ" -scheme "$SCHEME" -sdk iphoneos -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
APP=$(find build -name "*.app" -path "*Release-iphoneos*" | head -1)
echo "APP: $APP"
cp GameData/Data.rsdk "$APP/"
cp GameData/settings.ini "$APP/"
cp -r GameData/Mods "$APP/"
PL="$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Add :UIFileSharingEnabled bool true" "$PL" || true
/usr/libexec/PlistBuddy -c "Add :LSSupportsOpeningDocumentsInPlace bool true" "$PL" || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'Sonic Forever'" "$PL" || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 'Sonic Forever'" "$PL"
rm -rf Payload && mkdir Payload && cp -r "$APP" Payload/
zip -qr SonicForever.ipa Payload
ls -lh SonicForever.ipa
