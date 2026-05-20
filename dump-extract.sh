#!/bin/bash
#
# dump-extract.sh
# Extract kernel + vendor proprietary blobs from firmware dump files placed in firmware/.
# DOES NOT TOUCH dtbo (staging keeps prebuilt/dtbo.img).
#
# Supported input combinations under firmware/:
#   (a) recovery.img + vendor.img                                  (sparse or raw ext4)
#   (b) recovery.img + vendor.new.dat.br + vendor.transfer.list    (OTA-style)
#
# AVB footer / verity hashtree are auto-detected (info only); ro mount works either way.
#

set -euo pipefail

DEVICE=aistb2
VENDOR=intek

MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi
MY_DIR="$(cd "${MY_DIR}" && pwd)"

FIRMWARE_DIR="${MY_DIR}/firmware"
WORK_DIR="${MY_DIR}/.dump-extract.tmp"

# ANDROID_ROOT for vendor proprietary destination
# Standard LineageOS layout: device/intek/aistb2 -> ANDROID_ROOT/vendor/intek/aistb2/proprietary/
ANDROID_ROOT="${ANDROID_ROOT:-${MY_DIR}/../../..}"
ANDROID_ROOT="$(cd "${ANDROID_ROOT}" && pwd)"
VENDOR_PROP_DIR="${ANDROID_ROOT}/vendor/${VENDOR}/${DEVICE}/proprietary"

PROPRIETARY_FILES="${MY_DIR}/proprietary-files.txt"

# ─── Pre-flight: required tools ──────────────────────────────────────────────
need_tool() {
    local name="$1" install_hint="$2"
    if ! command -v "$name" >/dev/null 2>&1; then
        echo "[FATAL] Missing required tool: $name"
        echo "  Install: $install_hint"
        exit 1
    fi
}

need_tool python3 "sudo apt install python3"
need_tool xxd    "sudo apt install xxd"

# Conditional tools (only checked if their input format is present)

# ─── Detect input combination ────────────────────────────────────────────────
if [[ ! -f "${FIRMWARE_DIR}/recovery.img" ]]; then
    echo "[FATAL] Missing: firmware/recovery.img"
    echo "  Place your stock recovery.img into firmware/ before running."
    exit 1
fi

HAS_VENDOR_IMG=0
HAS_OTA_DAT=0
[[ -f "${FIRMWARE_DIR}/vendor.img" ]] && HAS_VENDOR_IMG=1
[[ -f "${FIRMWARE_DIR}/vendor.new.dat.br" && -f "${FIRMWARE_DIR}/vendor.transfer.list" ]] && HAS_OTA_DAT=1

if [[ ${HAS_VENDOR_IMG} -eq 0 && ${HAS_OTA_DAT} -eq 0 ]]; then
    echo "[FATAL] No vendor input found under firmware/."
    echo "  Provide one of:"
    echo "    (a) firmware/vendor.img"
    echo "    (b) firmware/vendor.new.dat.br + firmware/vendor.transfer.list"
    exit 1
fi

if [[ ${HAS_VENDOR_IMG} -eq 1 && ${HAS_OTA_DAT} -eq 1 ]]; then
    echo "[FATAL] Ambiguous input: both vendor.img and vendor.new.dat.br present."
    echo "  Remove one set before running."
    exit 1
fi

mkdir -p "${WORK_DIR}"
trap 'rm -rf "${WORK_DIR}"; if mountpoint -q "${WORK_DIR}/mnt" 2>/dev/null; then sudo umount "${WORK_DIR}/mnt"; fi' EXIT

# ─── Stage 1: normalize vendor input to a raw ext4 image ─────────────────────
WORKING_IMG=""

if [[ ${HAS_OTA_DAT} -eq 1 ]]; then
    need_tool brotli   "sudo apt install brotli"
    need_tool sdat2img "git clone https://github.com/xpirt/sdat2img and put sdat2img.py on PATH"

    echo "[stage1] Decompressing vendor.new.dat.br..."
    brotli -d -k -o "${WORK_DIR}/vendor.new.dat" "${FIRMWARE_DIR}/vendor.new.dat.br"

    echo "[stage1] Converting .dat + transfer.list -> raw image..."
    sdat2img "${FIRMWARE_DIR}/vendor.transfer.list" "${WORK_DIR}/vendor.new.dat" "${WORK_DIR}/vendor.img"
    WORKING_IMG="${WORK_DIR}/vendor.img"
