#!/bin/bash

# sudo add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt install p7zip-full icoutils # For Notepad++

# Get Wine
wget -c https://www.playonlinux.com/wine/binaries/phoenicis/upstream-linux-x86/PlayOnLinux-wine-4.10-upstream-linux-x86.tar.gz

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
tar zxvf PlayOnLinux-wine-*-linux-x86.tar.gz -C ./Wine.AppDir
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
find . -path '*libp11*' -delete || true

# Only use Windows fonts. Do not attempt to use fonts from the host
# This should greatly speed up first-time launch times
# and get rid of fontconfig messages
sed -i -e 's|fontconfig|xxxxconfig|g'  lib/wine/gdi32.dll.so
find . -path '*fontconfig*' -delete

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
export LC_ALL=C LANGUAGE=C LANG=C

# Load Explorer if no arguments given
APPLICATION=""
if [ -z "$*" ] ; then
  APPLICATION="winecfg"
fi

# Since the AppImage gets mounted at different locations, relying on "$HERE"
# does not good to determine a unique string per application when inside an AppImage
if [ -z "$APPIMAGE" ]  ; then
  AppName=wine_$(echo "$HERE" | sha1sum | cut -d " " -f 1)
else
  AppName=wine_$(echo "$APPIMAGE" | sha1sum | cut -d " " -f 1)
fi

MNT_WINEPREFIX="/tmp/$AppName.unionfs" # TODO: Use the name of the app

# Load bundled WINEPREFIX if existing and if $WINEPREFIX is not set
if [ -d "$HERE/wineprefix" ] && [ -z "$WINEPREFIX" ] ; then
  RO_WINEPREFIX="$HERE/wineprefix" # WINEPREFIX in the AppDir
  RW_WINEPREFIX_OVERLAY="/tmp/$AppName.rw" # TODO: Use the name of the app

  mkdir -p "$MNT_WINEPREFIX" "$RW_WINEPREFIX_OVERLAY"
  if [ ! -e "$MNT_WINEPREFIX/drive_c" ] ; then
    echo "Mounting $MNT_WINEPREFIX"
    "$HERE/usr/bin/unionfs-fuse" -o use_ino,uid=$UID -ocow "$RW_WINEPREFIX_OVERLAY"=RW:"$RO_WINEPREFIX"=RO "$MNT_WINEPREFIX" || exit 1
    trap atexit EXIT
  fi

  export WINEPREFIX="$MNT_WINEPREFIX"
  echo "Using $HERE/wineprefix mounted to $WINEPREFIX"
fi

atexit()
{
  while pgrep -f "$HERE/bin/wineserver" ; do sleep 1 ; done
  pkill -f "$HERE/usr/bin/unionfs-fuse"
  sleep 1
  rm -r "$MNT_WINEPREFIX" # "$RW_WINEPREFIX_OVERLAY"
}


# Allow the AppImage to be symlinked to e.g., /usr/bin/wineserver
if [ ! -z $APPIMAGE ] ; then
  BINARY_NAME=$(basename "$ARGV0")
else
  BINARY_NAME=$(basename "$0")
fi
if [ ! -z "$1" ] && [ -e "$HERE/bin/$1" ] ; then
  MAIN="$HERE/bin/$1" ; shift
elif [ ! -z "$1" ] && [ -e "$HERE/usr/bin/$1" ] ; then
  MAIN="$HERE/usr/bin/$1" ; shift
elif [ -e "$HERE/bin/$BINARY_NAME" ] ; then
  MAIN="$HERE/bin/$BINARY_NAME"
elif [ -e "$HERE/usr/bin/$BINARY_NAME" ] ; then
  MAIN="$HERE/usr/bin/$BINARY_NAME"
else
  MAIN="$HERE/bin/wine"
fi

if [ -z "$APPLICATION" ] ; then
  LD_PRELOAD="$HERE/lib/libhookexecv.so" "$WINELDLIBRARY" "$MAIN" "$@" | cat
else
  LD_PRELOAD="$HERE/lib/libhookexecv.so" "$WINELDLIBRARY" "$MAIN" "$APPLICATION" | cat
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

