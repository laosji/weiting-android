"""
生成 Google Play 商店图形素材：
  - play_store_icon_512.png    512x512  高分辨率图标（不透明，32位 PNG）
  - feature_graphic_1024x500.png  1024x500  特色图片（不透明）

复用 generate.py 中的视觉语言：暖红渐变 + 白色"微" + 唱片同心圆。
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ACCENT_DARK = (217, 87, 75)      # #d9574b
ACCENT_LIGHT = (246, 196, 181)   # #f6c4b5
SURFACE = (251, 250, 247)        # #fbfaf7
WHITE = (255, 255, 255)
INK = (36, 37, 32)               # #242520

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


def make_gradient(w: int, h: int, c1, c2, diagonal=True) -> Image.Image:
    base = Image.new("RGB", (w, h), c1)
    top = Image.new("RGB", (w, h), c2)
    mask = Image.new("L", (w, h))
    px = mask.load()
    for y in range(h):
        for x in range(w):
            if diagonal:
                t = (x / max(w - 1, 1) + y / max(h - 1, 1)) / 2
            else:
                t = x / max(w - 1, 1)
            px[x, y] = int(255 * t)
    base.paste(top, (0, 0), mask)
    return base.convert("RGBA")


def draw_disc_rings(img, cx, cy, radius, alpha=46):
    draw = ImageDraw.Draw(img, "RGBA")
    for i, r in enumerate([radius, int(radius * 0.84), int(radius * 0.66), int(radius * 0.48)]):
        a = alpha if i % 2 == 0 else max(alpha - 18, 16)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r),
                     outline=(255, 255, 255, a), width=max(2, radius // 80))


def centered_text(img, text, font, fill, cx=None, cy=None, dy=0):
    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), text, font=font)
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    cx = img.width // 2 if cx is None else cx
    cy = img.height // 2 if cy is None else cy
    x = cx - w // 2 - bbox[0]
    y = cy - h // 2 - bbox[1] + dy
    draw.text((x, y), text, font=font, fill=fill)


def build_play_icon(out_path, size=512):
    """Play 高分辨率图标：满铺不透明渐变（Play 会自己加圆角和阴影）。"""
    icon = make_gradient(size, size, ACCENT_LIGHT, ACCENT_DARK).convert("RGB")
    icon = icon.convert("RGBA")

    draw_disc_rings(icon, size // 2, size // 2, int(size * 0.40), alpha=44)

    font = load_font(int(size * 0.56))
    centered_text(icon, "微", font, WHITE, dy=int(size * 0.01))

    # 左上高光
    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    sd.ellipse((int(size * 0.06), int(size * 0.04), int(size * 0.72), int(size * 0.42)),
               fill=(255, 255, 255, 34))
    shine = shine.filter(ImageFilter.GaussianBlur(radius=size * 0.04))
    icon = Image.alpha_composite(icon, shine)

    # Play 要求不透明 → 拍平到 RGB
    icon.convert("RGB").save(out_path)
    print(f"  wrote {out_path}")


def build_feature_graphic(out_path, w=1024, h=500):
    """Feature Graphic 1024x500：左侧 logo 圆角卡 + 右侧标题文案。"""
    bg = make_gradient(w, h, (250, 240, 236), SURFACE, diagonal=True).convert("RGBA")

    # 右侧大面积浅色，左侧放一个渐变圆角 logo 卡
    card = int(h * 0.62)
    card_x = int(w * 0.08)
    card_y = (h - card) // 2
    grad = make_gradient(card, card, ACCENT_LIGHT, ACCENT_DARK)
    mask = Image.new("L", (card, card), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, card - 1, card - 1),
                                           radius=int(card * 0.24), fill=255)
    logo = Image.new("RGBA", (card, card), (0, 0, 0, 0))
    logo.paste(grad, (0, 0), mask)
    draw_disc_rings(logo, card // 2, card // 2, int(card * 0.36), alpha=46)
    centered_text(logo, "微", load_font(int(card * 0.5)), WHITE, dy=int(card * 0.01))

    # 卡片阴影
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (card_x + 6, card_y + 14, card_x + card + 6, card_y + card + 14),
        radius=int(card * 0.24), fill=(40, 30, 24, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=16))
    bg = Image.alpha_composite(bg, shadow)
    bg.paste(logo, (card_x, card_y), logo)

    # 右侧文案
    draw = ImageDraw.Draw(bg)
    text_x = card_x + card + int(w * 0.05)
    title_font = load_font(int(h * 0.20))
    sub_font = load_font(int(h * 0.075))
    draw.text((text_x, int(h * 0.30)), "微听", font=title_font, fill=INK)
    draw.text((text_x, int(h * 0.58)), "把想听的视频，收进自己的列表",
              font=sub_font, fill=(94, 91, 84, 255))
    draw.text((text_x, int(h * 0.70)), "听书 · 听歌 · 后台播放",
              font=sub_font, fill=(170, 164, 154, 255))

    bg.convert("RGB").save(out_path)
    print(f"  wrote {out_path}")


if __name__ == "__main__":
    import os
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "play")
    os.makedirs(out, exist_ok=True)
    print("generating Play store graphics...")
    build_play_icon(f"{out}/play_store_icon_512.png")
    build_feature_graphic(f"{out}/feature_graphic_1024x500.png")
    print("done.")
