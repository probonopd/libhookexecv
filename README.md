# libhookexecv
Hook Wine execv syscall to use special ld.so in order to make it fully relocateable

## Problem statement

We want to make a fully portable of 32-bit Wine that can run on any Linux system, without the need for 32-bit compatibility libraries to be installed in the system (which is a hassle).

32-bit Wine is needed to run 32-bit Windows applications (as were the norm until very recently).

```
5$ find . -type f -exec file {} 2>&1 \; | grep "ld-"
./bin/wine: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 2.6.26, BuildID[sha1]=8b26c8c6685ea1ed987a21ef30b48823e844e858, stripped
./bin/winedump: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 2.6.26, BuildID[sha1]=6fc5973f83404c829810008d000671373860cb6f, stripped
./bin/wmc: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 2.6.26, BuildID[sha1]=30688d1dcd7ce51705571a891c8d6cf028dd6d0a, stripped
./bin/wrc: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 2.6.26, BuildID[sha1]=5c24139c3c19ddc6c26778afe204d60ab78c3911, stripped
./bin/winegcc: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 2.6.26, BuildID[sha1]=fa60ca2fb4322cc8c4d3c45e7bbfb11f1fab17eb, stripped
./bin/winebuild: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 2.6.26, BuildID[sha1]=29fb932cea712078706b973f5c14c11c41a2cc2c, stripped
./bin/wineserver: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 2.6.26, BuildID[sha1]=b72ce157533fbe10b42ec00e7518ff17011df558, stripped
./bin/widl: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 2.6.26, BuildID[sha1]=14b9c572d68809513bd0c43fb61073be71ca7fd1, stripped
```

It would be best if we could rewrite the ELF executables to not search for `/lib/ld-linux.so.2` on the system (which is not there on most 64-bit systems), but in a custom location, e.g., in `$ORIGIN/../lib` which should resolve, in our example, to `./lib/ld-linux.so.2`. Unfortunately this does not work. [__Why?__](https://stackoverflow.com/a/48456169)

## Complication

It is possible to use a custom loader by invoking ELF binaries like this:

```
./lib/ld-linux.so.2 --library-path $(readlink -f ./lib/):$LD_LIBRARY_PATH ./bin/wine
```

However, there are two issues with this:

- Wine launches subprocesses, which in turn would try to use `./lib/ld-linux.so.2` again
- `./lib/ld-linux.so.2` may still try to load libraries and [other stuff](https://packages.debian.org/jessie/i386/libc6/filelist) from the system `/lib`, which we must avoid. Ideally we could patch `./lib/ld-linux.so.2` to load its stuff from `$ORIGIN/i386-linux-gnu/`. Unfortunately there seems to be no way to achieve this apart from binary-patching `ld-linux.so.2`- __why?__

## Solution

```
# For testing, disable system /lib/ld-linux.so.2
sudo mv /lib/ld-linux.so.2 /lib/ld-linux.so.2.disabled || true

# Get Wine
wget https://www.playonlinux.com/wine/binaries/linux-x86/PlayOnLinux-wine-3.5-linux-x86.pol
tar xfvj PlayOnLinux-wine-*-linux-x86.pol wineversion/
cd wineversion/*/

# Get suitable old ld-linux.so and the stuff that comes with it
wget http://ftp.us.debian.org/debian/pool/main/g/glibc/libc6_2.19-18+deb8u10_i386.deb
dpkg -x libc6_2.19-18+deb8u10_i386.deb  .

# Make absolutely sure it will not load stuff from /lib or /usr
sed -i -e 's|/usr|/xxx|g' lib/ld-linux.so.2
sed -i -e 's|/lib|/XXX|g' lib/ld-linux.so.2

# Remove duplicate (why is it there?)
rm -f lib/i386-linux-gnu/ld-*.so

# Get libhookexecv.so
wget -c https://github.com/probonopd/libhookexecv/releases/download/continuous/libhookexecv.so -O lib/libhookexecv.so 
```

Then run like this:

```
cat > AppRun <<\EOF
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LDLINUX="$HERE/lib/ld-linux.so.2" # Patched to not load stuff from /lib
export WINELDLIBRARY="$LDLINUX" # libhookexecv uses the WINELDLIBRARY variable to patch wineloader on the fly
export LD_PRELOAD=$(readlink -f "$HERE/lib/libhookexecv.so")
export LD_LIBRARY_PATH=$(readlink -f "$HERE/lib/"):$(readlink -f "$HERE/lib/i386-linux-gnu"):$LD_LIBRARY_PATH
"$LDLINUX" --inhibit-cache "$HERE/bin/wine" "$@"
EOF
chmod +x AppRun

./AppRun explorer.exe
```

However I get this error:

```
./AppRun explorer.exe

ERROR: ld.so: object '/home/me/Downloads/wineversion/3.5/lib/libhookexecv.so' from LD_PRELOAD cannot be preloaded (wrong ELF class: ELFCLASS32): ignored.
ERROR: ld.so: object '/home/me/Downloads/wineversion/3.5/lib/libhookexecv.so' from LD_PRELOAD cannot be preloaded (wrong ELF class: ELFCLASS32): ignored.
/lib/ld-linux.so.2: could not open
```
