#!/usr/bin/env bash

set -euox pipefail

# Do not forgot to init ESP IDF environment:
# . ~/.../Espressif_IDE/esp-idf-v5.2.1/export.fish

# First stage: preprocess *.h to *.i files
PRESERVE_I_FILES=y idf.py --build-dir=preprocessed set-target esp32c3 build

D_BINDING_MODULE="./preprocessed/esp_idf.d"
export D_BINDING=$(realpath $D_BINDING_MODULE)

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

time dub run --root=ast_merge/ --build=release -- --clang_opts="--target=riscv32" --batch_size=10 --threads=8 --include=importc.h --show_excluded=brief --debug_output --output ${D_BINDING_MODULE} < preprocessed_files_list.txt 2> err.log

# Probably, this is same case as in https://github.com/atilaneves/dpp/issues/350
sed -i 's/align(1)://g' ${D_BINDING_MODULE}

echo "...Processing *.i files done"

# Second stage: build and link with D files
idf.py --build-dir=builddir set-target esp32c3 build
