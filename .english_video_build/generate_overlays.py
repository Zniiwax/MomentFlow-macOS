#!/usr/bin/env python3
"""Generate English-only overlay cards for the 15-second MomentFlow film."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "overlays"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 1920, 1080
FONT_PATH = "/System/Library/Fonts/SFNS.ttf"


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size)


def new_overlay() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def label(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    size: int,
    fill: tuple[int, int, int, int] = (246, 247, 251, 235),
    bold: bool = False,
) -> None:
    stroke = 1 if bold else 0
    draw.text(
        xy,
        text,
        font=font(size),
        fill=fill,
        stroke_width=stroke,
        stroke_fill=fill,
    )


def pill(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    text: str,
    size: int,
    *,
    fill: tuple[int, int, int, int] = (8, 10, 16, 255),
    color: tuple[int, int, int, int] = (248, 248, 251, 238),
    radius: int = 17,
    accent: bool = True,
) -> None:
    x1, y1, x2, y2 = box
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=(255, 255, 255, 31), width=1)
    text_x = x1 + (44 if accent else 22)
    if accent:
        cy = (y1 + y2) // 2
        draw.ellipse((x1 + 20, cy - 4, x1 + 28, cy + 4), fill=(255, 84, 100, 255))
    f = font(size)
    bbox = draw.textbbox((0, 0), text, font=f)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    label(draw, (text_x, (y1 + y2 - th) // 2 - bbox[1]), text, size, color)
    del tw


def caption(draw: ImageDraw.ImageDraw, text: str, width: int | None = None) -> None:
    f = font(27)
    bbox = draw.textbbox((0, 0), text, font=f)
    tw = bbox[2] - bbox[0]
    if width is None:
        width = min(880, max(350, tw + 94))
    x1 = (W - width) // 2
    pill(draw, (x1, 980, x1 + width, 1036), text, 27)


def save(image: Image.Image, name: str) -> None:
    image.save(OUT / name)


def scene1() -> None:
    image, draw = new_overlay()
    draw.rectangle((60, 0, 445, 56), fill=(18, 21, 31, 255))
    label(draw, (82, 15), "Finder", 21, (245, 246, 250, 235), True)
    label(draw, (178, 15), "File", 20, (255, 255, 255, 135))
    label(draw, (235, 15), "Edit", 20, (255, 255, 255, 135))
    label(draw, (295, 15), "View", 20, (255, 255, 255, 135))

    draw.rectangle((350, 104, 700, 141), fill=(23, 25, 35, 255))
    label(draw, (407, 112), "The Last Train · Episode 6", 16, (255, 255, 255, 125))
    draw.rectangle((1568, 106, 1625, 140), fill=(23, 25, 35, 255))
    label(draw, (1575, 111), "Full Screen", 13, (255, 255, 255, 100))

    draw.rectangle((384, 209, 505, 267), fill=(13, 16, 25, 255))
    label(draw, (387, 226), "Golden Moment", 27, (255, 255, 255, 235), True)

    draw.rectangle((1186, 724, 1390, 761), fill=(12, 14, 22, 255))
    label(draw, (1190, 733), "QUICK RECORD", 17, (255, 255, 255, 160), True)
    draw.rectangle((1444, 771, 1604, 810), fill=(12, 14, 22, 255))

    draw.rectangle((286, 833, 540, 873), fill=(13, 20, 28, 255))
    label(draw, (307, 839), "THE LAST TRAIN", 19, (255, 255, 255, 230), True)
    save(image, "scene1_base.png")

    ready, ready_draw = new_overlay()
    label(ready_draw, (1452, 780), "READY TO REC", 15, (255, 255, 255, 105), True)
    save(ready, "scene1_ready.png")

    recording, recording_draw = new_overlay()
    label(recording_draw, (1452, 780), "REC 00:01", 15, (255, 108, 120, 225), True)
    save(recording, "scene1_rec.png")

    cap, cap_draw = new_overlay()
    caption(cap_draw, "A PERFECT MOMENT · ONE KEYPRESS")
    save(cap, "scene1_caption.png")


def scene2() -> None:
    image, draw = new_overlay()
    draw.rectangle((380, 230, 650, 284), fill=(18, 21, 31, 255))
    label(draw, (405, 244), "Finder", 20, (245, 246, 250, 232), True)
    label(draw, (487, 244), "File", 19, (255, 255, 255, 135))
    label(draw, (535, 244), "Edit", 19, (255, 255, 255, 135))
    label(draw, (585, 244), "View", 19, (255, 255, 255, 135))
    draw.rounded_rectangle((615, 675, 1305, 738), radius=20, fill=(8, 10, 17, 255))
    label(
        draw,
        (655, 691),
        "Lives in your menu bar · No recorder window",
        27,
        (246, 247, 251, 160),
    )
    save(image, "scene2_base.png")

    cap, cap_draw = new_overlay()
    caption(cap_draw, "MOMENTFLOW · MENU BAR RECORDER")
    save(cap, "scene2_caption.png")


def scene3() -> None:
    image, draw = new_overlay()
    draw.rectangle((170, 112, 450, 157), fill=(8, 11, 19, 255))
    label(draw, (205, 121), "THREE ACTIONS", 18, (247, 248, 252, 150), True)
    draw.rectangle((168, 154, 820, 250), fill=(8, 11, 19, 255))
    label(draw, (180, 166), "READY WHEN YOU ARE.", 59, (248, 249, 253, 245), True)

    cards = [
        (186, 518, 470, 664, (35, 38, 68, 255)),
        (709, 518, 993, 664, (28, 32, 47, 255)),
        (1242, 518, 1526, 664, (27, 31, 45, 255)),
    ]
    for box in cards:
        draw.rounded_rectangle(box[:4], radius=8, fill=box[4])

    label(draw, (198, 548), "Quick Record", 38, (246, 247, 251, 242), True)
    label(draw, (198, 606), "Current window · One key", 19, (255, 255, 255, 105))
    label(draw, (721, 548), "Capture", 38, (246, 247, 251, 242), True)
    label(draw, (721, 606), "Screen / Window / Region", 19, (255, 255, 255, 105))
    label(draw, (1254, 548), "Mark Moment", 38, (246, 247, 251, 242), True)
    label(draw, (1254, 606), "Screenshot + quick note", 19, (255, 255, 255, 105))

    draw.rounded_rectangle((680, 770, 1240, 816), radius=15, fill=(8, 11, 19, 255))
    label(draw, (716, 780), "Custom shortcuts · Changes apply instantly", 22, (255, 255, 255, 100))
    save(image, "scene3_base.png")

    cap, cap_draw = new_overlay()
    caption(cap_draw, "SHORTCUTS READY. ONE PRESS AWAY.", 720)
    save(cap, "scene3_caption.png")


def scene4() -> None:
    image, draw = new_overlay()
    draw.rectangle((136, 86, 650, 128), fill=(8, 11, 18, 255))
    label(draw, (142, 95), "WINDOW-ONLY · PICTURE + AUDIO", 18, (247, 248, 252, 145), True)
    draw.rectangle((136, 130, 750, 226), fill=(8, 11, 18, 255))
    label(draw, (142, 143), "PICTURE + AUDIO.", 58, (248, 249, 252, 245), True)

    draw.rounded_rectangle((152, 254, 336, 315), radius=19, fill=(8, 11, 17, 255))
    label(draw, (177, 272), "CURRENT WINDOW", 16, (247, 248, 251, 225), True)
    draw.rectangle((130, 828, 550, 884), fill=(11, 18, 24, 255))
    label(draw, (153, 839), "THE LAST TRAIN", 19, (255, 255, 255, 228), True)

    draw.rectangle((1394, 304, 1610, 373), fill=(35, 39, 64, 255))
    label(draw, (1402, 316), "SYSTEM AUDIO", 18, (248, 249, 252, 170), True)

    draw.rounded_rectangle((1366, 548, 1774, 722), radius=28, fill=(42, 46, 79, 255))
    label(draw, (1396, 580), "ONE FILE. EDIT-READY.", 17, (255, 255, 255, 115), True)
    draw.rounded_rectangle((1396, 619, 1449, 672), radius=15, fill=(255, 91, 103, 245))
    label(draw, (1406, 633), "MP4", 18, (255, 255, 255, 245), True)
    label(draw, (1470, 631), "Golden Moment.mp4", 24, (248, 249, 252, 242), True)
    label(draw, (1470, 675), "Picture + system audio", 16, (255, 255, 255, 118))
    save(image, "scene4_base.png")

    cap, cap_draw = new_overlay()
    caption(cap_draw, "WINDOW VIDEO + SYSTEM AUDIO · ONE MP4", 850)
    save(cap, "scene4_caption.png")


def scene5() -> None:
    image, draw = new_overlay()
    draw.rectangle((672, 148, 1250, 242), fill=(8, 12, 18, 255))
    label(draw, (720, 166), "ONLY ON YOUR MAC", 58, (247, 249, 248, 245), True)

    cards = [
        (497, "No network", "Zero requests"),
        (812, "No uploads", "Saved locally"),
        (1128, "Open source", "Reviewable code"),
    ]
    for x, title, sub in cards:
        draw.rounded_rectangle(
            (x, 695, x + 295, 795),
            radius=21,
            fill=(27, 42, 50, 255),
            outline=(181, 242, 224, 28),
            width=1,
        )
        draw.rounded_rectangle((x + 25, 728, x + 61, 764), radius=10, fill=(117, 199, 175, 24))
        label(draw, (x + 35, 731), "✓", 19, (172, 229, 210, 235))
        label(draw, (x + 76, 718), title, 24, (237, 248, 244, 245), True)
        label(draw, (x + 76, 753), sub, 15, (226, 244, 238, 105))
    save(image, "scene5_base.png")

    cap, cap_draw = new_overlay()
    caption(cap_draw, "NO NETWORK · NO UPLOADS · OPEN SOURCE", 750)
    save(cap, "scene5_caption.png")


def scene6() -> None:
    image, draw = new_overlay()
    draw.rectangle((655, 116, 1285, 207), fill=(8, 11, 18, 255))
    label(draw, (696, 134), "SAVED TO DISK.", 51, (248, 249, 252, 245), True)

    # Rebuild the Finder sidebar in English while keeping the main window intact.
    draw.rectangle((270, 280, 518, 865), fill=(20, 23, 32, 255))
    label(draw, (296, 287), "FAVORITES", 13, (255, 255, 255, 82), True)
    sidebar = [
        ("Desktop", 327, (111, 145, 202, 255), False),
        ("MomentFlow", 386, (255, 96, 110, 255), True),
        ("Recents", 445, (111, 145, 202, 255), False),
        ("Movies", 504, (111, 145, 202, 255), False),
    ]
    for text, y, color, active in sidebar:
        if active:
            draw.rounded_rectangle((287, y - 9, 493, y + 36), radius=9, fill=(65, 72, 133, 235))
        draw.rounded_rectangle((307, y, 327, y + 18), radius=4, fill=color)
        label(draw, (341, y - 2), text, 17, (245, 246, 250, 225 if active else 115), active)
    label(draw, (296, 563), "LOCAL", 13, (255, 255, 255, 82), True)
    draw.rounded_rectangle((307, 604, 327, 622), radius=4, fill=(113, 125, 150, 255))
    label(draw, (341, 602), "Downloads", 17, (245, 246, 250, 115))

    draw.rectangle((1528, 352, 1608, 396), fill=(27, 30, 41, 255))
    label(draw, (1544, 363), "4 items", 13, (255, 255, 255, 120))

    draw.rounded_rectangle((561, 428, 675, 462), radius=7, fill=(20, 22, 31, 255))
    draw.ellipse((574, 440, 583, 449), fill=(255, 85, 101, 255))
    label(draw, (592, 435), "JUST SAVED", 11, (255, 131, 139, 235), True)

    files = [
        (557, "Golden Moment.mp4", "42 sec · 128 MB", (38, 27, 35, 255)),
        (920, "Sunset by the Sea.mp4", "18 sec · 61 MB", (34, 36, 47, 255)),
        (1281, "Live in Concert.mp4", "1m 12s · 194 MB", (34, 36, 47, 255)),
    ]
    for x, title, meta, bg in files:
        draw.rectangle((x, 592, x + 281, 651), fill=bg)
        label(draw, (x + 1, 602), title, 16, (240, 241, 246, 235))
        label(draw, (x + 1, 628), meta, 13, (255, 113, 126, 200) if x == 562 else (255, 255, 255, 100))

    draw.rounded_rectangle((1274, 837, 1696, 953), radius=22, fill=(27, 30, 44, 255))
    draw.ellipse((1300, 862, 1350, 912), fill=(255, 92, 107, 38))
    draw.ellipse((1316, 878, 1334, 896), fill=(255, 80, 96, 255))
    label(draw, (1360, 856), "Saved", 21, (243, 244, 248, 245), True)
    label(draw, (1360, 894), "~/Desktop/MomentFlow/Golden Moment.mp4", 13, (255, 255, 255, 110))
    save(image, "scene6_base.png")

    cap, cap_draw = new_overlay()
    caption(cap_draw, "SAVED STRAIGHT TO YOUR LOCAL FOLDER", 760)
    save(cap, "scene6_caption.png")


def scene7() -> None:
    image, draw = new_overlay()
    draw.rounded_rectangle((545, 730, 1378, 782), radius=20, fill=(8, 11, 18, 255))
    label(
        draw,
        (583, 742),
        "Picture + system audio · One clean file",
        23,
        (247, 248, 252, 125),
    )
    save(image, "scene7_base.png")

    cap, cap_draw = new_overlay()
    caption(cap_draw, "FAVORITE MOMENTS AND MUSIC", 570)
    save(cap, "scene7_caption.png")


def scene8() -> None:
    image, draw = new_overlay()
    draw.rectangle((485, 552, 1438, 644), fill=(9, 10, 17, 255))
    label(draw, (565, 566), "KEEP THE MOMENTS YOU LOVE.", 53, (249, 248, 250, 242), True)

    chips = [
        (741, 864, "WINDOW ONLY"),
        (878, 1042, "SYSTEM AUDIO"),
        (1056, 1197, "LOCAL SAVE"),
    ]
    for x1, x2, text in chips:
        draw.rounded_rectangle((x1, 677, x2, 724), radius=20, fill=(11, 13, 20, 255))
        label(draw, (x1 + 17, 690), "●", 11, (255, 92, 106, 230))
        label(draw, (x1 + 38, 691), text, 14, (247, 248, 252, 145), True)
    save(image, "scene8_base.png")

    cap, cap_draw = new_overlay()
    caption(cap_draw, "KEEP THE MOMENT", 390)
    save(cap, "scene8_caption.png")


def main() -> None:
    scene1()
    scene2()
    scene3()
    scene4()
    scene5()
    scene6()
    scene7()
    scene8()
    print(f"Generated English overlays in {OUT}")


if __name__ == "__main__":
    main()
