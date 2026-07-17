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

# PythonによるWindows用.cur/.aniバイナリ作成関数の定義
# 外部モジュール不要、純粋な標準パッケージ(struct)のみでバイナリを組み立てます
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

    # アニメーションカーソル (.ani) か静止カーソル (.cur) か判定
    is_animated = any(len(l) >= 5 for l in lines)
    out_dir_path = Path(out_dir)

    if not is_animated:
        # --- .cur (Windows Static Cursor) のビルド ---
        # 複数サイズ(マルチアイコン構造)に対応
        out_path = out_dir_path / f"{cursor_name}.cur"
        icon_dir = struct.pack('<HHH', 0, 2, len(lines)) # 2 = Cursor type
        entries = b""
        image_data = b""
        offset = 6 + len(lines) * 16

        for line in lines:
            size = int(line[0])
            x = int(line[1])
            y = int(line[2])
            png_p = line[3]

            with open(png_p, 'rb') as img_f:
                png_bytes = img_f.read()

            w = 0 if size >= 256 else size
            h = 0 if size >= 256 else size

            # ICONDIRENTRY (Cursor仕様: ホットスポットを内包)
            entries += struct.pack('<BBBBHHII', w, h, 0, 0, x, y, len(png_bytes), offset)
            image_data += png_bytes
            offset += len(png_bytes)

        with open(out_path, 'wb') as out_f:
            out_f.write(icon_dir + entries + image_data)

    else:
        # --- .ani (Windows Animated Cursor) のビルド ---
        out_path = out_dir_path / f"{cursor_name}.ani"

        # WindowsのRIFF-ANIフォーマットに準拠したコマのパッキング
        # 簡易的に最初のフレームのホットスポットとディレイ情報を適用します
        frames_png = [l[3] for l in lines]
        steps = len(frames_png)
        jif_rate = int(lines[0][4]) if len(lines[0]) >= 5 else 6 # 基準ディレイ

        # 単一フレームアイコンのバイト配列リスト
        icon_frames = []
        for line in lines:
            size, x, y, png_p = int(line[0]), int(line[1]), int(line[2]), line[3]
            with open(png_p, 'rb') as img_f:
                png_bytes = img_f.read()
            # ANI内の各コマは独立した1フレーム用CURバイナリ構造にする
            header = struct.pack('<HHH', 0, 2, 1)
            entry = struct.pack('<BBBBHHII', size, size, 0, 0, x, y, len(png_bytes), 22)
            icon_frames.append(header + entry + png_bytes)

        # RIFFチャンクの組み立て
        anih_chunk = struct.pack('<IIIIIIIIII', 36, 36, steps, steps, 0, 0, 32, 1, jif_rate, 1)

        # LIST 'fram' チャンクの作成
        list_content = b""
        for frame_bytes in icon_frames:
            # 各フレームは 'icon' チャンクに収納
            pad = b'\x00' if len(frame_bytes) % 2 != 0 else b""
            list_content += b'icon' + struct.pack('<I', len(frame_bytes)) + frame_bytes + pad

        fram_list = b'LIST' + struct.pack('<I', len(list_content) + 4) + b'fram' + list_content

        # 全体をACON RIFFとして結合
        riff_header = b'RIFF'
        anih_header = b'anih' + struct.pack('<I', len(anih_chunk)) + anih_chunk

        total_len = len(anih_header) + len(fram_list) + 4
        full_ani = riff_header + struct.pack('<I', total_len) + b'ACON' + anih_header + fram_list

        with open(out_path, 'wb') as out_f:
            out_f.write(full_ani)

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

    # 元のロジックのまま、各サイズごとのPNGをレンダリングしcfgに書き出し
    for size in "${SIZES[@]}"; do
        jq -c '.[]' "$json_file" | while read -r frame; do
            filename=$(echo "$frame" | jq -r '.filename')
            x=$(echo "$frame" | jq -r '.hotspot_x | round')
            y=$(echo "$frame" | jq -r '.hotspot_y | round')
            delay=$(echo "$frame" | jq -r '.delay // "0"')

            png_path="$TMP_DIR/${cursor_name}_${size}_${filename%.svg}.png"
            rsvg-convert -w "$size" -h "$size" "$dir/$filename" -o "$png_path"

            if [ "$delay" != "0" ]; then
                printf "%d %d %d %s %d\n" "$size" "$x" "$y" "$png_path" "$delay" >> "$cfg_file"
            else
                printf "%d %d %d %s\n" "$size" "$x" "$y" "$png_path" >> "$cfg_file"
            fi
        done
    done

    # 4. Windows用バイナリコンバータの実行 (xcursorgen の代替)
    if [ -f "$cfg_file" ]; then
        generate_windows_cursor "$cursor_name" "$cfg_file" "$OUT_DIR"
        rm "$cfg_file"
    fi
done

# 5. 出力ディレクトリにリンクを「実ファイルコピー」として反映
echo "=== Creating aliases in $OUT_DIR ==="
for item in "$BREEZE_DIR"/*; do
    [ -e "$item" ] || continue
    name=$(basename "$item")

    if [ -L "$item" ]; then
        target=$(readlink "$item")
        # .cur または .ani の実体ファイルが存在する場合に、別名で複製
        if [ -f "$OUT_DIR/$target.cur" ]; then
            cp "$OUT_DIR/$target.cur" "$OUT_DIR/$name.cur"
        elif [ -f "$OUT_DIR/$target.ani" ]; then
            cp "$OUT_DIR/$target.ani" "$OUT_DIR/$name.ani"
        fi
    fi
done

rm -rf "$TMP_DIR"
echo "Windows build complete. Check the '$OUT_DIR' directory!"