grep "Categories=" usr/share/applications/wine.desktop || echo 'Categories=System;Emulator;' >> usr/share/applications/wine.desktop
cp usr/share/applications/wine.desktop .

touch wine.svg # FIXME

export VERSION=$(strings ./lib/libwine.so.1 | grep wine-[\.0-9] | cut -d "-" -f 2)

cd ..

export WINEDLLOVERRIDES="mscoree,mshtml="
mkdir -p ./Wine.AppDir/wineprefixnew
export WINEPREFIX=$(readlink -f ./Wine.AppDir/wineprefixnew)
./Wine.AppDir/AppRun wineboot.exe
./Wine.AppDir/AppRun wineboot.exe
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

export VERSION=$(wget -q "https://notepad-plus-plus.org/repository/7.x/?C=M;O=D" -O - | grep href | grep '/"' | grep -v "unstable" | grep -v "repository" | cut -d ">" -f 6 | cut -d '"' -f 2| sed  -e 's|/||g' | sort -r -V | uniq | head -n 1)
SHORTVERSION=$(echo $VERSION | cut -d "." -f 1).x
wget -c "https://notepad-plus-plus.org/repository/$SHORTVERSION/$VERSION/npp.$VERSION.bin.minimalist.7z"
7z x -o"$WINEPREFIX/drive_c/windows/system32/" npp*.7z # system32 is on Windows $PATH equivalent

# Perhaps we can make this generic so as to convert all from portableapps.com in the same way
# wget -c "http://download3.portableapps.com/portableapps/Notepad++Portable/NotepadPlusPlusPortable_7.6.paf.exe"
# 7z x -y -otmp NotepadPlusPlusPortable_7.6.paf.exe 
# mv tmp/* "$WINEPREFIX/drive_c/windows/system32/"

# Icon
rm ./Wine.AppDir/*.{svg,svgz,png,xpm} ./Wine.AppDir/.DirIcon || true
wrestool -x -t 14 ./Wine.AppDir/wineprefix/drive_c/windows/system32/notepad++.exe > icon.ico
convert icon.ico icon.png
mkdir -p ./Wine.AppDir/usr/share/icons/hicolor/{256x256,48x48,16x16}/apps/
cp icon-3.png ./Wine.AppDir/usr/share/icons/hicolor/256x256/apps/notepadpp.png
cp icon-6.png ./Wine.AppDir/usr/share/icons/hicolor/48x48/apps/notepadpp.png
cp icon-8.png ./Wine.AppDir/usr/share/icons/hicolor/16x16/apps/notepadpp.png
cp icon-3.png ./Wine.AppDir/notepadpp.png
sed -i -e 's|^Icon=.*|Icon=notepadpp|g' ./Wine.AppDir/*.desktop

sed -i -e 's|^Name=.*|Name=NotepadPlusPlus|g' ./Wine.AppDir/*.desktop
sed -i -e 's|^Name\[.*||g' ./Wine.AppDir/*.desktop
sed -i -e 's|winecfg|notepad++.exe|g' ./Wine.AppDir/AppRun
ls -lh "$WINEPREFIX"

# Delete unneeded files
SQ=$(readlink -f .)/Wine.AppDir/
find Wine.AppDir/ -type f -or -type l > tmp.avail
while read p; do
  readlink -f "$p" >> tmp.normalized.have
done <tmp.avail
sed -i -e 's|'$SQ'||g' tmp.normalized.have
while read p; do
  if [[ $p =~ .*AppRun ]] || [[ $p =~ .*fuse.* ]] || [[ $p =~ .*copyright ]] || [[ $p =~ .*.desktop ]] || [[ $p =~ .*png ]] || [[ $p =~ .*svg ]] || [ ! -z "$(grep "$p" NotepadPlusPlus.manifest)" ] ; then 
    echo "KEEP $p"
  else
    echo rm "Wine.AppDir/$p"
    rm "Wine.AppDir/$p" || true
  fi
done <tmp.normalized.have
find Wine.AppDir/ -type d -empty -delete # Remove empty directories

ARCH=x86_64 ./appimagetool-x86_64.AppImage -g ./Wine.AppDir

( cd ./Wine.AppDir ; tar cfvz ../wineprefix.tar.gz wineprefix/ )
