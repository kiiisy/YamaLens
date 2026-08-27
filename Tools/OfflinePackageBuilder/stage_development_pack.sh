#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
package_directory_name=${1:-tanzawa-detailed-v1}
bundle_directory_name=${2:-$package_directory_name}

for directory_name in "$package_directory_name" "$bundle_directory_name"; do
case "$directory_name" in
    *[!A-Za-z0-9._-]*|'')
        echo "Package directory name may contain only letters, digits, period, underscore, and hyphen." >&2
        exit 1
        ;;
esac
done

source_directory="$repository_root/Data/Generated/$package_directory_name/package"
destination_directory="$repository_root/YamaLens/YamaLens/Resources/DevelopmentOfflinePackages/$bundle_directory_name.bundle"

required_files="manifest.json manifest.sig catalog.sqlite terrain.lzfse"

for file_name in $required_files; do
    source_file="$source_directory/$file_name"
    if [ ! -f "$source_file" ] || [ -L "$source_file" ]; then
        echo "Missing or invalid generated package file: $source_file" >&2
        exit 1
    fi
done

mkdir -p "$destination_directory"
for file_name in $required_files; do
    cp -f "$source_directory/$file_name" "$destination_directory/$file_name"
done

echo "Development offline package staged at:"
echo "$destination_directory"
