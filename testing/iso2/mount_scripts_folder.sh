#!/bin/bash
fld_name="/mnt/instalation_scripts_$(date +%s)_$RANDOM"
mkdir -p $fld_name
mount -t 9p -o trans=virtio inst_scripts $fld_name
echo "$fld_name created:"
cd $fld_name
ls -la
#bash
