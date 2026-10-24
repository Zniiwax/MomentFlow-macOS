#!/bin/bash
set -e
cd /Users/wzx/Documents/ChatGPT/my-ai-flow/MomentFlow-macOS/.video_build

FF=/opt/homebrew/bin/ffmpeg
FONT="/System/Library/Fonts/Hiragino Sans GB.ttc"
W=1920
H=1080
DUR=3.4
XF=0.6

# offsets for xfade
# img1: 0-3.4
# img2 crossfade at 2.8
# img3 crossfade at 5.6
# img4 crossfade at 8.4
# img5 crossfade at 11.2
# img6 crossfade at 14.0
# total: 17.4

$FF -y \
  -loop 1 -t $DUR -i frame1.jpg \
  -loop 1 -t $DUR -i frame2.jpg \
  -loop 1 -t $DUR -i frame3.jpg \
  -loop 1 -t $DUR -i frame4.jpg \
  -loop 1 -t $DUR -i frame5.jpg \
  -loop 1 -t $DUR -i frame6.jpg \
  -i voiceover.wav \
  -filter_complex "
    [0:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1,fps=30[v0];
    [1:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1,fps=30[v1];
    [2:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1,fps=30[v2];
    [3:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1,fps=30[v3];
    [4:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1,fps=30[v4];
    [5:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1,fps=30[v5];
    [v0][v1]xfade=transition=fade:duration=$XF:offset=2.8[x1];
    [x1][v2]xfade=transition=fade:duration=$XF:offset=5.6[x2];
    [x2][v3]xfade=transition=fade:duration=$XF:offset=8.4[x3];
    [x3][v4]xfade=transition=fade:duration=$XF:offset=11.2[x4];
    [x4][v5]xfade=transition=fade:duration=$XF:offset=14.0[x5];
    [x5]drawtext=fontfile='$FONT':text='看剧遇到心动画面，一键录下来':fontcolor=white:fontsize=38:borderw=2:bordercolor=black@0.6:x=(w-text_w)/2:y=h-90:enable='between(t,0.3,3.2)',
    drawtext=fontfile='$FONT':text='MomentFlow  macOS 菜单栏录屏小工具':fontcolor=white:fontsize=38:borderw=2:bordercolor=black@0.6:x=(w-text_w)/2:y=h-90:enable='between(t,3.2,6.2)',
    drawtext=fontfile='$FONT':text='录制窗口画面加系统声音，存成 MP4':fontcolor=white:fontsize=38:borderw=2:bordercolor=black@0.6:x=(w-text_w)/2:y=h-90:enable='between(t,6.2,9.2)',
    drawtext=fontfile='$FONT':text='不联网  不上传  开源安全':fontcolor=white:fontsize=38:borderw=2:bordercolor=black@0.6:x=(w-text_w)/2:y=h-90:enable='between(t,9.2,12.2)',
    drawtext=fontfile='$FONT':text='喜欢的片段和音乐，随手留住':fontcolor=white:fontsize=42:borderw=2:bordercolor=black@0.6:x=(w-text_w)/2:y=h-90:enable='between(t,12.2,17.0)'[vout]
  " \
  -map "[vout]" -map 6:a \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
  -c:a aac -b:a 128k \
  -shortest \
  -movflags +faststart \
  MomentFlow_Intro.mp4

echo "Done: MomentFlow_Intro.mp4"
ls -lh MomentFlow_Intro.mp4
