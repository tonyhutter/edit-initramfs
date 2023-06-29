#!/bin/bash
#
# Simple script to extract/edit/rebuild an initramfs image.  This makes it easy
# to quickly make edits to the contents of an initramfs.  This script works
# in a three step process:
#
# 1. Extract the initramfs image to a empty directory
# 2. Edit the extracted initramfs files
# 3. Rebuild a new initramfs image
#
# An initramfs image is just a concatenation of one or more CPIO archives.
# Typically it consists of an initial uncompressed archive containing microcode
# for the CPU, followed by a compressed archive containing the actual root
# filesystem.  You will see these two archives as the 'part0' and 'part1'
# directories in the extracted initramfs directory.  99% of the time you'll
# just be editing the root file system in 'part1'.
#
# Note: this only works on initramfs images, not initrd images.  initrd images
# are actual filesystem images, not CPIO archives.
#
# Copyright 2023 Lawrence Livermore National Security, LLC.
#
# SPDX-License-Identifier: MIT
#
function usage {
    echo "Usage:"
    echo ""
    echo "    Extract initramfs:"
    echo "        edit-initramfs.sh INITRAMFS_IMAGE EXTRACTED_INITRAMFS_DIR"
    echo ""
    echo "    [ Edit your initramfs files in EXTRACTED_INITRAMFS_DIR ]"
    echo ""
    echo "    Rebuild initramfs:"
    echo "        edit-initramfs.sh EXTRACTED_INITRAMFS_DIR NEW_INITRAMFS_IMAGE"
    echo ""
    echo "Example:"
    echo ""
    echo "    mkdir /tmp/my_initramfs_files"
    echo "    edit-initramfs.sh initramfs.img /tmp/my_initramfs_files"
    echo "    echo hello world > /tmp/my_initramfs_files/part1/etc/hello.txt"
    echo "    edit-initramfs.sh /tmp/my_initramfs_files new_initramds.img"
    echo ""
}

cpio_dir_prefix=part
cpio_file_prefix=part_file

function get_size {
    stat --printf="%s" $1
}

function do_decompress {
    local input_image="$1"
    local extract_dir="$2"
    start_block=0
    input_image_size=$(get_size $input_image)

    # Iterate though each CPIO in the initramfs
    count=0
    while [ 1 ] ; do
        cpio_dir=$extract_dir/$cpio_dir_prefix$count
        cpio_file=$extract_dir/$cpio_file_prefix$count

        if [[ $(($start_block * 512)) -ge $input_image_size ]] ; then
            # All done
           break
        fi

        dd status=none if=$input_image of=$cpio_file bs=512 skip=$start_block
        tmp="$(file $cpio_file)"
        extra_args=""
        compression=""
        if echo "$tmp" | grep -q 'gzip' ; then
            compression=gzip
            if echo "$tmp" | grep -q 'max compression' ; then
                extra_args='--best'
            fi
            mv $cpio_file $cpio_file.gz
            gunzip $cpio_file
        fi

        # Record whether or not we need to compress this later (and optional
        # compression extra_args).
        echo "compression=$compression" > $extract_dir/$cpio_dir_prefix$count.meta
        echo "extra_args=$extra_args" >> $extract_dir/$cpio_dir_prefix$count.meta

        mkdir $cpio_dir
        new_block=$(cpio -D $cpio_dir -i -F $cpio_file 2>&1 | cut -d' ' -f1)
        rm $cpio_file

        re='^[0-9]+$'
        if ! [[ $new_block =~ $re ]] ; then
            # '$new_block' did not contain a block number count.  We're
            # at the end of our CPIO.
            break
        fi
        if [[ $new_block -le $start_block ]] ; then
            break
        fi

        start_block=$new_block
        let "count++"
    done

    echo "Successfully decompressed $count parts from:"
    echo ""
    echo "$input_image"
    echo ""
    echo "to:"
    echo ""
    echo "$extract_dir"
    echo ""
    echo "You may now edit the files in $extract_dir and then recompress it" \
         "to an initramfs with:"
    echo ""
    echo "$0 $extract_dir"
    echo ""
    echo "or:"
    echo ""
    echo "$0 $extract_dir path_to_new_initramfs"
    echo ""
}

function do_compress {
    local extract_dir="$1"
    local output_image="$2"

    # Iterate though each extracted CPIO from the initramfs
    count=0
    while [ 1 ] ; do
        cpio_dir=$extract_dir/$cpio_dir_prefix$count
        cpio_file=$extract_dir/$cpio_file_prefix.recompress.$count

        if [ ! -d $cpio_dir ] ; then
            # All done
            break
        fi

        pushd $cpio_dir &> /dev/null
        source $extract_dir/$cpio_dir_prefix$count.meta

        if [ $count -eq 0 ] ; then
            truncate -s 0 $output_image
        fi

        if [ "$compression" == "gzip" ] ; then
            find . | cpio -H newc --quiet -o | gzip $extra_args >> $output_image
        else
            find . | cpio -H newc --quiet -o >> $output_image
        fi
        popd &> /dev/null

        let "count++"
    done

    echo "Successfully compressed files in:"
    echo ""
    echo "$extract_dir"
    echo ""
    echo "to:"
    echo ""
    echo "$output_image"
    echo ""
    echo "Note that $extract_dir still has old initramfs files in it and" \
         "may need to be deleted."
}

function sanity {
    if ! file $1 | grep -Eq 'cpio archive|gzip compressed data' ; then
        echo "ERROR: $1 does not appear to be an initramfs image"
        exit 1
    fi
}

if [[ "$EUID" -ne 0 ]]; then
    echo "WARNING: It's recommended you run as root to preserve initramfs file permissions"
fi

if [ -z "$1" ] ; then
    usage
    exit
fi

if [ -d "$1" ] ; then
    extract_dir="$1"
    if ! [ -d "$extract_dir/part0" ] ; then
        echo "ERROR: $extract_dir doesn't contain extracted initramfs files"
        exit 1
    fi
    if [ -n "$2" ] ; then
        output_image="$(readlink -f $2)"
    else
        echo "ERROR: Please specify a new initramfs image filename"
        exit 1
    fi

    do_compress "$extract_dir" "$output_image"
else
    # Decompress
    input_image="$(readlink -f $1)"
    sanity "$input_image"

    if [ -n "$2" ] ; then
        if [ -d "$2" ] ; then
            extract_dir="$2"
            if ! [ -z "$(ls -A $extract_dir)" ] ; then
                echo "ERROR: $extract_dir is not empty"
                exit 1
            fi
        else
            echo "ERROR: $extract_dir directory doesn't exist"
            exit 1
        fi
    else
        echo "ERROR: Please specify a directory to extract the initramfs into"
        exit 1
    fi
    do_decompress "$input_image" "$extract_dir"
fi
