#!/usr/bin/env bash
set -euo pipefail

package='com.google.android.apps.work.oobconfig'
component="$package/.zerotouch.FactoryResetActivity"

adb get-state >/dev/null

if ! adb shell pm path "$package" | grep -q '^package:'; then
    echo 'OobConfig is absent; no changes were made.'
    exit 0
fi

echo 'OobConfig was restored. Applying user-0 restrictions.'

adb shell pm disable-user --user 0 "$component" || true

for operation in \
    WAKE_LOCK \
    RUN_IN_BACKGROUND \
    RUN_ANY_IN_BACKGROUND \
    START_FOREGROUND \
    ACCESS_RESTRICTED_SETTINGS; do
    if adb shell cmd appops set "$package" "$operation" deny; then
        echo "$operation=deny"
    else
        echo "$operation=unsupported"
    fi
done

adb shell pm disable-user --user 0 "$package"
echo 'OobConfig is disabled for user 0.'

