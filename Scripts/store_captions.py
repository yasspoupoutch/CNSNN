#!/usr/bin/env python3
"""Turns the raw App Store screenshots into captioned ones: a short sentence in the app's fonts on
top, vowels in gold as in the wordmark, and the screenshot below in a rounded frame. Same size as the
input (1320 x 2868 for the iPhone 6.9" slot).

Usage: store_captions.py LISTING_JSON SOURCE_DIR TARGET_DIR
Captions are "captions" in LISTING_JSON, keyed by screenshot name; a name without one is copied as is.
"""
import json, pathlib, shutil, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

listing_path, source, target = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
listing = json.load(open(listing_path, encoding='utf-8'))
captions = listing.get('captions', {})
fonts = pathlib.Path(__file__).resolve().parent.parent / 'App/Resources/Fonts'
target.mkdir(parents=True, exist_ok=True)

# Same palette as App/DesignSystem/Theme.swift and the site.
BG_TOP, BG = (18, 20, 38), (6, 7, 12)
FG, GOLD = (244, 245, 248), (255, 198, 90)
VOWELS = set('AEIOUYÀÂÄÉÈÊËÎÏÔÖÙÛÜŸaeiouyàâäéèêëîïôöùûüÿ')


def background(w, h):
    img = Image.new('RGB', (w, h), BG)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = min(1, y / (h * 0.6))
        draw.line([(0, y), (w, y)], fill=tuple(int(a * (1 - t) + b * t) for a, b in zip(BG_TOP, BG)))
    # The two soft glows of the app's ambient background.
    glow = Image.new('RGB', (w, h), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.ellipse([-w * 0.4, -h * 0.15, w * 0.7, h * 0.3], fill=(70, 48, 160))
    g.ellipse([w * 0.5, h * 0.35, w * 1.5, h * 0.8], fill=(0, 90, 98))
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.18))
    return Image.blend(img, Image.composite(glow, img, Image.new('L', (w, h), 255)), 0.45)


def wrap(text, font, width, draw):
    lines, line = [], ''
    for word in text.split():
        trial = f'{line} {word}'.strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line); line = word
    return lines + [line]


def draw_line(draw, x, y, text, font, gold_vowels):
    for ch in text:
        draw.text((x, y), ch, font=font, fill=GOLD if gold_vowels and ch in VOWELS else FG)
        x += draw.textlength(ch, font=font)


for shot in sorted(source.glob('*.png')):
    caption = captions.get(shot.stem)
    if not caption:
        shutil.copyfile(shot, target / shot.name); continue
    raw = Image.open(shot).convert('RGB')
    w, h = raw.size
    img = background(w, h)
    draw = ImageDraw.Draw(img)
    title = ImageFont.truetype(str(fonts / 'Fraunces-Black.ttf'), int(w * 0.088))
    lines = wrap(caption['title'], title, w * 0.84, draw)
    y = int(h * 0.055)
    for line in lines:
        x = (w - draw.textlength(line, font=title)) / 2
        draw_line(draw, x, y, line, title, caption.get('goldVowels', False))
        y += int(title.size * 1.12)
    if caption.get('subtitle'):
        sub = ImageFont.truetype(str(fonts / 'InstrumentSerif-Italic.ttf'), int(w * 0.058))
        y += int(h * 0.006)
        for line in wrap(caption['subtitle'], sub, w * 0.84, draw):
            draw.text(((w - draw.textlength(line, font=sub)) / 2, y), line, font=sub, fill=(200, 202, 210))
            y += int(sub.size * 1.15)
    # The screenshot, scaled to the room left, in rounded corners with a thin light edge.
    top = y + int(h * 0.03)
    scale = (h - top) / h * 1.0
    sw, sh = int(w * 0.86 * min(1, scale / 0.86)), 0
    sh = int(sw * h / w)
    phone = raw.resize((sw, sh), Image.LANCZOS)
    radius = int(sw * 0.09)
    mask = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw, sh], radius=radius, fill=255)
    x = (w - sw) // 2
    edge = ImageDraw.Draw(img)
    edge.rounded_rectangle([x - 4, top - 4, x + sw + 4, top + sh + 4], radius=radius + 4, fill=(60, 62, 80))
    img.paste(phone, (x, top), mask)
    img.save(target / shot.name, optimize=True)
    print(f'Légende ajoutée : {shot.name} ({caption["title"]})')
