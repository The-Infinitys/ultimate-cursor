#!/bin/bash

SRC_DIR="cursors_scalable"

echo "=== Cleaning up $SRC_DIR ==="

# 1. cursors_scalable 内のリンクだけをすべて削除
# -type l でシンボリックリンクのみを対象にし、安全に削除します
find "$SRC_DIR" -maxdepth 1 -type l -delete

# 2. 実行結果の確認
if [ $? -eq 0 ]; then
    echo "Success: All symbolic links in $SRC_DIR have been removed."
    echo "You can now focus on editing the source files."
else
    echo "Error: Failed to clean up the directory."
    exit 1
fi
