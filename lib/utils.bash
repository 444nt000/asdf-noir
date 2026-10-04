#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/noir-lang/noir"
TOOL_NAME="noir"
TOOL_TEST="nargo --version"

fail() {
  echo "asdf-${TOOL_NAME}: $*" >&2
  exit 1
}

curl_opts=(-fsSL)

if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4 -k 5,5n | awk '{print $2}'
}

# Keep only tags with downloadable binaries (e.g. 0.36.0, 1.0.0-beta.16, 1.0.0-rc.2).
list_all_versions() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/v[0-9].*' |
    sed 's|^refs/tags/v||' |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$' |
    grep -v '^0\.0\.'
}

latest_version() {
  local redirect_url
  redirect_url="$(curl -sI "$GH_REPO/releases/latest" | sed -n 's|^location: *||Ip' | tr -d '\r')"

  if [[ $redirect_url == */tag/v* ]]; then
    echo "${redirect_url##*/tag/v}"
  else
    list_all_versions | sort_versions | tail -n1
  fi
}

# Nightlies are tagged without the "v" prefix (e.g. nightly-2026-10-03).
release_tag() {
  local version="$1"

  if [[ $version == nightly* ]]; then
    echo "$version"
  else
    echo "v$version"
  fi
}

detect_target() {
  local os arch libc="gnu"

  case "$(uname -s)" in
    Linux)
      os="unknown-linux"
      if ldd --version 2>&1 | grep -qi musl; then
        libc="musl"
      fi
      ;;
    Darwin) os="apple-darwin" ;;
    *) fail "Unsupported OS: $(uname -s)" ;;
  esac

  case "$(uname -m)" in
    x86_64 | amd64) arch="x86_64" ;;
    aarch64 | arm64) arch="aarch64" ;;
    *) fail "Unsupported architecture: $(uname -m)" ;;
  esac

  if [ "$os" = "unknown-linux" ]; then
    echo "${arch}-${os}-${libc}"
  else
    echo "${arch}-${os}"
  fi
}

# Archives were named nargo-<target>.tar.gz until 1.0.0-beta.16 and noir-<target>.tar.gz since.
download_release() {
  local version="$1"
  local filename="$2"
  local tag target url

  tag="$(release_tag "$version")"
  target="$(detect_target)"

  echo "* Downloading ${TOOL_NAME} release ${version} (${target})..."
  for prefix in noir nargo; do
    url="${GH_REPO}/releases/download/${tag}/${prefix}-${target}.tar.gz"
    if curl "${curl_opts[@]}" -o "$filename" "$url" 2>/dev/null; then
      return 0
    fi
  done

  fail "No ${target} release found for ${version} (tag ${tag})"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="${3%/bin}/bin"

  if [ "$install_type" != "version" ]; then
    fail "asdf-${TOOL_NAME} supports release installs only"
  fi

  (
    mkdir -p "$install_path"
    cp -R "${ASDF_DOWNLOAD_PATH}/." "$install_path"

    local tool_cmd
    tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
    test -x "$install_path/$tool_cmd" || fail "Expected $install_path/$tool_cmd to be executable."

    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error occurred while installing $TOOL_NAME $version."
  )
}
