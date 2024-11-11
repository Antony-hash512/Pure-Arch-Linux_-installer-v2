#!/bin/bash
current_dir=$(dirname "${BASH_SOURCE[0]}")
$current_dir/set_cyr_font.sh
#$current_dir/fix_dns.sh
$current_dir/use_cache.sh
$current_dir/mount_scripts_folder.sh

