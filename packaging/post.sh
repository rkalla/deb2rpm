#!/bin/sh
# Fedora post-install for the converted grok-bot package.
# Also used as %posttrans so an upgrade from 0.30.0 still leaves /usr/bin/grok-bot
# in place: that package's %postun removes the alternatives entry on upgrade.
# The Debian postinst also registers an apt source; that is skipped here
# because Fedora does not use apt.

if command -v update-alternatives >/dev/null 2>&1; then
    if [ -L '/usr/bin/grok-bot' ] && [ -e '/usr/bin/grok-bot' ] && [ "$(readlink '/usr/bin/grok-bot')" != '/etc/alternatives/grok-bot' ]; then
        rm -f '/usr/bin/grok-bot'
    fi
    update-alternatives --install '/usr/bin/grok-bot' 'grok-bot' '/opt/Grok Bot/grok-bot' 100 \
        || ln -sfn '/opt/Grok Bot/grok-bot' '/usr/bin/grok-bot'
else
    ln -sfn '/opt/Grok Bot/grok-bot' '/usr/bin/grok-bot'
fi

# Electron's SUID sandbox helper is only needed when user namespaces are unavailable.
if [ -L /proc/self/ns/user ] && unshare --user true >/dev/null 2>&1; then
    chmod 0755 '/opt/Grok Bot/chrome-sandbox' || true
else
    chmod 4755 '/opt/Grok Bot/chrome-sandbox' || true
fi

if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF '/opt/Grok Bot' /usr/share/applications/grok-bot.desktop >/dev/null 2>&1 || true
    if [ -e /usr/bin/grok-bot ]; then
        restorecon -F /usr/bin/grok-bot >/dev/null 2>&1 || true
    fi
fi

# AppArmor is optional. Fedora defaults to SELinux, so this only runs when AppArmor is enabled.
if command -v apparmor_status >/dev/null 2>&1 && apparmor_status --enabled >/dev/null 2>&1; then
    APPARMOR_PROFILE_SOURCE='/opt/Grok Bot/resources/apparmor-profile'
    APPARMOR_PROFILE_TARGET='/etc/apparmor.d/grok-bot'
    if command -v apparmor_parser >/dev/null 2>&1 && apparmor_parser --skip-kernel-load --debug "$APPARMOR_PROFILE_SOURCE" >/dev/null 2>&1; then
        cp -f "$APPARMOR_PROFILE_SOURCE" "$APPARMOR_PROFILE_TARGET"
        apparmor_parser --replace --write-cache --skip-read-cache "$APPARMOR_PROFILE_TARGET" || true
    else
        echo "Skipping the installation of the AppArmor profile as this version of AppArmor does not seem to support the bundled profile" >&2
    fi

    if [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = 1 ] &&
        ! grep -q '^grok-bot ' /sys/kernel/security/apparmor/profiles 2>/dev/null; then
        if [ -f "$APPARMOR_PROFILE_TARGET" ]; then
            echo "warning: the AppArmor profile grok-bot is not loaded and this kernel restricts unprivileged user namespaces; Grok Bot exits at launch until the profile is loaded (sudo apparmor_parser -r '$APPARMOR_PROFILE_TARGET')" >&2
        else
            echo "warning: this version of apparmor_parser rejected the bundled AppArmor profile and this kernel restricts unprivileged user namespaces; Grok Bot cannot start its sandbox on this kernel until the apparmor package is updated and Grok Bot is reinstalled" >&2
        fi
    fi
fi

exit 0
