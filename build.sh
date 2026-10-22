#!/bin/bash
set -eo pipefail
ROOT=$PWD
DEP=$ROOT/engine/dependencies/ios
SDKP=$(xcrun --sdk iphoneos --show-sdk-path)
MINV=13.0
CC="xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=$MINV -isysroot $SDKP"

echo "== [0] game data =="
mkdir -p GameData
cat Data.rsdk.part* > GameData/Data.rsdk
unzip -qo extras.zip -d GameData
mkdir -p "$DEP"
cp GameData/Data.rsdk "$DEP/Data.rsdk"
ls -la "$DEP"
echo "== dependencies.txt =="; cat "$DEP/dependencies.txt" || true

mkplist() { # dir exec id
cat > "$1/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$2</string>
<key>CFBundleIdentifier</key><string>$3</string>
<key>CFBundleName</key><string>$2</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>$MINV</string>
</dict></plist>
PL
}

echo "== [1/4] SDL2 framework =="
git clone --depth 1 --branch release-2.30.9 https://github.com/libsdl-org/SDL.git sdl \
  || git clone --depth 1 --branch SDL2 https://github.com/libsdl-org/SDL.git sdl
SDLPROJ=sdl/Xcode/SDL/SDL.xcodeproj
xcodebuild -list -project "$SDLPROJ" || true
TGT=$(xcodebuild -list -project "$SDLPROJ" | sed -n '/Targets:/,/Build Configurations:/p' | sed 's/^ *//' | grep -i framework | grep -i ios | grep -vi xc | head -1 || true)
[ -z "$TGT" ] && TGT=$(xcodebuild -list -project "$SDLPROJ" | sed 's/^ *//' | grep -i framework | grep -i ios | head -1 || true)
echo "SDL target: $TGT"
[ -z "$TGT" ] && { echo "ERROR: no SDL iOS framework target found"; exit 1; }
xcodebuild -project "$SDLPROJ" -target "$TGT" -configuration Release -sdk iphoneos \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO IPHONEOS_DEPLOYMENT_TARGET=$MINV \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  SYMROOT="$ROOT/sdlbuild" build
SDLFW=$(find sdlbuild -type d -name SDL2.framework | grep -i iphoneos | head -1)
echo "SDL framework: $SDLFW"
rm -rf "$DEP/SDL2.framework"; cp -R "$SDLFW" "$DEP/"

echo "== [2/4] libSDLMain.a =="
$CC -c -I sdl/include sdl/src/main/uikit/SDL_uikit_main.c -o uikit_main.o
ar rcs "$DEP/libSDLMain.a" uikit_main.o

echo "== [3/4] Ogg framework =="
git clone --depth 1 --branch v1.3.5 https://github.com/xiph/ogg.git ogg
cat > ogg/include/ogg/config_types.h <<'EOF'
#ifndef __CONFIG_TYPES_H__
#define __CONFIG_TYPES_H__
#include <stdint.h>
typedef int16_t ogg_int16_t;
typedef uint16_t ogg_uint16_t;
typedef int32_t ogg_int32_t;
typedef uint32_t ogg_uint32_t;
typedef int64_t ogg_int64_t;
typedef uint64_t ogg_uint64_t;
#endif
EOF
OFW="$DEP/Ogg.framework"; rm -rf "$OFW"; mkdir -p "$OFW/Headers/ogg"
$CC -dynamiclib -O2 -fPIC -w -I ogg/include -install_name @rpath/Ogg.framework/Ogg \
  -o "$OFW/Ogg" ogg/src/bitwise.c ogg/src/framing.c
cp ogg/include/ogg/*.h "$OFW/Headers/ogg/"
cp ogg/include/ogg/*.h "$OFW/Headers/"
mkplist "$OFW" Ogg org.xiph.ogg

echo "== [4/4] Vorbis framework =="
git clone --depth 1 --branch v1.3.7 https://github.com/xiph/vorbis.git vorbis
VFW="$DEP/Vorbis.framework"; rm -rf "$VFW"; mkdir -p "$VFW/Headers/vorbis"
VSRC=$(ls vorbis/lib/*.c | grep -v -E "barkmel|psytune|tone|misc")
$CC -dynamiclib -O2 -fPIC -w -I vorbis/include -I vorbis/lib -I "$OFW/Headers" \
  -F "$DEP" -framework Ogg -install_name @rpath/Vorbis.framework/Vorbis \
  -o "$VFW/Vorbis" $VSRC
cp vorbis/include/vorbis/*.h "$VFW/Headers/vorbis/"
cp vorbis/include/vorbis/*.h "$VFW/Headers/"
mkplist "$VFW" Vorbis org.xiph.vorbis
ls -la "$DEP"

echo "== Patching GL headers for iOS =="
python3 - <<'PY'
p='engine/RSDKv4/RetroEngine.hpp'
s=open(p).read()
old='#include <GL/glew.h>'
new='#if RETRO_PLATFORM == RETRO_iOS\n#include <OpenGLES/ES1/gl.h>\n#include <OpenGLES/ES1/glext.h>\n#else\n#include <GL/glew.h>\n#endif'
print('glew includes patched:', s.count(old))
open(p,'w').write(s.replace(old,new))
PY
echo "== RetroEngine.hpp 125-240 =="
sed -n 125,240p engine/RSDKv4/RetroEngine.hpp
echo "== end =="

PROJ="engine/RSDKv4 ios.xcodeproj"
echo "Using: $PROJ"
xcodebuild -project "$PROJ" -scheme RSDKv4 -sdk iphoneos -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  'OTHER_CFLAGS=$(inherited) -D__IPHONEOS__=1' \
  'OTHER_CPLUSPLUSFLAGS=$(inherited) -D__IPHONEOS__=1 -DGLES_SILENCE_DEPRECATION=1' \
  "HEADER_SEARCH_PATHS=\$(inherited) $DEP/SDL2.framework/Headers $DEP/Ogg.framework/Headers $DEP/Vorbis.framework/Headers" \
  "FRAMEWORK_SEARCH_PATHS=\$(inherited) $DEP" \
  "LIBRARY_SEARCH_PATHS=\$(inherited) $DEP" \
  build

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
