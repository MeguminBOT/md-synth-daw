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

Frames are converted to I420 with BT.709 weights at studio range, and the VP9 bitstream says so
through its colour space and range, because a decoder left to guess picks BT.601 below 720 lines
and every colour shifts.

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
    Keyframe interval   kf_max_dist, the seconds times the frame rate, with kf_min_dist 0
    Tune                VP9E_SET_TUNE_CONTENT: VP9E_CONTENT_DEFAULT or VP9E_CONTENT_SCREEN

The realtime only build turns any speed from -4 to 4 into 5, so the sheet offers 5 to 9 and
nothing the encoder would change without saying. `rc_dropframe_thresh` is nought under every rate
control, so each frame drawn is a frame in the file, even where CBR runs short of bits.

Tile columns follow the width: as many as the encoder threads allow while each tile stays at least
256 pixels wide, which is four at 1920 and eight at 3840.

The scope in a video is drawn at its design sizes times the picture height over 720, in faces
baked at that scale for the one export, so 3840 by 2160 carries the scope drawn three times as
large rather than the 1280 by 720 one with room around it.

## Measured

`mdd gate video` writes two seconds of colour bars moving four pixels a frame and a 440 Hz tone,
at 320 by 180, thirty frames a second, 800 kilobits of video and 96 of audio:

    file                29141 bytes
    frames              60, the first a key frame, the last at 1966 ms
    Opus packets        101, the last at 2000 ms
    duration            2000 ms, with cues
    frame 30, ffmpeg    0.67 levels from the source on average
    audio, ffmpeg       96960 samples against 96000, at 439.47 Hz against 440

It then writes one second of the same bars under each rate control, at quality level 30 where the
control reads one, and eight frames at 3840 by 2160 under VBR. Every file holds every frame:

    VBR                 15772 bytes, 30 frames
    CBR                 16302 bytes, 30 frames
    CQ                  16497 bytes, 30 frames
    Q                   16404 bytes, 30 frames
    3840 by 2160        16761 bytes, 8 frames, 3840 by 2160 in the track header

Bars moving four pixels a frame are cheap to predict, so a second at 320 by 180 comes to between
126 and 132 kilobits under every control, well under the 800 asked for.

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
