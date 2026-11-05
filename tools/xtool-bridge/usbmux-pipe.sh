#!/bin/sh
# Started by socat for each connection: runs the Windows-side pipe.
exec python.exe "$(wslpath -w "$(dirname "$0")/usbmux_pipe.py")"
