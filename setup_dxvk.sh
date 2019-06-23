#!/bin/bash

# Stripped down installer script since the original does not seem to work
# with the AppDir version of Wine (yet?)

# figure out where we are
basedir=`dirname "$(readlink -f $0)"`
WINEPREFIX=$(readlink -f $WINEPREFIX)
win32_sys_path="$WINEPREFIX/drive_c/windows/system32"
win64_sys_path="$WINEPREFIX/drive_c/windows/system32"

# figure out which action to perform
action=install

# process arguments
shift

with_dxgi=1
file_cmd="cp"

while [ $# -gt 0 ]; do
  case "$1" in
  "--without-dxgi")
    with_dxgi=0
    ;;
  "--symlink")
    file_cmd="ln -s"
    ;;
  esac
  shift
done

# check wine prefix before invoking wine, so that we
# don't accidentally create one if the user screws up
if [ -n "$WINEPREFIX" ] && ! [ -f "$WINEPREFIX/system.reg" ]; then
  echo "$WINEPREFIX:"' Not a valid wine prefix.' >&2
  exit 1
fi


if [ -z "$win32_sys_path" ] && [ -z "$win64_sys_path" ]; then
  echo 'Failed to resolve C:\windows\system32.' >&2
  exit 1
fi

# create native dll override
overrideDll() {
  ./Wine.AppDir/AppRun reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v $1 /d native /f 2>&1
  if [ $? -ne 0 ]; then
    echo -e "Failed to add override for $1"
    exit 1
  fi
}

# remove dll override
restoreDll() {
  ./Wine.AppDir/AppRun reg delete 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v $1 /f 2>&1
  if [ $? -ne 0 ]; then
    echo "Failed to remove override for $1"
  fi
}

# copy or link dxvk dll, back up original file
installFile() {
  dstfile="${1}/${3}.dll"
  srcfile="${basedir}/${2}/${3}.dll"

  if [ -f "${srcfile}.so" ]; then
    srcfile="${srcfile}.so"
  fi

  if ! [ -f "${srcfile}" ]; then
    echo "${srcfile}: File not found. Skipping." >&2
    return 1
  fi

  if [ -n "$1" ]; then
    if [ -f "${dstfile}" ] || [ -h "${dstfile}" ]; then
      if ! [ -f "${dstfile}.old" ]; then
        mv "${dstfile}" "${dstfile}.old"
      else
        rm "${dstfile}"
      fi
      $file_cmd "${srcfile}" "${dstfile}"
    else
      echo "${dstfile}: File not found in wine prefix" >&2
      return 1
    fi
  fi
  return 0
}


install() {
  installFile "$win32_sys_path" "x32" "$1"
  inst32_ret="$?"
  installFile "$win64_sys_path" "x64" "$1"
  inst64_ret="$?"
  if [ "$inst32_ret" -eq 0 ] || [ "$inst64_ret" -eq 0 ]; then
    overrideDll "$1"
  fi
}


# skip dxgi during install if not explicitly
# enabled, but always try to uninstall it
if [ $with_dxgi -ne 0 ] ; then
  $action dxgi
fi

$action d3d10
$action d3d10_1
$action d3d10core
$action d3d11
