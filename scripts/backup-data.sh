#!/usr/bin/env sh
set -eu

source_dir=${1:-data/matches}
destination=${2:-"backup-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"}

if [ ! -d "$source_dir" ]; then
  echo "Backup source does not exist: $source_dir" >&2
  exit 1
fi
case "$destination" in
  *.tar.gz) ;;
  *) echo "Backup destination must end in .tar.gz" >&2; exit 1 ;;
esac

parent=$(dirname -- "$source_dir")
name=$(basename -- "$source_dir")
tar -czf "$destination" -C "$parent" "$name"
echo "Created backup: $destination"
