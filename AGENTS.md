# deb2rpm

This repository converts the Grok Bot amd64 `.deb` into an unsigned x86_64 RPM for Fedora. It is not a generic deb-to-rpm tool.

## Commands

- Syntax check: `bash -n grok-bot-deb-to-rpm.sh`
- Convert: `./grok-bot-deb-to-rpm.sh /absolute/path/grok-bot_VERSION_amd64.deb`
- The script verifies the RPM before it exits. When an older grok-bot is installed, also run `rpm -Uvh --test` on the output.
- Do not install the package. `sudo` on this host requires a password.

## Packaging rules

- Build with `fpm -s dir`. Do not use `alien` or `fpm -s deb`.
- Keep `--no-auto-depends`. Bundled `.so` and `.node` files must not become RPM requires.
- Fedora dependency names live in `grok-bot-deb-to-rpm.sh`. Debian names such as `libgtk-3-0` are not Fedora packages.
- `packaging/post.sh` is both `%post` and `%posttrans`. `%posttrans` restores `/usr/bin/grok-bot` because grok-bot 0.30.0 removes the alternatives entry from `%postun` during an upgrade.
- `packaging/postun.sh` must exit immediately unless `$1` is `0`, `remove`, or `purge`.
- Do not register the Debian apt source, keyring, or `downloads.cursor.com`.
- The RPM must conflict with, provide, and obsolete `sand`.
- The install path is `/opt/Grok Bot`, including the space. The launcher is `/usr/bin/grok-bot`.
- `chrome-sandbox` stays mode `0755` in the payload. The post script changes it to `4755` only when user namespaces are unavailable.
- If a new deb adds a dependency, a maintainer script, or a Conflicts/Provides/Replaces value other than `sand`, the converter stops on purpose. Update the mapping and describe what changed.
- Do not commit `.deb` or `.rpm` files.

## Host

Fedora workstation. The package is unsigned. Install with `sudo dnf install` of the local RPM path. `localpkg_gpgcheck` is off, so a local unsigned RPM installs without `--nogpgcheck`.
