#!/usr/bin/env bash
# Punto de entrada desde cualquier directorio; no cambia ramas ni crea commits.
set -euo pipefail
case "${1:-check}" in
  setup|check) mode="${1:-check}" ;;
  *) printf '%s\n' 'Uso: bash scripts/v122.sh [setup|check]' >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf '%s\n' 'Solo se admite un argumento.' >&2; exit 2; }
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/v122-env.sh"
python3 "$script_dir/v122_setup.py" "$mode"
