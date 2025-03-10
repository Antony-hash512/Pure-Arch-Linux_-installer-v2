#!/bin/bash
#создаём архив root.tar.gz с ключом для полных путей, список берется из файла root_list
mv ../rootfiles.tar.gz ../rootfiles_bkp$(date +%Y%m%d_%H%M%S)_$RANDOM.tar.gz
tar -czpf ../rootfiles.tar.gz -P --files-from root_list