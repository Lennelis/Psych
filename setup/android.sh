#!/bin/sh
# SETUP FOR BUILDING THE ANDROID APK (Linux and macOS)
# You need Haxe 4.3.4 or newer installed first: https://haxe.org/download
# The Android SDK, NDK and JDK are separate - see docs/MOBILE.md
set -e

echo Installing dependencies...
echo This might take a few moments depending on your internet speed.
haxelib install hxcpp
haxelib install lime 8.1.2
haxelib install openfl 9.3.3
haxelib install flixel 5.6.1
haxelib install flixel-addons 3.2.2
haxelib install flixel-tools 1.5.1
haxelib install hscript-iris 1.1.3
haxelib install tjson 1.4.0
haxelib install hxvlc 2.0.1 --skip-dependencies
haxelib set lime 8.1.2
haxelib set openfl 9.3.3
haxelib git flxanimate https://github.com/Dot-Stuff/flxanimate 768740a56b26aa0c072720e0d1236b94afe68e3e
haxelib git linc_luajit https://github.com/superpowers04/linc_luajit 1906c4a96f6bb6df66562b3f24c62f4c5bba14a7
haxelib git funkin.vis https://github.com/FunkinCrew/funkVis 22b1ce089dd924f15cdc4632397ef3504d464e90
haxelib git grig.audio https://gitlab.com/haxe-grig/grig.audio.git cbf91e2180fd2e374924fe74844086aab7891666

# Gives the port Context.getExternalFilesDir(), which is how it finds a writable
# folder on the device. Android-only; nothing else needs it.
haxelib git extension-androidtools https://github.com/MAJigsaw77/extension-androidtools.git

# hxdiscord_rpc is deliberately absent: DISCORD_ALLOWED is off for mobile, and the
# library has no Android build.

echo
echo Checking the Android toolchain...
# `lime setup android` asks for these interactively and writes them to ~/.lime/config.xml.
# Lime also reads them straight from the environment, which is what makes an
# unattended setup (and CI) possible.
if [ -z "$ANDROID_SDK" ] && [ -n "$ANDROID_HOME" ]; then
	ANDROID_SDK="$ANDROID_HOME"
fi

MISSING=""
if [ -z "$ANDROID_SDK" ]; then MISSING="$MISSING ANDROID_SDK"; fi
if [ -z "$ANDROID_NDK_ROOT" ]; then MISSING="$MISSING ANDROID_NDK_ROOT"; fi
if [ -z "$JAVA_HOME" ]; then MISSING="$MISSING JAVA_HOME"; fi

if [ -n "$MISSING" ]; then
	echo "Not set:$MISSING"
	echo
	echo "Set them in your shell, for example:"
	echo "  export ANDROID_SDK=\$HOME/Android/Sdk"
	echo "  export ANDROID_NDK_ROOT=\$HOME/Android/Sdk/ndk/21.4.7075529"
	echo "  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"
	echo
	echo "Or run 'haxelib run lime setup android' and answer its questions instead."
	echo "Either way, see docs/MOBILE.md for which versions to install."
else
	echo "ANDROID_SDK       $ANDROID_SDK"
	echo "ANDROID_NDK_ROOT  $ANDROID_NDK_ROOT"
	echo "JAVA_HOME         $JAVA_HOME"
fi

echo
echo Finished!
