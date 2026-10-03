# deb2rpm

Convert a Grok Bot amd64 `.deb` into an unsigned x86_64 RPM for Fedora.

A plain `fpm -s deb -t rpm` does not produce an installable package. The Debian postinst registers an apt repository, the Debian dependency names are not Fedora package names, and an old grok-bot `%postun` removes `/usr/bin/grok-bot` during an upgrade. This repo builds the RPM from the deb payload and replaces those scriptlets.

## Requirements

- `dpkg-deb`
- `fpm`
- `rpm` and `rpmbuild`

## Usage

```bash
./grok-bot-deb-to-rpm.sh ~/Downloads/grok-bot_0.66.0_amd64.deb
sudo dnf install ~/Downloads/grok-bot-0.66.0-1.x86_64.rpm
```

The RPM is written next to the deb as `grok-bot-VERSION-1.x86_64.rpm`. Pass `-o` to choose another path and `-f` to overwrite. The script does not install the package.

The converter checks the finished RPM before it exits: identity, the `sand` provide/conflict/obsolete, absence of the apt repository setup, file list, ownership, and modes. When an older grok-bot is already installed, you can also run:

```bash
rpm -Uvh --test grok-bot-VERSION-1.x86_64.rpm
```

## Layout

- `grok-bot-deb-to-rpm.sh` reads the deb, maps dependencies, and runs fpm.
- `packaging/post.sh` is the RPM `%post` and `%posttrans`. `%posttrans` puts `/usr/bin/grok-bot` back after an upgrade.
- `packaging/postun.sh` is the RPM `%postun`. It removes the launcher only on uninstall.

Downloaded `.deb` files and built `.rpm` files are gitignored.

## When it stops

The script refuses to build if the package is not `grok-bot` for `amd64`, if `Depends` contains a package it does not know how to map, if `Conflicts`, `Provides`, or `Replaces` is anything other than `sand`, or if the deb adds a maintainer script. That is deliberate. Update the script for that new deb instead of forcing the old conversion.

## License

Apache License 2.0. See [LICENSE](LICENSE).
