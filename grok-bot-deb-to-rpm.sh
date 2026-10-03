#!/usr/bin/env bash
# Convert a Grok Bot amd64 .deb into an unsigned x86_64 RPM for this Fedora host.
#
# A plain `fpm -s deb -t rpm` is not enough. The Debian postinst registers an
# apt source Fedora cannot use, Debian package names are not Fedora names, and
# the old grok-bot %postun removes /usr/bin/grok-bot during an upgrade. This
# script packs the deb payload with Fedora dependencies and the scriptlets in
# packaging/. post.sh is %post and %posttrans. postun.sh is %postun.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: grok-bot-deb-to-rpm.sh [-o OUTPUT.rpm] [-f] DEB

Convert a Grok Bot amd64 .deb into an unsigned x86_64 .rpm for Fedora.

  -o PATH   write the rpm here
            (default: grok-bot-VERSION-RELEASE.x86_64.rpm next to the deb)
  -f        overwrite an existing output file

The result is not installed. Install it with:
  sudo dnf install ./grok-bot-VERSION-RELEASE.x86_64.rpm
EOF
}

die() {
  echo "grok-bot-deb-to-rpm: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

trim() {
  local value="$1"
  value=${value//$'\n'/ }
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

output=""
force=0
deb=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -o)
      [[ $# -ge 2 ]] || die "-o needs a path"
      output=$2
      shift 2
      ;;
    -f|--force)
      force=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      [[ -z $deb ]] || die "only one .deb can be converted at a time"
      deb=$1
      shift
      ;;
  esac
done

[[ $# -eq 0 ]] || die "unexpected argument: $1"
[[ -n $deb ]] || {
  usage >&2
  exit 1
}
[[ -f $deb ]] || die "not a file: $deb"

need_cmd dpkg-deb
need_cmd fpm
need_cmd rpm
need_cmd rpmbuild

deb=$(readlink -f "$deb")

pkg=$(trim "$(dpkg-deb -f "$deb" Package)")
raw_version=$(trim "$(dpkg-deb -f "$deb" Version)")
arch=$(trim "$(dpkg-deb -f "$deb" Architecture)")
license=$(trim "$(dpkg-deb -f "$deb" License)")
maintainer=$(trim "$(dpkg-deb -f "$deb" Maintainer)")
homepage=$(trim "$(dpkg-deb -f "$deb" Homepage)")
depends=$(trim "$(dpkg-deb -f "$deb" Depends)")
conflicts=$(trim "$(dpkg-deb -f "$deb" Conflicts)")
provides=$(trim "$(dpkg-deb -f "$deb" Provides)")
replaces=$(trim "$(dpkg-deb -f "$deb" Replaces)")
description=$(dpkg-deb -f "$deb" Description | sed -n 's/^[[:space:]]*//; /^$/d; p' | head -n 1)

[[ $pkg == grok-bot ]] || die "this script only converts grok-bot packages (got: ${pkg:-<empty>})"
[[ $arch == amd64 ]] || die "expected an amd64 deb, got: ${arch:-<empty>}"
[[ -n $raw_version ]] || die "deb has no Version"
[[ -n $description ]] || description="Grok Bot desktop agent"
[[ -n $license ]] || license="unknown"
[[ -n $maintainer ]] || maintainer="SpaceXAI <hi@cursor.com>"
[[ -n $homepage ]] || homepage="https://cursor.com"

# RPM Version cannot contain '-' or ':'. A plain Debian revision becomes Release.
if [[ $raw_version == *:* ]]; then
  die "Debian epochs are not supported ($raw_version)"
fi
if [[ $raw_version == *-* ]]; then
  version=${raw_version%%-*}
  release=${raw_version#*-}
  [[ $release =~ ^[0-9]+$ ]] || die "Debian revision '$release' is not a plain integer"
else
  version=$raw_version
  release=1
fi
[[ $version =~ ^[0-9A-Za-z.+~]+$ ]] || die "version '$version' is not a safe RPM version"

# Fedora package names used by the installed grok-bot RPMs. These cover the
# Electron host libraries that the Debian Depends line names, plus the
# libraries those packages pull in on Debian and that RPM will not pull in
# unless they are listed here. Auto-requires stay off so the bundled .so and
# .node files are not turned into system dependencies.
fedora_deps=(
  alsa-lib
  at-spi2-atk
  at-spi2-core
  atk
  cairo
  cups-libs
  dbus-libs
  desktop-file-utils
  expat
  gdk-pixbuf2
  glib2
  gtk-update-icon-cache
  gtk3
  krb5-libs
  libX11
  libX11-xcb
  libXScrnSaver
  libXcomposite
  libXcursor
  libXdamage
  libXext
  libXfixes
  libXrandr
  libXtst
  libdrm
  libglvnd-glx
  libnotify
  libsecret
  libstdc++
  libuuid
  libxcb
  libxkbcommon
  mesa-libgbm
  nspr
  nss
  pango
  pulseaudio-libs
  shared-mime-info
  systemd-libs
  xdg-utils
)

check_debian_depends() {
  local group alt name ok
  local -a groups alts unknown
  local depends_line=$1
  [[ -n $depends_line ]] || die "deb Depends is empty"
  IFS=',' read -ra groups <<< "$depends_line"
  for group in "${groups[@]}"; do
    ok=0
    unknown=()
    IFS='|' read -ra alts <<< "$group"
    for alt in "${alts[@]}"; do
      alt=$(trim "$alt")
      name=${alt%%[[:space:]]*}
      name=${name%%(*}
      [[ -n $name ]] || continue
      if [[ $name =~ ^(libgtk-3-0|libnotify4|libnss3|libxss1|libxtst6|xdg-utils|libatspi2\.0-0|libuuid1|libsecret-1-0|libasound2t64|libasound2|libgbm1|libxkbcommon0|libdrm2)$ ]]; then
        ok=1
      else
        unknown+=("$name")
      fi
    done
    if [[ $ok -eq 0 ]]; then
      die "Debian Depends has a package this script does not map to Fedora: ${unknown[*]:-<empty>} (group:${group})"
    fi
    if [[ ${#unknown[@]} -gt 0 ]]; then
      echo "warning: ignoring unmapped alternative(s) in '${group}': ${unknown[*]}" >&2
    fi
  done
}

expect_only_sand() {
  local field=$1 value=$2
  local -a parts
  [[ -n $value ]] || die "$field is empty; expected 'sand'"
  read -ra parts <<< "${value//,/ }"
  [[ ${#parts[@]} -eq 1 && ${parts[0]} == sand ]] || die "$field must be exactly 'sand' before this script can convert the deb (got: $value)"
}

check_debian_depends "$depends"
expect_only_sand Conflicts "$conflicts"
expect_only_sand Provides "$provides"
expect_only_sand Replaces "$replaces"

vendor=${maintainer%%<*}
vendor=$(trim "$vendor")
[[ -n $vendor ]] || vendor="SpaceXAI"

if [[ -z $output ]]; then
  output="$(dirname "$deb")/grok-bot-${version}-${release}.x86_64.rpm"
elif [[ $output != /* ]]; then
  output="$(pwd)/$output"
fi
if [[ -e $output && $force -ne 1 ]]; then
  die "output already exists: $output (pass -f to overwrite)"
fi

work=$(mktemp -d)
cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT

dpkg-deb -x "$deb" "$work/root"
dpkg-deb -e "$deb" "$work/control"

[[ -x "$work/root/opt/Grok Bot/grok-bot" ]] || die "deb payload is missing /opt/Grok Bot/grok-bot"

for member in "$work/control"/*; do
  case $(basename "$member") in
    control|md5sums|postinst|postrm) ;;
    *) die "unexpected deb control member '$(basename "$member")'; review it before converting" ;;
  esac
done
[[ -f "$work/control/postinst" && -f "$work/control/postrm" ]] || die "deb is missing postinst or postrm"
grep -q "/opt/Grok Bot/grok-bot" "$work/control/postinst" || die "postinst no longer references /opt/Grok Bot/grok-bot"
grep -q "update-alternatives" "$work/control/postinst" || die "postinst no longer uses update-alternatives"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ -f "$script_dir/packaging/post.sh" && -f "$script_dir/packaging/postun.sh" ]] \
  || die "missing packaging/post.sh or packaging/postun.sh next to this script"

# packaging/post.sh is used for both %post and %posttrans. %posttrans runs after
# the old package's %postun, which on grok-bot 0.30.0 removes the alternatives
# entry during upgrade.
cp "$script_dir/packaging/post.sh" "$work/post.sh"
cp "$script_dir/packaging/postun.sh" "$work/postun.sh"
chmod 755 "$work/post.sh" "$work/postun.sh"

dep_args=()
for dep in "${fedora_deps[@]}"; do
  dep_args+=(-d "$dep")
done

echo "Building grok-bot-${version}-${release}.x86_64.rpm from $(basename "$deb")"
rm -f "$output"
fpm \
  -s dir \
  -t rpm \
  -n grok-bot \
  -v "$version" \
  --iteration "$release" \
  -a x86_64 \
  --license "$license" \
  --vendor "$vendor" \
  -m "$maintainer" \
  --url "$homepage" \
  --description "$description" \
  --category "Applications/Editors" \
  --rpm-summary "$description" \
  --rpm-os linux \
  --rpm-digest sha256 \
  --rpm-compression xz \
  --rpm-use-file-permissions \
  --rpm-user root \
  --rpm-group root \
  --rpm-auto-add-directories \
  --no-auto-depends \
  --provides sand \
  --conflicts sand \
  --replaces sand \
  --after-install "$work/post.sh" \
  --after-remove "$work/postun.sh" \
  --rpm-posttrans "$work/post.sh" \
  "${dep_args[@]}" \
  -C "$work/root" \
  -p "$output" \
  .

[[ -f $output ]] || die "fpm did not write $output"

verify_rpm() {
  local got_name got_version got_release got_arch
  got_name=$(rpm -qp --qf '%{NAME}' "$output")
  got_version=$(rpm -qp --qf '%{VERSION}' "$output")
  got_release=$(rpm -qp --qf '%{RELEASE}' "$output")
  got_arch=$(rpm -qp --qf '%{ARCH}' "$output")
  [[ $got_name == grok-bot && $got_version == "$version" && $got_release == "$release" && $got_arch == x86_64 ]] \
    || die "rpm identity mismatch: ${got_name}-${got_version}-${got_release}.${got_arch}"

  rpm -qp --provides "$output" | grep -qx 'sand' || die "rpm does not provide sand"
  rpm -qp --conflicts "$output" | grep -qx 'sand' || die "rpm does not conflict with sand"
  rpm -qp --obsoletes "$output" | grep -qx 'sand' || die "rpm does not obsolete sand"

  local scripts
  scripts=$(rpm -qp --scripts "$output")
  grep -q "update-alternatives --install '/usr/bin/grok-bot'" <<< "$scripts" || die "rpm %post is missing the launcher setup"
  grep -q 'posttrans scriptlet' <<< "$scripts" || die "rpm is missing %posttrans"
  if grep -E -q 'apt-config|sources\.list|dearmor|downloads\.cursor\.com' <<< "$scripts"; then
    die "rpm scriptlets still register the Debian apt repository"
  fi

  local -A deb_files=() rpm_paths=()
  local line path perm
  while IFS= read -r line; do
    perm=${line%% *}
    [[ $perm == d* ]] && continue
    path="/${line#* ./}"
    path=${path%/}
    deb_files["$path"]=1
  done < <(dpkg-deb -c "$deb")

  while IFS= read -r path; do
    [[ -n $path ]] || continue
    rpm_paths["$path"]=1
  done < <(rpm -qp --list "$output")

  local missing=0
  for path in "${!deb_files[@]}"; do
    if [[ -z ${rpm_paths[$path]+x} ]]; then
      echo "missing from rpm: $path" >&2
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || die "rpm is missing files from the deb"

  local dump_line pkg_size pkg_mode pkg_owner pkg_group file fs_size fs_perm pkg_perm
  while IFS= read -r dump_line; do
    [[ $dump_line =~ ^(.*)[[:space:]]([0-9]+)[[:space:]]([0-9]+)[[:space:]]([0-9a-f]+)[[:space:]]([0-9]+)[[:space:]]([^[:space:]]+)[[:space:]]([^[:space:]]+)[[:space:]]([01])[[:space:]]([01])[[:space:]]([0-9]+)[[:space:]](.*)$ ]] \
      || die "could not parse rpm dump line: $dump_line"
    path=${BASH_REMATCH[1]}
    pkg_size=${BASH_REMATCH[2]}
    pkg_mode=${BASH_REMATCH[5]}
    pkg_owner=${BASH_REMATCH[6]}
    pkg_group=${BASH_REMATCH[7]}
    file="$work/root$path"
    [[ -e $file || -L $file ]] || die "rpm contains $path, which is not in the extracted deb"
    [[ $pkg_owner == root && $pkg_group == root ]] || die "$path is owned by $pkg_owner:$pkg_group, expected root:root"
    if [[ -d $file && ! -L $file ]]; then
      continue
    fi
    [[ -n ${deb_files[$path]+x} ]] || die "rpm has extra file $path"
    fs_size=$(stat -c '%s' "$file")
    [[ $fs_size == "$pkg_size" ]] || die "$path size mismatch: deb $fs_size, rpm $pkg_size"
    pkg_perm=$((8#${pkg_mode: -4}))
    fs_perm=$((8#$(stat -c '%a' "$file")))
    [[ $pkg_perm -eq $fs_perm ]] || die "$path mode mismatch: deb $(printf '%04o' "$fs_perm"), rpm $(printf '%04o' "$pkg_perm")"
  done < <(rpm -qp --dump "$output")
}

verify_rpm
echo "Wrote $output"
echo "Install with: sudo dnf install $output"
