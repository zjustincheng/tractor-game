#!/usr/bin/env sh
set -eu

archive=${1:?Usage: validate-backup.sh backup.tar.gz}
case "$archive" in
  *.tar.gz) ;;
  *) echo "Backup must end in .tar.gz" >&2; exit 1 ;;
esac
[ -f "$archive" ] || { echo "Backup does not exist: $archive" >&2; exit 1; }

tar -tzf "$archive" >/dev/null
echo "Archive is readable: $archive"
