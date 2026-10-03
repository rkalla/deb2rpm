#!/bin/sh
# RPM %postun passes the number of packages of this name left installed.
# 0 means uninstall. 1 or more means this is the old package during an upgrade.
# Debian postrm uses remove/purge for the same case.
if [ "$1" != "0" ] && [ "$1" != "remove" ] && [ "$1" != "purge" ]; then
    exit 0
fi

if command -v update-alternatives >/dev/null 2>&1; then
    update-alternatives --remove 'grok-bot' '/opt/Grok Bot/grok-bot' || true
fi

if [ -L '/usr/bin/grok-bot' ]; then
    target=$(readlink '/usr/bin/grok-bot' || true)
    if [ "$target" = '/opt/Grok Bot/grok-bot' ] || [ "$target" = '/etc/alternatives/grok-bot' ]; then
        rm -f '/usr/bin/grok-bot'
    fi
fi

APPARMOR_PROFILE_DEST='/etc/apparmor.d/grok-bot'
if [ -f "$APPARMOR_PROFILE_DEST" ]; then
    if command -v apparmor_status >/dev/null 2>&1 && apparmor_status --enabled >/dev/null 2>&1; then
        if command -v apparmor_parser >/dev/null 2>&1; then
            apparmor_parser --remove "$APPARMOR_PROFILE_DEST" || true
        fi
    fi
    rm -f "$APPARMOR_PROFILE_DEST"
fi

exit 0
