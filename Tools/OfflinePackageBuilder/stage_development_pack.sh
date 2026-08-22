#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_directory="$repository_root/Data/Generated/tanzawa-detailed-v1/package"
destination_directory="$repository_root/YamaLens/YamaLens/Resources/DevelopmentOfflinePackages/tanzawa-detailed-v1"

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
