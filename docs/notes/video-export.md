# Video export

A scope video is a WebM file holding VP9 video and Opus audio, written by
`src/mdd/native/video.cpp` through libvpx and libwebm.

## The VP9 encoder

libvpx is compiled from `vendor/libvpx` as portable C, with only the VP9 encoder, realtime only.
The files its configure script writes are kept in `src/mdd/native/vpx`, generated from v1.17.0:

    configure --target=generic-gnu --disable-vp8 --enable-vp9 --disable-vp9-decoder
      --enable-realtime-only --disable-examples --disable-tools --disable-docs
      --disable-unit-tests --disable-install-bins --disable-install-libs
      --disable-webm-io --disable-libyuv
    make libvpx_srcs.txt vpx_version.h vp9_rtcd.h vpx_dsp_rtcd.h vpx_scale_rtcd.h

That configuration builds 85 C files plus `vpx_config.c`. The trees in `mdd.xml` leave out of
each folder exactly what `libvpx_srcs.txt` leaves out, and a tree does not walk into subfolders,
which is where the processor specific code sits. No assembler is asked for, so none of it is built.

Four values in `vpx_config.h` depend on the platform rather than on the generic configuration.
Under MSVC, `INLINE` is `__inline` and `CONFIG_MSVS` is set in place of `CONFIG_GCC`. On Windows
there is no `pthread.h` and no `unistd.h`, and `HAVE_PTHREAD_H` being nought is what makes
`vpx_util/vpx_pthread.h` use Windows threads. `HAVE_PTHREAD_SETNAME_NP` is tested with `ifdef`,
so on Windows it is left undefined rather than set to nought.

A new libvpx version regenerates these files with the commands above, run against the new source.

## What a file carries

Frames are converted with BT.709 weights at studio range, to I444 in VP9 profile 1 where the
colour is kept at full resolution and to I420 in profile 0 where it is halved, and the bitstream
says so through its colour space and range, because a decoder left to guess picks BT.601 below
720 lines and every colour shifts.

Opus goes into WebM as raw packets of twenty milliseconds rather than in ogg pages. The
identification header is the audio track's codec private data, and the encoder's lookahead is
written both as the header's pre-skip and as the track's codec delay.

The muxer holds audio back until a frame at or after its time has arrived, so the writer hands
over each frame's audio and the frame as they are made and the file still comes out in time order.

## What the settings set

The video sheet's settings reach libvpx under these names:

    Rate control        rc_end_usage: VPX_VBR, VPX_CBR, VPX_CQ or VPX_Q
    Video bitrate       rc_target_bitrate, in kilobits a second, never below 100
    Quality level       VP8E_SET_CQ_LEVEL, 0 to 63
    Encoder speed       VP8E_SET_CPUUSED, 5 to 9
    Keyframe interval   kf_max_dist, the seconds times the frame rate, rounded, with kf_min_dist 0
    Tune                VP9E_SET_TUNE_CONTENT: VP9E_CONTENT_DEFAULT or VP9E_CONTENT_SCREEN
    Chroma              g_profile 1 with I444 frames, or g_profile 0 with I420
    (always)            rc_max_quantizer 40 under VBR and CQ

The realtime only build turns any speed from -4 to 4 into 5, so the sheet offers 5 to 9 and
nothing the encoder would change without saying. `rc_dropframe_thresh` is nought under every rate
control, so each frame drawn is a frame in the file, even where CBR runs short of bits.

Tile columns follow the width: as many as the encoder threads allow while each tile stays at least
256 pixels wide, which is four at 1920 and eight at 3840.

The picture is cleared to black and holds only the lanes of the parts the piece carries, the
parts `Song.carries` names, which are the same parts a stem is written for. Where it carries
none, every part gets a lane.

The scope in a video is drawn at its design sizes times the picture height over 720, in faces
baked at that scale for the one export, so 3840 by 2160 carries the scope drawn three times as
large rather than the 1280 by 720 one with room around it.

## Colour and flicker

