#!/usr/bin/env bash
# Focused native path regression; requires only OpenFOAM and dummy Pstream.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export WM_MPLIB=Dummy FOAM_MPI=dummy
source "$script_dir/env.sh"
export LIB_DIR="$WM_PROJECT_DIR/src" LIB_HEADER_DIRS="$WM_PROJECT_DIR/src"

wmake "$WM_PROJECT_DIR/applications/test/fileNameSpaces"
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$script_dir/run_fileNameSpaces.ps1")" \
    -ExecutablePath "$(cygpath -w "$FOAM_USER_APPBIN/Test-fileNameSpaces.exe")" \
    -OpenFOAMRoot "$(cygpath -w "$WM_PROJECT_DIR")" \
    -LibraryDirectory "$(cygpath -w "$FOAM_LIBBIN")" \
    -RuntimeDirectory "$(cygpath -w /ucrt64/bin)"
