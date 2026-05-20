#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common Omni stuff.
$(call inherit-product, vendor/omni/config/common.mk)

# Inherit from aistb2 device
$(call inherit-product, device/intek/aistb2/device.mk)

PRODUCT_DEVICE := aistb2
PRODUCT_NAME := omni_aistb2
PRODUCT_BRAND := skb
PRODUCT_MODEL := BID-AI100
PRODUCT_MANUFACTURER := INTEK

PRODUCT_GMS_CLIENTID_BASE := android-intek

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="aistb2-userdebug 9 PQ2A.190305.002 eng.loving.20191122.143933 release-keys"

BUILD_FINGERPRINT := skb/aistb2/aistb2:9/PQ2A.190305.002/lovinghc11221439:userdebug/release-keys
