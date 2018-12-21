#!/bin/bash

# Be verbose
set -x

# sudo add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"
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
install --print-uris wine:i386 | grep "_i386" | grep -v "wine" | cut -d "'" -f 2 )

wget -c $URLS

# Get unionfs-fuse to make shared read-only wineprefix usable for every user
apt download fuse unionfs-fuse libfuse2 # 32-bit versions seemingly do not work properly on 64-bit machines

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

# Workaround for:
# p11-kit: couldn't load module
rm usr/lib/i386-linux-gnu/libp11-* || true
find squashfs-root/ -path '*libp11*' -delete || true

# Get libhookexecv.so
cp ../libhookexecv.so lib/libhookexecv.so

# Get wine-preloader_hook
cp ../wine-preloader_hook bin/
chmod +x bin/wine-preloader_hook

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

# Workaround for: wine: loadlocale.c:129: _nl_intern_locale_data:
# Assertion `cnt < (sizeof (_nl_value_type_LC_TIME) / sizeof (_nl_value_type_LC_TIME[0]))' failed.
export LC_ALL=C LANGUAGE=C

# Load Explorer if no arguments given
APPLICATION=""
if [ -z "$*" ] ; then
  APPLICATION="winecfg"
fi

MNT_WINEPREFIX="/tmp/.AppName.unionfs" # TODO: Use the name of the app

# Load bundled WINEPREFIX if existing and if $WINEPREFIX is not set
if [ -d "$HERE/wineprefix" ] && [ -z "$WINEPREFIX" ] ; then
  RO_WINEPREFIX="$HERE/wineprefix" # WINEPREFIX in the AppDir
  RW_WINEPREFIX_OVERLAY="$HOME/.AppName" # TODO: Use the name of the app
  mkdir -p "$MNT_WINEPREFIX" "$RW_WINEPREFIX_OVERLAY"
  "$HERE/usr/bin/unionfs-fuse" -o use_ino,uid=$UID -ocow "$RW_WINEPREFIX_OVERLAY"=RW:"$RO_WINEPREFIX"=RO "$MNT_WINEPREFIX" || exit 1
  export WINEPREFIX="$MNT_WINEPREFIX"
  echo "Using $HERE/wineprefix mounted to $WINEPREFIX"
  trap atexit EXIT
fi

atexit()
{
  while pgrep -f "$HERE/bin/wineserver" ; do sleep 1 ; done
  pkill -f "$HERE/usr/bin/unionfs-fuse"
}

# LANG=C is a workaround for: "wine: loadlocale.c:129: _nl_intern_locale_data: Assertion (...) failed"; FIXME
if [ -z "$APPLICATION" ] ; then
  LANG=C LD_PRELOAD="$HERE/lib/libhookexecv.so" "$WINELDLIBRARY" "$HERE/bin/wine" "$@" | cat
else
  LANG=C LD_PRELOAD="$HERE/lib/libhookexecv.so" "$WINELDLIBRARY" "$HERE/bin/wine" "$APPLICATION" | cat
fi
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

export WINEDLLOVERRIDES="mscoree,mshtml="
mkdir -p ./Wine.AppDir/wineprefixnew
export WINEPREFIX=$(readlink -f ./Wine.AppDir/wineprefixnew)
./Wine.AppDir/AppRun wineboot
./Wine.AppDir/AppRun wineboot
sleep 5
# Need to ensure that we have system.reg userdef.reg user.reg, otherwise explorer.exe will not launch
ls -lh "$WINEPREFIX"

# echo "disable" > "$WINEPREFIX/.update-timestamp" # Stop Wine from updating $WINEPREFIX automatically from time to time # This leads to non-working WINEPREFIX!
( cd "$WINEPREFIX/drive_c/" ; rm -rf users ; ln -s /home users ) || true # Do not hardcode username in wineprefix
ls -lh "$WINEPREFIX/"
mv ./Wine.AppDir/wineprefixnew ./Wine.AppDir/wineprefix && export WINEPREFIX=$(readlink -f ./Wine.AppDir/wineprefix)

wget -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x ./appimagetool-x86_64.AppImage
ARCH=x86_64 ./appimagetool-x86_64.AppImage -g ./Wine.AppDir

#
# Wine AppImage DONE. Now making a wineprefix for Notepad++
#

wget -c "https://notepad-plus-plus.org/repository/7.x/7.6.1/npp.7.6.1.bin.minimalist.7z"
7z x -o"$WINEPREFIX/drive_c/windows/system32/" npp*.7z # system32 is on Windows $PATH equivalent

# Perhaps we can make this generic so as to convert all from portableapps.com in the same way
# wget -c "http://download3.portableapps.com/portableapps/Notepad++Portable/NotepadPlusPlusPortable_7.6.paf.exe"
# 7z x -y -otmp NotepadPlusPlusPortable_7.6.paf.exe 
# mv tmp/* "$WINEPREFIX/drive_c/windows/system32/"

sed -i -e 's|^Name=.*|Name=NotepadPlusPlus|g' ./Wine.AppDir/*.desktop
sed -i -e 's|winecfg|notepad++.exe|g' ./Wine.AppDir/AppRun
ls -lh "$WINEPREFIX"

ARCH=x86_64 ./appimagetool-x86_64.AppImage -g ./Wine.AppDir

( cd ./Wine.AppDir ; tar cfvz ../wineprefix.tar.gz wineprefix/ )
