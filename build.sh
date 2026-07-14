#!/bin/bash

SRC_DIR="cursors_scalable"
OUT_DIR="cursors"
TMP_DIR=".tmp_pngs"
BREEZE_DIR="breeze"
SIZES=(24 30 32 48 64 72)

# 初期化
rm -rf "$OUT_DIR" "$TMP_DIR"
sleep 1
mkdir -p "$OUT_DIR" "$TMP_DIR"

echo "=== Syncing structure in $SRC_DIR based on $BREEZE_DIR ==="

# 1. cursors_scalable 内のリンクだけを一度すべて削除して再構築
find "$SRC_DIR" -maxdepth 1 -type l -delete

# 2. breezeを参考にリンクを作成
for item in "$BREEZE_DIR"/*; do
    [ -e "$item" ] || continue
    name=$(basename "$item")

    # リンクの場合のみ、同じリンクを SRC_DIR に作成
    if [ -L "$item" ]; then
        target=$(readlink "$item")
        ln -sf "$target" "$SRC_DIR/$name"
    fi
done

echo "=== Building cursor theme ==="

# 3. ビルド処理
for dir in "$SRC_DIR"/*; do
    # リンクの場合はスキップ（後で出力ディレクトリでリンクを貼る）
    [ -L "$dir" ] && continue
    [ -d "$dir" ] || continue

    cursor_name=$(basename "$dir")
    cfg_file="$OUT_DIR/$cursor_name.cfg"
    json_file="$dir/metadata.json"

    [ ! -f "$json_file" ] && continue
    echo "Processing: $cursor_name"

    for size in "${SIZES[@]}"; do
        jq -c '.[]' "$json_file" | while read -r frame; do
            filename=$(echo "$frame" | jq -r '.filename')
            x=$(echo "$frame" | jq -r '.hotspot_x | round')
            y=$(echo "$frame" | jq -r '.hotspot_y | round')
            delay=$(echo "$frame" | jq -r '.delay // "0"')

            png_path="$(realpath "$TMP_DIR/${cursor_name}_${size}_${filename%.svg}.png")"
            rsvg-convert -w "$size" -h "$size" "$dir/$filename" -o "$png_path"

            if [ "$delay" != "0" ]; then
                printf "%d %d %d %s %d\n" "$size" "$x" "$y" "$png_path" "$delay" >> "$cfg_file"
            else
                printf "%d %d %d %s\n" "$size" "$x" "$y" "$png_path" >> "$cfg_file"
            fi
        done
    done

    # 4. xcursorgen 実行
    if [ -f "$cfg_file" ]; then
        xcursorgen "$cfg_file" "$OUT_DIR/$cursor_name"
        rm "$cfg_file"
    fi
done

# 5. 出力ディレクトリにリンクを反映
echo "=== Creating aliases in $OUT_DIR ==="
for item in "$BREEZE_DIR"/*; do
    [ -e "$item" ] || continue
    name=$(basename "$item")

    if [ -L "$item" ]; then
        target=$(readlink "$item")
        # リンク先のターゲット（ディレクトリ等）が存在する場合のみリンクを作成
        ln -sf "$target" "$OUT_DIR/$name"
    fi
done

rm -rf "$TMP_DIR"
echo "Build complete."
