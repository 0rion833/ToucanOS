#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="$BASE_DIR/rootfs"
BOOT="$BASE_DIR/boot"
ISO_DIR="$BASE_DIR/iso_root"
ISO_PATH="$BASE_DIR/ToucanOS.iso"

if [ ! -f "$BOOT/bzImage" ]; then
    echo "[-] Error: $BOOT/bzImage not found!"
    exit 1
fi

echo "[+] Building full rootfs..."
rm -rf "$ROOTFS" "$ISO_DIR"
mkdir -p "$ROOTFS"/{bin,sbin,usr/bin,usr/sbin,proc,sys,dev,dev/pts,etc,root,tmp,run}
mkdir -p "$ISO_DIR/boot/grub"

echo "[+] Setting up BusyBox..."
if [ ! -f "$BOOT/busybox" ]; then
    wget -q -O "$BOOT/busybox" https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
fi
cp "$BOOT/busybox" "$ROOTFS/bin/busybox"
chmod +x "$ROOTFS/bin/busybox"

# Essential device nodes
mknod -m 600 "$ROOTFS/dev/console" c 5 1 2>/dev/null
mknod -m 666 "$ROOTFS/dev/null" c 1 3 2>/dev/null
mknod -m 666 "$ROOTFS/dev/tty" c 5 0 2>/dev/null

for i in $(seq 1 4); do
    mknod -m 666 "$ROOTFS/dev/tty$i" c 4 $i 2>/dev/null
done

# Generate BusyBox symlinks
cd "$ROOTFS"
for app in $("$ROOTFS/bin/busybox" --list); do
    ln -sf /bin/busybox "bin/$app" 2>/dev/null
    ln -sf /bin/busybox "sbin/$app" 2>/dev/null
    ln -sf /bin/busybox "usr/bin/$app" 2>/dev/null
    ln -sf /bin/busybox "usr/sbin/$app" 2>/dev/null
done

echo "[+] Copying configurations and scripts..."
cp "$BASE_DIR/config/profile" "$ROOTFS/etc/profile"
cp "$BASE_DIR/src/toucanfetch" "$ROOTFS/bin/toucanfetch" 2>/dev/null || true
cp "$BASE_DIR/src/init" "$ROOTFS/init"

chmod +x "$ROOTFS/init"
[ -f "$ROOTFS/bin/toucanfetch" ] && chmod +x "$ROOTFS/bin/toucanfetch"

echo "[+] Packing initramfs..."
cd "$ROOTFS"
find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$BOOT/initramfs.cpio.gz"

echo "[+] Building ISO..."
cp "$BOOT/bzImage" "$ISO_DIR/boot/bzImage"
cp "$BOOT/initramfs.cpio.gz" "$ISO_DIR/boot/initramfs.cpio.gz"
cp "$BASE_DIR/config/grub.cfg" "$ISO_DIR/boot/grub/grub.cfg"

grub-mkrescue -o "$ISO_PATH" "$ISO_DIR" 2>/dev/null

if [ -f "$ISO_PATH" ]; then
    echo "[+] ISO successfully built!"
    echo "[+] Launching QEMU..."
    qemu-system-x86_64 -cdrom "$ISO_PATH" -m 256 -vga std
else
    echo "[-] ISO build failed."
fi
