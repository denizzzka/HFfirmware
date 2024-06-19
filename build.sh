#!/usr/bin/env bash

set -euox pipefail

# Do not forgot to init ESP IDF environment:
# . ~/.../Espressif_IDE/esp-idf-v5.2.1/export.fish

# First stage: preprocess *.h to *.i files
#~ PRESERVE_I_FILES=y idf.py --build-dir=preprocessed set-target esp32c3 build

echo "Processing *.i files..."

# restrict in freertos isn't compatible with __restrict in esp_ringbuf, ESP IDF issue?

fdfind --base-directory ./preprocessed/esp-idf --type f --extension "c.i" \
    --case-sensitive \
    --ignore-file ../../fd_ignore.txt \
    --exec cp {} {.} \; \
    --exec sed -i -r 's/__atomic_/__atomic_DISABLED_/g' {.} \; \
    --exec sed -i -r 's/__sync_/REDECLARED__sync_/g' {.} \; \
    --exec echo ./preprocessed/esp-idf/{.} \; > preprocessed_files_list.txt

echo "Merging *.i files"

#~ ./ast_merge/ast_merge < preprocessed_files_list.txt > ./preprocessed/processed_for_dpp.c
#~ ./ast_merge/ast_merge < preprocessed_files_list.txt
head -n 15 preprocessed_files_list.txt | ./ast_merge/ast_merge

echo "Convert merged C code to .h"

echo "./preprocessed/processed_for_dpp.c" | ~/Dev/diprocessor/peg/diprocessor_peg > ./preprocessed/processed_for_dpp.h

# Create D bindings from generated .c files
# FIXME: Used DPP branch: https://github.com/denizzzka/dpp/tree/c_and_i_files
#~ ~/Dev/dpp/bin/d++ --preprocess-only --no-sys-headers --include-path=./preprocessed/ --source-output-path=./preprocessed/ esp_idf.dpp

echo "...Processing *.i files done"

# Second stage: build and link with D files
#~ idf.py --build-dir=builddir set-target esp32c3 build
