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

## Measured

`mdd gate video` writes two seconds of colour bars moving four pixels a frame and a 440 Hz tone,
at 320 by 180, thirty frames a second, 800 kilobits of video and 96 of audio:

    file                29141 bytes
    frames              60, the first a key frame, the last at 1966 ms
    Opus packets        101, the last at 2000 ms
    duration            2000 ms, with cues
    frame 30, ffmpeg    0.67 levels from the source on average
    audio, ffmpeg       96960 samples against 96000, at 439.47 Hz against 440
