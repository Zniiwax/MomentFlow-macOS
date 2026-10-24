#!/opt/anaconda3/bin/python3
"""Pre-render subtitle text onto each frame image using PIL."""
from PIL import Image, ImageDraw, ImageFont
import os

BUILD_DIR = "/Users/wzx/Documents/ChatGPT/my-ai-flow/MomentFlow-macOS/.video_build"
FONT_PATH = "/System/Library/Fonts/Hiragino Sans GB.ttc"
W, H = 1920, 1080

# subtitle text for each frame (frame 1-6)
subtitles = [
    "看剧遇到心动画面，一键录下来",
    "MomentFlow · macOS 菜单栏录屏小工具",
    "录制窗口画面 + 系统声音，存成 MP4",
    "不联网 · 不上传 · 开源安全",
    "喜欢的片段和音乐",
    "随手留住",
]

font = ImageFont.truetype(FONT_PATH, 40)

for i, sub in enumerate(subtitles, 1):
    img_path = os.path.join(BUILD_DIR, f"frame{i}.jpg")
    img = Image.open(img_path).convert("RGB")
    # resize to 1920x1080 cover
    img_ratio = img.width / img.height
    target_ratio = W / H
    if img_ratio > target_ratio:
        new_h = H
        new_w = int(H * img_ratio)
    else:
        new_w = W
        new_h = int(W / img_ratio)
    img = img.resize((new_w, new_h), Image.LANCZOS)
    left = (new_w - W) // 2
    top = (new_h - H) // 2
    img = img.crop((left, top, left + W, top + H))

    draw = ImageDraw.Draw(img)
    # measure text
    bbox = draw.textbbox((0, 0), sub, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (W - tw) // 2
    y = H - 100

    # semi-transparent background bar for readability
    bar_pad = 20
    draw.rectangle(
        [x - bar_pad, y - 8, x + tw + bar_pad, y + th + 12],
        fill=(0, 0, 0, 160),
    )
    # text with slight shadow
    draw.text((x + 2, y + 2), sub, fill=(0, 0, 0), font=font)
    draw.text((x, y), sub, fill=(255, 255, 255), font=font)

    out_path = os.path.join(BUILD_DIR, f"frame{i}_sub.jpg")
    img.save(out_path, quality=92)
    print(f"saved {out_path}")

print("done")
