#!/bin/sh
# Build the static C shim used by Yaynu.Tui for process-wide state.
#
# Outputs c_src/libtui_shim.a so Fix's `static_links = ["tui_shim"]`
# can pick it up via `library_paths = ["c_src"]`.

set -e
cd "$(dirname "$0")/.."
SRC="c_src/tui_shim.c"
OBJ="c_src/tui_shim.o"
LIB="c_src/libtui_shim.a"

if [ -f "$LIB" ] && [ "$LIB" -nt "$SRC" ]; then
    exit 0
fi

cc -O2 -Wall -Wextra -fPIC -c "$SRC" -o "$OBJ"
ar rcs "$LIB" "$OBJ"
rm -f "$OBJ"
