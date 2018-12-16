#!/bin/bash

# Be verbose
set -x

sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt install p7zip-full # For Notepad++

# Get Wine
wget -c https://www.playonlinux.com/wine/binaries/linux-x86/PlayOnLinux-wine-3.5-linux-x86.pol

# Get old Wine (for icons and such)
# apt download libc6:i386
# ./W	dpkg -x wine*.deb .

# Download ALL the i386 dependencies of Wine down to glibc/libc6, but not Wine itself
# (we have a newer one)
URLS=$(apt-get --allow-unauthenticated -o Apt::Get::AllowUnauthenticated=true \
-o Debug::NoLocking=1 -o APT::Cache-Limit=125829120 -o Dir::Etc::sourceparts=- \
-o APT::Get::List-Cleanup=0 -o APT::Get::AllowUnauthenticated=1 \
-o Debug::pkgProblemResolver=true -o Debug::pkgDepCache::AutoInstall=true \
-o APT::Install-Recommends=0 -o APT::Install-Suggests=0 -y \
install --print-uris wine:i386 unionfs-fuse:i386 2>&1 | grep "_i386" | grep -v "wine" | cut -d "'" -f 2 )

wget -c $URLS

# Get unionfs-fuse to make shared read-only wineprefix usable for every user
# apt download unionfs-fuse

# Get suitable old ld-linux.so and the stuff that comes with it
# apt download libc6:i386 # It is already included above

mkdir -p ./Wine.AppDir
tar xfvj PlayOnLinux-wine-*-linux-x86.pol -C ./Wine.AppDir --strip-components=2 wineversion/ 
cd Wine.AppDir/

# Extract debs
find ../.. -name '*.deb' -exec dpkg -x {} . \;

# Make absolutely sure it will not load stuff from /lib or /usr
sed -i -e 's|/usr|/xxx|g' lib/ld-linux.so.2
sed -i -e 's|/usr/lib|/ooo/ooo|g' lib/ld-linux.so.2

# Remove duplicate (why is it there?)
rm -f lib/i386-linux-gnu/ld-*.so

# Get libhookexecv.so
wget -c https://github.com/probonopd/libhookexecv/releases/download/continuous/libhookexecv.so -O lib/libhookexecv.so

# Get patched wine-preload
wget -c https://github.com/Hackerl/Wine_Appimage/releases/download/testing/wine-preloader-patched.zip
unzip wine-preloader-patched.zip
mv wine-preloader bin/

# Clean
rm wine-preloader-patched.zip

# Write custom AppRun
cat > AppRun <<\EOF
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"

export LD_LIBRARY_PATH="$HERE/usr/lib":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/lib":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/lib/i386-linux-gnu":$LD_LIBRARY_PATH

# Sound Library
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu/pulseaudio":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu/alsa-lib":$LD_LIBRARY_PATH

# LD
export WINELDLIBRARY="$HERE/lib/ld-linux.so.2"

export WINEDLLOVERRIDES="mscoree,mshtml=" # Do not ask to install Mono or Gecko
export WINEDEBUG=-all # Do not print Wine debug messages

# Load Explorer if no arguments given
EXPLORER=""
if [ -z "$@" ] ; then
  EXPLORER="explorer.exe"
fi

# Load bundled WINEPREFIX if existing

MNT_WINEPREFIX="$HOME/.QQ.unionfs" # Use the name of the app
atexit()
{
  killall "$WINELDLIBRARY" && sleep 0.1 && rm -r "$MNT_WINEPREFIX"
}

if [ -d "$HERE/wineprefix" ] ; then
  RO_WINEPREFIX="$HERE/wineprefix" # WINEPREFIX in the AppDir
  TMP_WINEPREFIX_OVERLAY=/tmp/QQ # Use the name of the app
  mkdir -p "$MNT_WINEPREFIX" "$TMP_WINEPREFIX_OVERLAY"
  "$WINELDLIBRARY" "$HERE/usr/bin/unionfs-fuse" -o use_ino,nonempty,uid=$UID -ocow "$TMP_WINEPREFIX_OVERLAY"=RW:"$RO_WINEPREFIX"=RO "$MNT_WINEPREFIX" || exit 1
  export WINEPREFIX="$MNT_WINEPREFIX"
  echo "Using $HERE/wineprefix mounted to $WINEPREFIX"
  trap atexit EXIT
fi

LD_PRELOAD="$HERE/lib/libhookexecv.so" "$WINELDLIBRARY" "$HERE/bin/wine" "$@" "$EXPLORER" | cat
EOF
chmod +x AppRun

# Why is this needed? Probably because our Wine was compiled on a different distribution
( cd ./lib/i386-linux-gnu/ ; ln -s libudev.so.1 libudev.so.0 )
( cd ./usr/lib/i386-linux-gnu/ ; rm -f libpng12.so.0 ; ln -s ../../../lib/libpng12.so.0 . )
rm -rf lib64/

# Cannot move around share since Wine has the relative path to it; hence symlinking
# so that the desktop file etc. are in the correct place for desktop integration
cp -r usr/share share/ && rm -rf usr/share
( cd usr/ ; ln -s ../share . )

cp usr/share/applications/wine.desktop .

touch wine.svg # FIXME

export VERSION=$(strings ./lib/libwine.so.1 | grep wine-[\.0-9] | cut -d "-" -f 2)

cd ..

wget -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x ./appimagetool-x86_64.AppImage
ARCH=x86_64 ./appimagetool-x86_64.AppImage -g ./Wine.AppDir

#
# Wine AppImage DONE. Now making a wineprefix for Notepad++
#

export WINEDLLOVERRIDES="mscoree,mshtml="
mkdir -p ./Wine.AppDir/wineprefix
export WINEPREFIX=$(readlink -f ./Wine.AppDir/wineprefix)
./Wine*.AppImage wineboot

echo "disable" > "$WINEPREFIX/.update-timestamp" # Stop Wine from updating $WINEPREFIX automatically from time to time
( cd wineprefix/drive_c/ ; rm -rf users ; ln -s /home users ) # Do not hardcode username in wineprefix
ls -lh wineprefix/

wget -c "https://notepad-plus-plus.org/repository/7.x/7.6.1/npp.7.6.1.bin.minimalist.7z"
7z x -owineprefix/drive_c/windows/system32/ npp*.7z # system32 is on Windows $PATH equivalent

# Perhaps we can make this generic so as to convert all from portableapps.com in the same way
# wget -c "http://download3.portableapps.com/portableapps/Notepad++Portable/NotepadPlusPlusPortable_7.6.paf.exe"
# 7z x -y -otmp NotepadPlusPlusPortable_7.6.paf.exe 
# mv tmp/* "$WINEPREFIX/drive_c/windows/system32/"

sed -i -e 's|^Name=.*|Name=Notepad++|g' ./Wine.AppDir/*.desktop

ARCH=x86_64 ./appimagetool-x86_64.AppImage -g ./Wine.AppDir
