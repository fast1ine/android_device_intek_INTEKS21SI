#!/sbin/sh
# aistb2-usb-symlinks.sh
#
# Stabilises USB block-device names against hot-unplug/replug. The kernel
# allocates sda, sdb, sdc, ... in connection order and never reuses an old
# letter on the same boot, so a fstab line that hard-codes /dev/block/sda1
# breaks as soon as the user re-inserts the disk.
#
# This loop walks /sys/block/sd*, finds the USB host controller in each
# device's parent path, and (re-)points stable names at the current sdX:
#   /dev/block/aistb2-usb1   -> /dev/block/sdX     (xhci  : main USB host)
#   /dev/block/aistb2-usb1p1 -> /dev/block/sdX1
#   /dev/block/aistb2-usb2   -> /dev/block/sdY     (other host)
#   /dev/block/aistb2-usb2p1 -> /dev/block/sdY1
#
# If two disks share a host, the lexicographically first sysfs path wins
# the lower number, the second falls through to usb2.

DEV=/dev/block

resolve_known_host() {
    # Echoes "1" for xHCI, "2" for the other known host, or empty for unknown.
    case "$1" in
        *f7a20000.xhci*|*xhci*) echo 1 ;;
        *f7ed0000.usb*|*ci_hdrc.0*) echo 2 ;;
        *) echo "" ;;
    esac
}

scan_once() {
    have_usb1=""
    have_usb2=""
    unknown_usb=""
    found_sd=0

    for blk in /sys/block/sd*; do
        [ -d "$blk" ] || continue
        found_sd=1
        sdname=${blk##*/}
        # readlink -f is available in TWRP toybox.
        syspath=$(readlink -f "$blk/device" 2>/dev/null)
        host=$(resolve_known_host "$syspath")

        case "$host" in
            1)
                if [ -z "$have_usb1" ]; then
                    have_usb1=$sdname
                elif [ -z "$have_usb2" ]; then
                    have_usb2=$sdname
                fi
                ;;
            2)
                if [ -z "$have_usb2" ]; then
                    have_usb2=$sdname
                elif [ -z "$have_usb1" ]; then
                    have_usb1=$sdname
                fi
                ;;
            *)
                unknown_usb="$unknown_usb $sdname"
                ;;
        esac
    done

    for sdname in $unknown_usb; do
        if [ -z "$have_usb1" ]; then
            have_usb1=$sdname
        elif [ -z "$have_usb2" ]; then
            have_usb2=$sdname
        fi
    done

    update_link() {
        # $1 = stable name suffix (usb1/usb2), $2 = sdX or empty
        target=$2
        link_disk="$DEV/aistb2-$1"
        link_part="$DEV/aistb2-${1}p1"
        if [ -z "$target" ] || [ ! -e "$DEV/$target" ]; then
            rm -f "$link_disk" "$link_part" 2>/dev/null
            return
        fi
        if [ "$(readlink "$link_disk" 2>/dev/null)" != "/dev/block/$target" ]; then
            rm -f "$link_disk" 2>/dev/null
            ln -s "/dev/block/$target" "$link_disk" 2>/dev/null
        fi
        if [ ! -e "$DEV/${target}1" ]; then
            rm -f "$link_part" 2>/dev/null
        elif [ "$(readlink "$link_part" 2>/dev/null)" != "/dev/block/${target}1" ]; then
            rm -f "$link_part" 2>/dev/null
            ln -s "/dev/block/${target}1" "$link_part" 2>/dev/null
        fi
    }

    update_link usb1 "$have_usb1"
    update_link usb2 "$have_usb2"
}

if [ "$1" = "--once" ]; then
    scan_once
    if [ "$found_sd" = "1" ]; then
        sleep 0.1 2>/dev/null
        scan_once
    fi
    exit 0
fi

while true; do
    scan_once
    sleep 1
done