else
    # vendor.img present: check sparse vs raw
    MAGIC=$(xxd -l 4 -p "${FIRMWARE_DIR}/vendor.img")
    if [[ "${MAGIC}" == "3aff26ed" ]]; then
        need_tool simg2img "sudo apt install android-sdk-libsparse-utils"
        echo "[stage1] Sparse image detected, converting to raw..."
        simg2img "${FIRMWARE_DIR}/vendor.img" "${WORK_DIR}/vendor_raw.img"
        WORKING_IMG="${WORK_DIR}/vendor_raw.img"
    else
        echo "[stage1] Raw image detected, using directly."
        WORKING_IMG="${FIRMWARE_DIR}/vendor.img"
    fi
fi

# ─── Stage 2: AVB footer detection (info only) ───────────────────────────────
FOOTER_MAGIC=$(tail -c 64 "${WORKING_IMG}" | xxd -l 4 -p)
if [[ "${FOOTER_MAGIC}" == "41564266" ]]; then
    echo "[stage2] AVB footer detected (AVBf). Image will be mounted ro; verity tree ignored."
else
    echo "[stage2] No AVB footer. Plain ext4."
fi

# ─── Stage 3: mount + extract proprietary blobs ──────────────────────────────
echo "[stage3] Mounting working image (sudo required for loop mount)..."
mkdir -p "${WORK_DIR}/mnt"
sudo mount -o loop,ro "${WORKING_IMG}" "${WORK_DIR}/mnt"

if [[ ! -f "${PROPRIETARY_FILES}" ]]; then
    echo "[FATAL] proprietary-files.txt not found at ${PROPRIETARY_FILES}"
    exit 1
fi

mkdir -p "${VENDOR_PROP_DIR}"
echo "[stage3] Extracting blobs to: ${VENDOR_PROP_DIR}"

COUNT=0
while IFS= read -r line; do
    # skip blank and comment lines
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" ]] && continue

    # strip leading - (optional marker) and from:to (use 'from' for source)
    case "${line}" in
        -*) line="${line#-}" ;;
    esac
    src_path="${line%%:*}"

    # Source within mounted /vendor: strip leading 'vendor/' if present
    case "${src_path}" in
        vendor/*) rel="${src_path#vendor/}" ;;
        */*)      rel="${src_path}" ;;
        *)        rel="${src_path}" ;;
    esac

    src_file="${WORK_DIR}/mnt/${rel}"
    dst_file="${VENDOR_PROP_DIR}/${src_path}"

    if [[ ! -f "${src_file}" ]]; then
        echo "  [SKIP] ${src_path} (not found in image)"
        continue
    fi
    mkdir -p "$(dirname "${dst_file}")"
    cp -p "${src_file}" "${dst_file}"
    echo "  [OK]   ${src_path}"
    COUNT=$((COUNT + 1))
done < "${PROPRIETARY_FILES}"

sudo umount "${WORK_DIR}/mnt"

echo "[stage3] ${COUNT} blob(s) extracted."

# ─── Stage 4: extract kernel from recovery.img ───────────────────────────────
echo "[stage4] Extracting kernel from firmware/recovery.img..."
python3 - <<PYEOF
import struct, os, sys
img_path = "${FIRMWARE_DIR}/recovery.img"
out_dir  = "${MY_DIR}/prebuilt"
out_path = os.path.join(out_dir, "kernel")

with open(img_path, "rb") as f:
    hdr = f.read(48)
if hdr[0:8] != b"ANDROID!":
    sys.exit(f"[FATAL] Not an Android boot image (magic={hdr[0:8]!r})")

(kernel_size, _ka, ramdisk_size, _ra, second_size, _sa,
 _tags, page_size, header_version, _osver) = struct.unpack("<10I", hdr[8:48])

if header_version != 1:
    sys.exit(f"[FATAL] Expected boot header v1, got v{header_version}")

os.makedirs(out_dir, exist_ok=True)
with open(img_path, "rb") as f:
    f.seek(page_size)
    data = f.read(kernel_size)
with open(out_path, "wb") as f:
    f.write(data)
print(f"  kernel: {kernel_size} bytes -> prebuilt/kernel")
PYEOF

echo
echo "[OK] Done."
echo "  prebuilt/kernel populated."
echo "  prebuilt/dtbo.img preserved (not touched)."
echo "  Vendor blobs at: ${VENDOR_PROP_DIR}"
