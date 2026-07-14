#!/bin/bash

SRC_DIR="cursors_scalable"
OUT_DIR="cursors"
TMP_DIR=".tmp_pngs"
DEFAULT_CURSOR="default"
SIZES=(24 32 48 64)
# 初期化
rm -rf "$OUT_DIR" "$TMP_DIR"
sleep 1
mkdir -p "$OUT_DIR" "$TMP_DIR"

echo "Building cursor theme..."

# エイリアス定義（関数化して再利用）
declare -A aliases=(
    ["arrow"]="default" ["left_ptr"]="default" ["size-bdiag"]="default"
    ["size-fdiag"]="default" ["size-hor"]="default" ["size-ver"]="default"
    ["top_left_arrow"]="default" ["circle"]="not-allowed" ["crossed_circle"]="not-allowed"
    ["forbidden"]="no-drop" ["grab"]="openhand" ["grabbing"]="closedhand"
    ["closedhand"]="dnd-move" ["dnd-none"]="dnd-move" ["move"]="dnd-move"
    ["dnd-copy"]="copy" ["cross"]="crosshair" ["tcross"]="crosshair"
    ["e-resize"]="size_hor" ["ew-resize"]="size_hor" ["h_double_arrow"]="size_hor"
    ["sb_h_double_arrow"]="size_hor" ["w-resize"]="size_hor" ["n-resize"]="size_ver"
    ["ns-resize"]="size_ver" ["s-resize"]="size_ver" ["sb_v_double_arrow"]="size_ver"
    ["v_double_arrow"]="size_ver" ["ne-resize"]="size_bdiag" ["nesw-resize"]="size_bdiag"
    ["sw-resize"]="size_bdiag" ["nw-resize"]="size_fdiag" ["nwse-resize"]="size_fdiag"
    ["se-resize"]="size_fdiag" ["half-busy"]="progress" ["left_ptr_watch"]="progress"
    ["wait"]="progress" ["watch"]="wait" ["hand1"]="pointer"
    ["hand2"]="pointer" ["pointing_hand"]="pointer" ["ibeam"]="text"
    ["xterm"]="text" ["link"]="alias" ["left_ptr_help"]="help"
    ["question_arrow"]="help" ["whats_this"]="help" ["plus"]="cell"
    ["size_all"]="fleur" ["split_h"]="col-resize" ["split_v"]="row-resize"
)

# 1. cursors_scalable 側への自動リンク作成
echo "Syncing aliases in source directory..."
for alias_name in "${!aliases[@]}"; do
    target="${aliases[$alias_name]}"
    if [ ! -d "$SRC_DIR/$alias_name" ]; then
        # ターゲットディレクトリがソースに存在しない場合は default を継承させる
        if [ -d "$SRC_DIR/$target" ]; then
            ln -sf "$target" "$SRC_DIR/$alias_name"
        else
            ln -sf "$DEFAULT_CURSOR" "$SRC_DIR/$alias_name"
        fi
    fi
done
# 1. 各ディレクトリ処理
for dir in "$SRC_DIR"/*; do
    [ -d "$dir" ] || continue
    [ -L "$dir" ] && continue # リンクは飛ばす
    cursor_name=$(basename "$dir")
    cfg_file="$OUT_DIR/$cursor_name.cfg"
    json_file="$dir/metadata.json"

    [ ! -f "$json_file" ] && continue
    echo "Processing: $cursor_name"

    # 全サイズ分をcfgに追記する
    for size in "${SIZES[@]}"; do
        jq -c '.[]' "$json_file" | while read -r frame; do
            filename=$(echo "$frame" | jq -r '.filename')
            # metadataのサイズではなく、現在ループ中のサイズを使用
            x=$(echo "$frame" | jq -r '.hotspot_x')
            y=$(echo "$frame" | jq -r '.hotspot_y')
            # 座標をサイズ比率に合わせてスケール調整（必要なら）
            # ここでは単純に座標を流し込むが、本来は x * size / 24 等の計算が必要

            delay=$(echo "$frame" | jq -r '.delay // "0"')

            png_path="$TMP_DIR/${cursor_name}_${size}_${filename%.svg}.png"
            rsvg-convert -w "$size" -h "$size" "$dir/$filename" -o "$png_path"

            if [ "$delay" != "0" ]; then
                echo "$size $x $y $png_path $delay" >> "$cfg_file"
            else
                echo "$size $x $y $png_path" >> "$cfg_file"
            fi
        done
    done

    # 2. xcursorgen 実行
    [ -f "$cfg_file" ] && xcursorgen "$cfg_file" "$OUT_DIR/$cursor_name" && rm "$cfg_file"
done

# 3. 出力先ディレクトリへのエイリアス作成
echo "Creating aliases in output directory..."
for alias_name in "${!aliases[@]}"; do
    target="${aliases[$alias_name]}"
    [ ! -f "$OUT_DIR/$target" ] && target="$DEFAULT_CURSOR"
    ln -sf "$target" "$OUT_DIR/$alias_name"
done

rm -rf "$TMP_DIR"
echo "Build complete."
