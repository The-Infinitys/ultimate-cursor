#!/bin/bash

SRC_DIR="cursors_scalable"
OUT_DIR="windows"  # Windows用に変更
TMP_DIR=".tmp_pngs"
BREEZE_DIR="breeze"
# Windowsの標準推奨サイズに最適化
SIZES=(24 32 48 64)

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

    if [ -L "$item" ]; then
        target=$(readlink "$item")
        ln -sf "$target" "$SRC_DIR/$name"
    fi
done

echo "=== Building Windows cursor theme ==="

# PythonによるWindows用.curバイナリ作成関数の定義
# すべてのフレーム入力を静止画のマルチサイズ対応 .cur ファイルとしてパッキングします
generate_windows_cursor() {
    python3 - "$@" << 'EOF'
import sys
import struct
from pathlib import Path

def build_cursor(cursor_name, cfg_path, out_dir):
    with open(cfg_path, 'r') as f:
        lines = [line.strip().split() for line in f if line.strip() and not line.startswith('#')]

    if not lines:
        return

    out_dir_path = Path(out_dir)
    out_path = out_dir_path / f"{cursor_name}.cur"

    # 重複サイズを排除し、静止カーソル用のユニークなサイズリストを作成（最初のフレームのみ採用）
    seen_sizes = set()
    unique_lines = []
    for line in lines:
        size = int(line[0])
        if size not in seen_sizes:
            seen_sizes.add(size)
            unique_lines.append(line)

    # --- .cur (Windows Static Cursor) のビルド ---
    # ICONDIR ヘッダ: 予約(0), タイプ(2=Cursor), リソース数
    icon_dir = struct.pack('<HHH', 0, 2, len(unique_lines))
    entries = b""
    image_data = b""
    offset = 6 + len(unique_lines) * 16

    for line in unique_lines:
        size = int(line[0])
        x = int(line[1])
        y = int(line[2])
        png_p = line[3]

        with open(png_p, 'rb') as img_f:
            png_bytes = img_f.read()

        w = 0 if size >= 256 else size
        h = 0 if size >= 256 else size

        # ICONDIRENTRY (Cursor仕様: 幅, 高さ, 色数, 予約, ホットスポットX, ホットスポットY, データサイズ, オフセット)
        entries += struct.pack('<BBBBHHII', w, h, 0, 0, x, y, len(png_bytes), offset)
        image_data += png_bytes
        offset += len(png_bytes)

    with open(out_path, 'wb') as out_f:
        out_f.write(icon_dir + entries + image_data)

if __name__ == '__main__':
    build_cursor(sys.argv[1], sys.argv[2], sys.argv[3])
EOF
}

# 3. ビルド処理
for dir in "$SRC_DIR"/*; do
    [ -L "$dir" ] && continue
    [ -d "$dir" ] || continue

    cursor_name=$(basename "$dir")
    cfg_file="$OUT_DIR/$cursor_name.cfg"
    json_file="$dir/metadata.json"

    [ ! -f "$json_file" ] && continue
    echo "Processing: $cursor_name"

    # 各サイズごとのPNGをレンダリングしcfgに書き出し
    for size in "${SIZES[@]}"; do
        jq -c '.[]' "$json_file" | while read -r frame; do
            filename=$(echo "$frame" | jq -r '.filename')
            x=$(echo "$frame" | jq -r '.hotspot_x | round')
            y=$(echo "$frame" | jq -r '.hotspot_y | round')

            png_path="$TMP_DIR/${cursor_name}_${size}_${filename%.svg}.png"
            rsvg-convert -w "$size" -h "$size" "$dir/$filename" -o "$png_path"

            printf "%d %d %d %s\n" "$size" "$x" "$y" "$png_path" >> "$cfg_file"
        done
    done

    # 4. Windows用バイナリコンバータの実行
    if [ -f "$cfg_file" ]; then
        generate_windows_cursor "$cursor_name" "$cfg_file" "$OUT_DIR"
        rm "$cfg_file"
    fi
done

# 5. 不要になった一時ディレクトリの削除のみ実行（コピー処理は完全撤廃）
rm -rf "$TMP_DIR"
echo "Windows build complete. Check the '$OUT_DIR' directory!"

# 生成されたオリジナル名（text.cur等）を直接割り当てたインストーラー
cat << 'EOF' > windows/install.inf
[Version]
Signature="$Windows NT$"

[DefaultInstall]
CopyFiles = Scheme.Cur
AddReg    = Scheme.Reg

[DestinationDirs]
Scheme.Cur = 10,"Cursors\%CUR_DIR%"

[Scheme.Reg]
HKCU,"Control Panel\Cursors\Schemes","%SCHEME_NAME%",,"%10%\Cursors\%CUR_DIR%\%pointer%",%10%\Cursors\%CUR_DIR%\%help%",%10%\Cursors\%CUR_DIR%\%work%",%10%\Cursors\%CUR_DIR%\%busy%",%10%\Cursors\%CUR_DIR%\%cross%",%10%\Cursors\%CUR_DIR%\%text%",%10%\Cursors\%CUR_DIR%\%hand%",%10%\Cursors\%CUR_DIR%\%unavailiable%",%10%\Cursors\%CUR_DIR%\%vert%",%10%\Cursors\%CUR_DIR%\%horz%",%10%\Cursors\%CUR_DIR%\%dgn1%",%10%\Cursors\%CUR_DIR%\%dgn2%",%10%\Cursors\%CUR_DIR%\%move%",%10%\Cursors\%CUR_DIR%\%alternate%",%10%\Cursors\%CUR_DIR%\%link%"

[Scheme.Cur]
%pointer%
%help%
%work%
%busy%
%cross%
%text%
%hand%
%unavailiable%
%vert%
%horz%
%dgn1%
%dgn2%
%move%
%alternate%
%link%

[Strings]
CUR_DIR       = "BeyondTheInfinite"
SCHEME_NAME   = "Beyond The Infinite"
pointer       = "default.cur"
help          = "help.cur"
work          = "progress.cur"
busy          = "wait.cur"
cross         = "crosshair.cur"
text          = "text.cur"
hand          = "pencil.cur"
unavailiable  = "not-allowed.cur"
vert          = "size_ver.cur"
horz          = "size_hor.cur"
dgn1          = "size_fdiag.cur"
dgn2          = "size_bdiag.cur"
move          = "fleur.cur"
alternate     = "up-arrow.cur"
link          = "pointer.cur"
EOF

