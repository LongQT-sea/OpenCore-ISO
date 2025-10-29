#!/usr/bin/env bash

ISO_FILE_NAME=LongQT-OpenCore-v0.5.iso
VOL_NAME=LongQT-OpenCore
SOURCE_DIR=./
BOOT_IMG=BOOT.img

cd "$(dirname "$0")"

# Cleanup
find ${SOURCE_DIR} \
    \( \
        -name ".DS_Store" \
        -o -name "._*" \
        -o -name ".Spotlight-V100" \
        -o -name ".Trashes" \
        -o -name ".fseventsd" \
        -o -name ".DocumentRevisions-V100" \
        -o -name ".TemporaryItems" \
        -o -name "__MACOSX" \
    \) \
    -exec rm -rf {} +

if ! command -v xorriso >/dev/null 2>&1; then
  echo "xorriso not found. Please install it with: brew install xorriso"
  exit 1
fi

xorriso -rockridge off -as mkisofs \
  -iso-level 3 \
  -V "${VOL_NAME}" \
  -J -joliet-long\
  -eltorito-alt-boot \
  -e "${BOOT_IMG}" \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  -m ".git*" \
  -m "README.md" \
  -m "Make_ISO*" \
  -m "LICENSE*" \
  -m "cpu-models.conf" \
  -m "Create_Recovery_ISO*" \
  -output ~/Desktop/${ISO_FILE_NAME} \
  ${SOURCE_DIR}
