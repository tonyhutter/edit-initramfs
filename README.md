# edit-initramfs.sh - A simple initramfs editor

`edit-initramfs.sh` is a simple script to extract, edit, and rebuild an initramfs image.  This makes it easy to quickly make edits to the contents of an initramfs.  The script works in a three step process:

1. Extract the initramfs image to a empty directory
2. Edit the extracted initramfs files
3. Rebuild a new initramfs image

## Usage:
### Extract initramfs:
```sh
edit-initramfs.sh  INITRAMFS_IMAGE  EXTRACTED_INITRAMFS_DIR
```
### Rebuild initramfs:
```sh
edit-initramfs.sh  EXTRACTED_INITRAMFS_DIR  NEW_INITRAMFS_IMAGE
```
### Example:
```sh
mkdir /tmp/my_initramfs_files
edit-initramfs.sh initramfs.img /tmp/my_initramfs_files
echo hello world > /tmp/my_initramfs_files/part1/etc/hello.txt
edit-initramfs.sh /tmp/my_initramfs_files new_initramds.img
```
edit-initramfs.sh is distributed under the terms of the MIT license. All new contributions must be made under this license.

LLNL-CODE-850891
