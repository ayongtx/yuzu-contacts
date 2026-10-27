"""
生成 App 图标（1024x1024 PNG，无透明通道）。
不依赖 Pillow —— 直接用 zlib + struct 手写 PNG 编码。
画法：对角渐变底 + 白色人形（圆头 + 圆肩），边缘用有符号距离场做抗锯齿。
"""

import math
import struct
import zlib
import os

W = H = 1024

# 品牌渐变：左上亮蓝 → 右下深蓝
C1 = (58, 122, 255)
C2 = (8, 58, 184)


def sdf_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sdf_round_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    ax = qx if qx > 0 else 0.0
    ay = qy if qy > 0 else 0.0
    return math.hypot(ax, ay) + min(max(qx, qy), 0.0) - r


def figure_sdf(x, y):
    """人形 = 头（圆）+ 肩（圆角矩形），取两者最小值"""
    head = sdf_circle(x, y, 512.0, 372.0, 132.0)
    body = sdf_round_rect(x, y, 512.0, 782.0, 216.0, 172.0, 172.0)
    return head if head < body else body


def build_rows():
    rows = []
    for y in range(H):
        row = bytearray()
        row.append(0)  # PNG filter type: None

        # 该行的渐变混合系数（对角方向）
        for x in range(W):
            t = (x + y) / (W + H - 2)
            if t < 0:
                t = 0.0
            elif t > 1:
                t = 1.0
            br = int(C1[0] + (C2[0] - C1[0]) * t)
            bg = int(C1[1] + (C2[1] - C1[1]) * t)
            bb = int(C1[2] + (C2[2] - C1[2]) * t)

            # 只在人形包围盒内才算距离场，其余直接铺底色
            if 246 <= x <= 778 and 232 <= y <= 962:
                d = figure_sdf(x, y)
                cov = 0.5 - d
                if cov > 1.0:
                    cov = 1.0
                elif cov < 0.0:
                    cov = 0.0

                if cov > 0:
                    r = int(br + (255 - br) * cov)
                    g = int(bg + (255 - bg) * cov)
                    b = int(bb + (255 - bb) * cov)
                else:
                    r, g, b = br, bg, bb
            else:
                r, g, b = br, bg, bb

            row.append(r)
            row.append(g)
            row.append(b)
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    raw = b"".join(rows)
    compressed = zlib.compress(raw, 9)

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return out + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)  # 8bit truecolor RGB

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", compressed))
        f.write(chunk(b"IEND", b""))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "ContactsPro", "Assets.xcassets",
                       "AppIcon.appiconset", "icon-1024.png")
    out = os.path.normpath(out)

    print("渲染中，1024x1024 …")
    rows = build_rows()
    write_png(out, rows)
    print("已生成:", out, os.path.getsize(out), "bytes")
