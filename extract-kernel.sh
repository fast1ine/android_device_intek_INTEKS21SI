#!/bin/bash
#
# extract-kernel.sh
# Dump recovery partition from connected device and extract kernel into prebuilt/kernel.
# DOES NOT TOUCH dtbo (staging keeps prebuilt/dtbo.img).
#

set -euo pipefail

DEVICE=aistb2
VENDOR=intek

MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi
MY_DIR="$(cd "${MY_DIR}" && pwd)"

# Configurable (override via env if needed)
RECOVERY_PARTITION="${RECOVERY_PARTITION:-/dev/block/by-name/recovery}"
DEVICE_TMP="${DEVICE_TMP:-/data/local/tmp}"

# Pre-flight: required tools
for tool in adb python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[FATAL] Missing required tool: $tool"
        echo "  Install: sudo apt install $tool"
        exit 1
    fi
done

# Pre-flight: device connected + root
echo "[*] Waiting for device..."
adb wait-for-device
UID_VAL=$(adb shell id -u | tr -d '\r\n')
if [[ "${UID_VAL}" != "0" ]]; then
    echo "[FATAL] adb shell is not root (uid=${UID_VAL})."
    echo "  This script requires a userdebug build (adb shell shows '#') or 'adb root'."
    exit 1
fi

# 1) Dump recovery partition
echo "[1/2] Dumping recovery partition (${RECOVERY_PARTITION})..."
adb shell "dd if=${RECOVERY_PARTITION} of=${DEVICE_TMP}/recovery.img bs=4M" >/dev/null
adb pull "${DEVICE_TMP}/recovery.img" "${MY_DIR}/recovery.img" >/dev/null
adb shell "rm -f ${DEVICE_TMP}/recovery.img"

# 2) Parse boot header v1 + slice kernel
echo "[2/2] Extracting kernel from recovery.img..."
python3 - <<PYEOF
import struct, os, sys
img_path  = "${MY_DIR}/recovery.img"
out_dir   = "${MY_DIR}/prebuilt"
out_path  = os.path.join(out_dir, "kernel")

with open(img_path, "rb") as f:
    hdr = f.read(48)

if hdr[0:8] != b"ANDROID!":
    sys.exit(f"[FATAL] Not an Android boot image (magic={hdr[0:8]!r})")

(kernel_size, _kaddr,
 ramdisk_size, _raddr,
 second_size, _saddr,
 _tags, page_size,
 header_version, _osver) = struct.unpack("<10I", hdr[8:48])

if header_version != 1:
    sys.exit(f"[FATAL] Expected boot header v1, got v{header_version}")

kernel_offset = page_size  # always 1 page after the header

os.makedirs(out_dir, exist_ok=True)
with open(img_path, "rb") as f:
    f.seek(kernel_offset)
    kernel = f.read(kernel_size)

with open(out_path, "wb") as f:
    f.write(kernel)

print(f"  kernel: {kernel_size} bytes -> prebuilt/kernel")
PYEOF

# Cleanup intermediate
rm -f "${MY_DIR}/recovery.img"

echo
echo "[OK] prebuilt/kernel populated. prebuilt/dtbo.img preserved (not touched)."
