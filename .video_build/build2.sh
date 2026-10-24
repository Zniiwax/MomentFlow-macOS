#!/bin/bash
set -e
cd /Users/wzx/Documents/ChatGPT/my-ai-flow/MomentFlow-macOS/.video_build

FF=/opt/homebrew/bin/ffmpeg
DUR=3.4
XF=0.6

$FF -y \
  -loop 1 -t $DUR -i frame1_sub.jpg \
  -loop 1 -t $DUR -i frame2_sub.jpg \
  -loop 1 -t $DUR -i frame3_sub.jpg \
  -loop 1 -t $DUR -i frame4_sub.jpg \
  -loop 1 -t $DUR -i frame5_sub.jpg \
  -loop 1 -t $DUR -i frame6_sub.jpg \
  -i voiceover.wav \
  -filter_complex "
    [0:v]fps=30,settb=AVTB[v0];
    [1:v]fps=30,settb=AVTB[v1];
    [2:v]fps=30,settb=AVTB[v2];
    [3:v]fps=30,settb=AVTB[v3];
    [4:v]fps=30,settb=AVTB[v4];
    [5:v]fps=30,settb=AVTB[v5];
    [v0][v1]xfade=transition=fade:duration=$XF:offset=2.8[x1];
    [x1][v2]xfade=transition=fade:duration=$XF:offset=5.6[x2];
    [x2][v3]xfade=transition=fade:duration=$XF:offset=8.4[x3];
    [x3][v4]xfade=transition=fade:duration=$XF:offset=11.2[x4];
    [x4][v5]xfade=transition=fade:duration=$XF:offset=14.0[vout]
  " \
  -map "[vout]" -map 6:a \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
  -c:a aac -b:a 128k \
  -shortest \
  -movflags +faststart \
  MomentFlow_Intro.mp4

echo "=== Done ==="
ls -lh MomentFlow_Intro.mp4
$FF -i MomentFlow_Intro.mp4 2>&1 | grep -E "Duration|Stream"
