#!/bin/sh
# Lets WSL reach the iPhone through the Windows "Apple Devices" app.
# Run as root and keep it running:
#   wsl -d Ubuntu-24.04 -u root -- sh /mnt/c/Users/PC/Desktop/mantiza/Mantiza/tools/xtool-bridge/iphone-bridge.sh
# Needs: socat in WSL, python.exe on Windows, Apple Devices installed.
DIR="$(cd "$(dirname "$0")" && pwd)"
rm -f /var/run/usbmuxd
echo "iPhone bridge running on /var/run/usbmuxd (Ctrl+C to stop)"
exec socat UNIX-LISTEN:/var/run/usbmuxd,fork,mode=666 "EXEC:sh $DIR/usbmux-pipe.sh"
