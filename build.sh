#!/bin/sh

set -ex

BASE_IMAGE_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/36/Container/aarch64/images/Fedora-Container-Base-36-1.5.aarch64.tar.xz"
BASE_IMAGE="$(basename "$BASE_IMAGE_URL")"

DL="$PWD/dl"
ROOT="$PWD/root"
FILES="$PWD/files"
IMAGES="$PWD/images"
IMG="$PWD/img"

EFI_UUID=2ABF-9F91
ROOT_UUID=725346d2-f127-47bc-b464-9dd46155e8d6
export ROOT_UUID EFI_UUID

if [ "$(whoami)" != "root" ]; then
    echo "You must be root to run this script."
    exit 1
fi

clean_mounts() {
	while grep -q "$ROOT/[^ ]" /proc/mounts; do
		cat /proc/mounts | grep "$ROOT" | cut -d" " -f2 | xargs umount || true
		sleep 0.1
	done
}

clean_mounts

umount "$IMG" 2>/dev/null || true
mkdir -p "$DL" "$IMG"

if [ ! -e "$DL/$BASE_IMAGE" ]; then
    echo "## Downloading base image..."
    wget -c "$BASE_IMAGE_URL" -O "$DL/$BASE_IMAGE.part"
    mv "$DL/$BASE_IMAGE.part" "$DL/$BASE_IMAGE"
fi

umount "$ROOT" 2>/dev/null || true
rm -rf "$ROOT"
mkdir -p "$ROOT"

echo "## Unpacking base image..."
cd "$ROOT"
bsdtar -xpf "$DL/$BASE_IMAGE" -C "$ROOT"
tar -xOf "$DL/$BASE_IMAGE" --wildcards --no-anchored 'layer.tar' | bsdtar -xpf -
cd -

cp -r "$FILES" "$ROOT"

mount --bind "$ROOT" "$ROOT"

make_uefi_image() {
    imgname="$1"
    img="$IMAGES/$imgname"
    mkdir -p "$img"
    echo "## Making image $imgname"
    echo "### Creating EFI system partition tree..."
    mkdir -p "$img/esp"
    echo "### Compressing..."
    rm -f "$img".zip
    ( cd "$img"; zip -r ../"$imgname".zip * )
    echo "### Done"
}

make_image() {
    imgname="$1"
    img="$IMAGES/$imgname"
    mkdir -p "$img"
    echo "## Making image $imgname"
    echo "### Calculating image size..."
    size="$(du -B M -s "$ROOT" | cut -dM -f1)"
    echo "### Image size: $size MiB"
    size=$(($size + ($size / 8) + 64))
    echo "### Padded size: $size MiB"
    rm -f "$img/root.img"
    truncate -s "${size}M" "$img/root.img"
    echo "### Making filesystem..."
    mkfs.ext4 -O '^metadata_csum' -U "$ROOT_UUID" -L "asahi-root" "$img/root.img"
    echo "### Loop mounting..."
    mount -o loop "$img/root.img" "$IMG"
    echo "### Copying files..."
    rsync -aHAX \
        --exclude /files \
        --exclude '/tmp/*' \
        --exclude /etc/machine-id \
        --exclude '/boot/efi/*' \
        "$ROOT/" "$IMG/"
    echo "### Unmounting..."
    umount "$IMG"
    echo "### Creating EFI system partition tree..."
    mkdir -p "$img/esp/EFI/BOOT"
    echo "### Compressing..."
    rm -f "$img".zip
    ( cd "$img"; zip -1 -r ../"$imgname".zip * )
    echo "### Done"
}

make_image
make_uefi_image "uefi-only"

