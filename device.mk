#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/intek/aistb2

# Recovery: keymaster blobs from vendor partition to recovery ramdisk.
# Source comes from extract-files.sh (adb) or dump-extract.sh (firmware dump),
# populated into vendor/intek/aistb2/proprietary/ at build time.
PRODUCT_COPY_FILES += \
    vendor/intek/aistb2/proprietary/vendor/bin/hw/android.hardware.keymaster@4.0-service.syna:$(TARGET_RECOVERY_ROOT_OUT)/sbin/keymaster/vendor/bin/hw/android.hardware.keymaster@4.0-service.syna \
    vendor/intek/aistb2/proprietary/vendor/bin/hw/android.hardware.keymaster@4.0-service.syna:$(TARGET_RECOVERY_ROOT_OUT)/vendor/bin/hw/android.hardware.keymaster@4.0-service.syna \
    vendor/intek/aistb2/proprietary/vendor/lib/keymaster4hal.so:$(TARGET_RECOVERY_ROOT_OUT)/sbin/keymaster/vendor/lib/keymaster4hal.so \
    vendor/intek/aistb2/proprietary/vendor/lib/keymaster4hal.so:$(TARGET_RECOVERY_ROOT_OUT)/vendor/lib/keymaster4hal.so \
    vendor/intek/aistb2/proprietary/vendor/lib/libdrmcommm.so:$(TARGET_RECOVERY_ROOT_OUT)/sbin/keymaster/vendor/lib/libdrmcommm.so \
    vendor/intek/aistb2/proprietary/vendor/lib/libkeymaster.so:$(TARGET_RECOVERY_ROOT_OUT)/sbin/keymaster/vendor/lib/libkeymaster.so
