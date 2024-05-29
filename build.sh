#!/usr/bin/env bash

set -euox pipefail

# Do not forgot to init ESP IDF environment:
# . ~/.../Espressif_IDE/esp-idf-v5.2.1/export.fish

# First stage: preprocess *.h to *.i files
PRESERVE_I_FILES=y idf.py --build-dir=preprocessed set-target esp32c3 build

# Mass rename *.c.i files to *.i to satisfy D compiler
mmv -r './preprocessed/;*.c.i' '#2.i'

# Second stage: build and link with D files
idf.py --build-dir=builddir set-target esp32c3 build