A scope is lines two to four pixels thick in saturated colours on black, which is close to the
worst case for 4:2:0: the chroma plane has half the resolution each way, so a thin line's colour
is averaged with the black beside it. Measured on 14 September 2026 with ffmpeg's libvpx-vp9 at
realtime, row threading and screen tuning, over 90 frames of nine moving sine traces three pixels
thick at 1280 by 720, 60 frames a second and 6000 kilobits, which is the bitrate per pixel of 2560
by 1440 at 24000. Colour kept is the saturation of the decoded traces over the source's; flicker is
the mean change between consecutive decoded frames over pixels at least six from any trace:

    chroma  speed  largest quantiser  bytes     trace error  colour kept  flicker
    4:2:0   7      63                 924181    44.40        41.3 %       0.670
    4:2:0   7      40                 1257739   37.98        48.4 %       0.581
    4:4:4   7      63                 1078469   29.32        74.7 %       0.786
    4:4:4   7      48                 1194190   28.44        75.7 %       0.761
    4:4:4   7      40                 1789997   18.50        86.9 %       0.569
    4:4:4   5      40                 1095448   16.36        90.2 %       0.423

Turning adaptive quantisation off changed nothing, byte for byte, and neither default tuning in
place of screen tuning nor a static threshold of 500 did better than the 4:4:4, speed 7, largest
quantiser 40 row. A video therefore starts at 4:4:4 and speed 5, and variable and constrained
quality never go coarser than 40. The measurement is ffmpeg's libvpx rather than the encoder this
repository compiles in; `mdd gate video` measures the colour a thin line keeps through the compiled
one, and on still lines two pixels thick it keeps 68.8 per cent of the saturation at 4:2:0 and
99.8 per cent at 4:4:4.

## Defaults

The video settings start at YouTube's recommended upload encoding settings, as
support.google.com/youtube/answer/1722171 gave them on 2026-09-13:

    frame rate          60, one of the common rates it lists
    bitrate type        variable
    video bitrate       its SDR figure for the size, the high frame rate one at 48 and above
    key frames          a closed group of pictures half the frame rate long, so every 0.5 s
    colour              BT.709
    audio               48 kHz, stereo at 384 kbit/s, Opus being one of the codecs it names

Its bitrates, in kilobits a second, with the low end taken where it gives a range:

    size            24 to 30    48 to 60
    1280 by 720     5000        7500
    1920 by 1080    8000        12000
    2560 by 1440    16000       24000
    3840 by 2160    35000       53000

It names no size, so a video starts at 2560 by 1440. Its container is MP4 and its video codec
H.264, and neither is written here: the file is WebM and the video VP9. WebM is on the list of
formats its upload help accepts.

## Measured

`mdd gate video` writes two seconds of colour bars moving four pixels a frame and a 440 Hz tone,
at 320 by 180 and 4:4:4, thirty frames a second, 800 kilobits of video and 96 of audio:

    file                29035 bytes
    frames              60, the first a key frame, the last at 1966 ms
    Opus packets        101, the last at 2000 ms
    duration            2000 ms, with cues
    frame 30, ffmpeg    0.46 levels from the source on average
    audio, ffmpeg       96960 samples against 96000, at 439.47 Hz against 440

It then writes one second of the same bars under each rate control, at quality level 30 where the
control reads one, and eight frames at 3840 by 2160 under VBR. Every file holds every frame:

    VBR                 15790 bytes, 30 frames
    CBR                 17220 bytes, 30 frames
    CQ                  17365 bytes, 30 frames
    Q                   16512 bytes, 30 frames
    3840 by 2160        31429 bytes, 8 frames, 3840 by 2160 in the track header

Bars moving four pixels a frame are cheap to predict, so a second at 320 by 180 comes to between
126 and 139 kilobits under every control, well under the 800 asked for.

`mdd gate spine` exports a scope video the way the export panel does: a clip of three notes starting
a beat in, rendered and levelled as a mix, then drawn a frame at a time into 1280 by 720 at thirty
frames a second. The first frame is empty lanes, so the pixels that change by frame 30 are the
traces:

    frames              60 of 60 drawn, 60 in the file
    file                516676 bytes for two seconds
    frame 30 against 0  52869 of 921600 pixels changed, 5.74 per cent

What the codec costs the executable, measured on MSVC release builds of the same tree before and
after the video export went in:

    before              5898752 bytes
    after               6689792 bytes, 791040 more
