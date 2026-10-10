#!/usr/bin/env bash
# Cargar con source; no cambia opciones de Bash, perfiles, proxy ni certificados.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf '%s\n' 'Uso: source scripts/v122-env.sh' >&2
  exit 1
fi

_v122_activate() {
  local repo state sdk candidate
  repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)" || return
  state="$(realpath -m -- "${V122_STATE_DIR:-$repo/.codex-v122}")" || return
  candidate="${V122_FLUTTER_ROOT:-${FLUTTER_ROOT:-}}"
  mkdir -p -- "$state/home" "$state/config" "$state/cache" "$state/pub-cache" "$state/lib" || return
  HOME="$state/home" XDG_CONFIG_HOME="$state/config" XDG_CACHE_HOME="$state/cache" \
    PUB_CACHE="$state/pub-cache" V122_STATE_DIR="$state" V122_FLUTTER_ROOT="$candidate" \
    python3 "$repo/scripts/v122_setup.py" prepare || return
  IFS= read -r sdk < "$state/sdk-path" || return
  export V122_REPO_ROOT="$repo" V122_STATE_DIR="$state" FLUTTER_ROOT="$sdk"
  export HOME="$state/home" XDG_CONFIG_HOME="$state/config" XDG_CACHE_HOME="$state/cache"
  export PUB_CACHE="$state/pub-cache"
  # Colocar siempre el SDK seleccionado primero, incluso si había otro Dart.
  case "$PATH" in
    "$sdk/bin:"*) ;;
    *) export PATH="$sdk/bin:$PATH" ;;
  esac
  case ":${LD_LIBRARY_PATH:-}:" in
    *":$state/lib:"*) ;;
    *) export LD_LIBRARY_PATH="$state/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
  esac
}

if _v122_activate; then
  unset -f _v122_activate
else
  unset -f _v122_activate
  return 1
fi
