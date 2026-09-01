import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
INTO = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "icon"))

GROUND = (14, 17, 22, 255)
BODY = (30, 37, 47, 255)
EDGE = (58, 70, 86, 255)
PIN = (224, 168, 106, 255)
PIN_DIM = (150, 112, 70, 255)
WAVE = (86, 200, 240, 255)

PARTS = [
    (0xFF, 0x52, 0x52), (0xFF, 0x90, 0x29), (0xFF, 0xD0, 0x29), (0xB4, 0xE1, 0x2E),
    (0x3F, 0xD9, 0x8A), (0x2B, 0xC4, 0xB4), (0x38, 0xA8, 0xF0), (0x6C, 0x74, 0xF0),
    (0xA6, 0x5C, 0xF0), (0x9E, 0x9E, 0x9E), (0xF0, 0x50, 0xA0),
]

OVER = 8


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def square_wave(draw, left, top, right, bottom, thick, colour, cycles):
    width = right - left
    step = width / (cycles * 2.0)
    high = top
    low = bottom
    up = True
    x = left

    draw.line([(x, low), (x, high)], fill=colour, width=thick)

    for i in range(cycles * 2):
        y = high if up else low
        draw.line([(x, y), (x + step, y)], fill=colour, width=thick)
        x += step
        if i < cycles * 2 - 1:
            draw.line([(x, high), (x, low)], fill=colour, width=thick)
        up = not up

    draw.line([(x, high), (x, low)], fill=colour, width=thick)


def draw_icon(size, plain):
    side = size * OVER
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    unit = side / 100.0

    rounded(draw, (0, 0, side - 1, side - 1), int(22 * unit), GROUND)

    body = (int(21 * unit), int(25 * unit), int(79 * unit), int(75 * unit))
    pins = 5 if not plain else 0

    if pins:
        gap = (body[3] - body[1]) / float(pins)
        thick = int(gap * 0.42)
        run = int(12 * unit)

        for i in range(pins):
            top = int(body[1] + gap * i + gap * 0.29)
            left = PARTS[i % len(PARTS)] + (255,)
            right = PARTS[(i + 5) % len(PARTS)] + (255,)

            draw.rounded_rectangle(
                (body[0] - run, top, body[0] + int(2 * unit), top + thick),
                radius=int(thick * 0.4), fill=left)
            draw.rounded_rectangle(
                (body[2] - int(2 * unit), top, body[2] + run, top + thick),
                radius=int(thick * 0.4), fill=right)

    rounded(draw, body, int(6 * unit), EDGE)
    rounded(draw, (body[0] + int(unit), body[1] + int(unit),
                   body[2] - int(unit), body[3] - int(unit)), int(5 * unit), BODY)

    notch = int(4.5 * unit)
    middle = (body[0] + body[2]) // 2
    draw.pieslice((middle - notch, body[1] - notch, middle + notch, body[1] + notch),
                  start=0, end=180, fill=GROUND)

    thick = max(1, int((4.6 if plain else 3.6) * unit))
    inset = int((8 if plain else 10) * unit)

    high = body[1] + int((13 if plain else 14) * unit)
    low = body[3] - int((13 if plain else 14) * unit)

    square_wave(draw, body[0] + inset, high, body[2] - inset, low, thick, WAVE, 2)

    return image.resize((size, size), Image.LANCZOS)


def main():
    if not os.path.isdir(INTO):
        os.makedirs(INTO)

    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256, 512]
    made = []

    for size in sizes:
        image = draw_icon(size, size <= 24)
        path = os.path.join(INTO, "mdd-" + str(size) + ".png")
        image.save(path)
        made.append(image)
        print("  " + str(size).rjust(4) + "  " + os.path.basename(path))

    raw = draw_icon(64, False).convert("RGBA")
    with open(os.path.join(INTO, "mdd-64.rgba"), "wb") as into:
        into.write(raw.tobytes())
    print("        mdd-64.rgba")

    made[-2].save(os.path.join(INTO, "mdd.ico"),
                  sizes=[(s, s) for s in sizes if s <= 256],
                  append_images=[i for i in made if i.size[0] <= 256])
    print("        mdd.ico")

    sheet = Image.new("RGBA", (16 + 20 + 24 + 32 + 48 + 64 + 128 + 256 + 8 * 8, 264),
                      (40, 40, 46, 255))
    x = 8
    for image in made:
        if image.size[0] > 256:
            continue
        sheet.paste(image, (x, 264 - 8 - image.size[0]), image)
        x += image.size[0] + 8
    sheet.save(os.path.join(INTO, "sheet.png"))


main()
