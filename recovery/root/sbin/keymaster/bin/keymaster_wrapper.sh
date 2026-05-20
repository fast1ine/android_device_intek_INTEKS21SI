#!/sbin/sh
export LD_LIBRARY_PATH=/vendor/lib:/vendor/lib/hw:/system/lib:/system/lib/vndk-28:/system/lib/vndk-sp-28:/sbin:/sbin/keymaster/vendor/lib:/sbin/keymaster/system/lib
export PATH=/sbin:/system/bin:/vendor/bin:/vendor/bin/hw
exec /sbin/keymaster/vendor/bin/hw/android.hardware.keymaster@4.0-service.syna
