#!/usr/bin/env bash
set -euo pipefail

package='com.google.android.apps.work.oobconfig'
component="$package/.zerotouch.FactoryResetActivity"

adb get-state >/dev/null

printf 'model=%s\n' "$(adb shell getprop ro.product.model | tr -d '\r')"
printf 'slot=%s\n' "$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
printf 'boot_completed=%s\n' "$(adb shell getprop sys.boot_completed | tr -d '\r')"
printf 'verified_boot_state=%s\n' "$(adb shell getprop ro.boot.verifiedbootstate | tr -d '\r')"

if adb shell pm path "$package" | grep -q '^package:'; then
    echo 'oobconfig=presente'
    adb shell pm path "$package"
    exit 2
fi

echo 'oobconfig=ausente'
if adb shell cmd package resolve-activity --brief -n "$component" 2>&1 \
    | grep -qv 'No activity found'; then
    echo 'factory_reset_activity=ativa_inesperadamente'
    exit 3
fi
echo 'factory_reset_activity=ausente'

for google_package in \
    com.android.vending \
    com.google.android.gms \
    com.google.android.gsf \
    com.google.android.setupwizard; do
    if adb shell pm path "$google_package" | grep -q '^package:'; then
        echo "$google_package=presente"
    else
        echo "$google_package=ausente"
    fi
done
