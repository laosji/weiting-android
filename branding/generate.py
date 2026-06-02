"""
为「微听」生成品牌资源：
  - icon_source.png            1024x1024  launcher 主图（带圆角背景，iOS / 老版 Android 用）
  - icon_foreground.png        1024x1024  Android 8.0+ adaptive 前景（透明底，内容在中心 66% 安全区）
  - icon_background.png        1024x1024  Android 8.0+ adaptive 背景（纯渐变）
  - icon_monochrome.png        1024x1024  Android 13+ themed icon（白色单色前景）
  - splash_logo.png             768x768   启动屏中央 logo（透明底，渐变胶囊 + 白色"微"）
  - splash_logo_dark.png        768x768   暗色启动屏中央 logo（同上）

设计语言对齐 lib/main.dart 中 _Header 的视觉：
  - 主色渐变 #f6c4b5 → #d9574b
  - 白色"微"字 + 唱片同心圆暗示
"""

import os

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ACCENT_DARK = (217, 87, 75)      # #d9574b
ACCENT_LIGHT = (246, 196, 181)   # #f6c4b5
SURFACE = (251, 250, 247)        # #fbfaf7
WHITE = (255, 255, 255)
INK = (36, 37, 32)               # #242520

# macOS 上的中文字体（黑体 + Unicode 兜底）
FONT_CANDIDATES = [
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/Library/Fonts/Arial Unicode.ttf",
    "/System/Library/Fonts/PingFang.ttc",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def make_gradient(size: int, c1, c2) -> Image.Image:
    """对角线渐变：左上 c1 → 右下 c2。"""
    base = Image.new("RGB", (size, size), c1)
    top = Image.new("RGB", (size, size), c2)
    mask = Image.new("L", (size, size))
    px = mask.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = int(255 * ((x + y) / (2 * (size - 1))))
    base.paste(top, (0, 0), mask)
    return base.convert("RGBA")


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_disc(img: Image.Image, cx: int, cy: int, radius: int, ring_color, ring_alpha=50):
    """在 img 上叠几圈薄环，模拟唱片纹理。"""
    draw = ImageDraw.Draw(img, "RGBA")
    for i, r in enumerate([radius, int(radius * 0.84), int(radius * 0.66), int(radius * 0.48)]):
        a = ring_alpha if i % 2 == 0 else max(ring_alpha - 18, 16)
        draw.ellipse(
            (cx - r, cy - r, cx + r, cy + r),
            outline=(255, 255, 255, a),
            width=3,
        )


def draw_centered_text(img: Image.Image, text: str, font, fill, dy: int = 0):
    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), text, font=font)
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    x = (img.width - w) // 2 - bbox[0]
    y = (img.height - h) // 2 - bbox[1] + dy
    draw.text((x, y), text, font=font, fill=fill)


def build_launcher_icon(out_path: str, size: int = 1024):
    """带背景的完整 launcher 图标。"""
    bg = make_gradient(size, ACCENT_LIGHT, ACCENT_DARK)

    # 圆角裁切（iOS / 部分老版 Android）
    mask = rounded_mask(size, radius=int(size * 0.22))
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask)

    # 同心圆唱片暗示
    draw_disc(icon, size // 2, size // 2, int(size * 0.40), WHITE, ring_alpha=42)

    # 中心放白色"微"字
    font = load_font(int(size * 0.56))
    draw_centered_text(icon, "微", font, WHITE, dy=int(size * 0.01))

    # 一抹高光，质感
    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    sd.ellipse(
        (int(size * 0.08), int(size * 0.06), int(size * 0.72), int(size * 0.42)),
        fill=(255, 255, 255, 36),
    )
    shine = shine.filter(ImageFilter.GaussianBlur(radius=size * 0.04))
    icon = Image.alpha_composite(icon, shine)

    icon.save(out_path)
    print(f"  wrote {out_path}")


def build_adaptive_background(out_path: str, size: int = 1024):
    """Android 8.0+ 自适应图标背景层（满铺渐变，不带圆角）。"""
    bg = make_gradient(size, ACCENT_LIGHT, ACCENT_DARK)
    bg.save(out_path)
    print(f"  wrote {out_path}")


def build_adaptive_foreground(out_path: str, size: int = 1024):
    """Android 8.0+ 自适应前景：透明底，内容必须收在中心圆里。
    Android 启动器会对前景再裁切（圆 / 方 / 水滴等），content area 通常是中心 66%。
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 安全可视区半径 ≈ 32%（content area 66% → 半径 33%，再缩 1% 留余量）
    safe_radius = int(size * 0.32)
    cx, cy = size // 2, size // 2

    # 微弱白色同心圆（在安全区内）
    draw_disc(img, cx, cy, safe_radius, WHITE, ring_alpha=70)

    # 字大小限制在安全区内
    font = load_font(int(safe_radius * 1.55))
    draw_centered_text(img, "微", font, WHITE, dy=int(size * 0.01))

    img.save(out_path)
    print(f"  wrote {out_path}")


def build_monochrome(out_path: str, size: int = 1024):
    """Android 13+ themed icon：单色（白色 alpha）前景。系统会按主题着色。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx, cy = size // 2, size // 2
    safe_radius = int(size * 0.32)
    draw_disc(img, cx, cy, safe_radius, WHITE, ring_alpha=120)
    font = load_font(int(safe_radius * 1.55))
    draw_centered_text(img, "微", font, (255, 255, 255, 255), dy=int(size * 0.01))
    img.save(out_path)
    print(f"  wrote {out_path}")


def build_splash_logo(out_path: str, size: int = 768):
    """启动屏中央 logo：圆角渐变胶囊 + 白色"微"字 + 副标题。透明背景，外层 splash 颜色由 native_splash 控制。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    card_size = int(size * 0.78)
    card_radius = int(card_size * 0.22)
    card_x = (size - card_size) // 2
    card_y = (size - card_size) // 2

    # 渐变 + 圆角
    gradient = make_gradient(card_size, ACCENT_LIGHT, ACCENT_DARK)
    mask = rounded_mask(card_size, card_radius)
    card = Image.new("RGBA", (card_size, card_size), (0, 0, 0, 0))
    card.paste(gradient, (0, 0), mask)

    # 唱片纹
    draw_disc(card, card_size // 2, card_size // 2, int(card_size * 0.36), WHITE, ring_alpha=46)

    # "微"字
    font = load_font(int(card_size * 0.5))
    draw_centered_text(card, "微", font, WHITE, dy=int(card_size * 0.01))

    # 轻微阴影
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (card_x + 8, card_y + 24, card_x + card_size + 8, card_y + card_size + 24),
        radius=card_radius,
        fill=(40, 30, 24, 70),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=18))

    img = Image.alpha_composite(img, shadow)
    img.paste(card, (card_x, card_y), card)

    img.save(out_path)
    print(f"  wrote {out_path}")


if __name__ == "__main__":
    out = os.path.dirname(os.path.abspath(__file__))
    print("generating brand assets...")
    build_launcher_icon(f"{out}/icon_source.png")
    build_adaptive_background(f"{out}/icon_background.png")
    build_adaptive_foreground(f"{out}/icon_foreground.png")
    build_monochrome(f"{out}/icon_monochrome.png")
    build_splash_logo(f"{out}/splash_logo.png")
    # 暗色模式 logo 用同一张（渐变本身可读性 OK）
    build_splash_logo(f"{out}/splash_logo_dark.png")
    print("done.")
