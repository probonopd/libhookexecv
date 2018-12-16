#!/bin/bash

# Be verbose
set -x

sudo dpkg --add-architecture i386
sudo apt-get update

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
install --print-uris wine:i386 2>&1 | grep "_i386" | grep -v "wine" | cut -d "'" -f 2 )

wget -c $URLS

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

# Load Explorer if no arguments given
EXPLORER=""
if [ -z "$@" ] ; then 
  EXPLORER="explorer.exe"
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
( cd usr/ ; ln -s ../share . )

cp usr/share/applications/wine.desktop .

touch wine.svg # FIXME

cd ..

wget -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x ./appimagetool-x86_64.AppImage
ARCH=x86_64 ./appimagetool-x86_64.AppImage -g ./Wine.AppDir
