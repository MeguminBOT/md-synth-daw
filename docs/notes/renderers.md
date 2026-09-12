# Renderer notes

Which SDL backend draws the interface, and what has been established about the two that
are wrong.

SDL3 ships `direct3d11`, `direct3d12`, `opengl`, `opengles2`, `vulkan` and `software`, and
`SDL_CreateRenderer` takes any of them by name. Windows starts at `direct3d11`.

## Choosing one

`mdd.App.PINNED` is what Windows falls back to and starts at. A flag names another on any
platform, and so does the `renderer` setting:

```sh
mdd --vulkan
mdd --dx12
mdd --renderer=opengl
```

A name SDL does not offer is ignored and the default stands, so an unrecognised flag
cannot leave the application with no renderer at all.

The selection was behind `#if windows` until it was measured, which meant the flags were
compiled out on the one platform the fault appears on: nothing on Windows could ask for
the backend that was wrong, so nothing could look at it.

## What is wrong

`direct3d12` and `vulkan` draw the interface incorrectly once the transport is running and
the playhead, the scope and the meters are redrawing every frame. A still window is
correct on all six, which is what makes a screen capture of an idle window worth nothing.

## What has been ruled out

`mdd gate shot` renders the whole interface through a named backend and writes a PNG, so
four backends can be compared against each other on the same scene:

```sh
mdd gate shot --direct --frames 120 --renderer vulkan --out shot-vulkan.png
```

Measured at 1600x1000, on the same scene, `direct3d11`, `direct3d12`, `vulkan` and
`opengl` write the **same file, byte for byte**, SHA256 `2081c52c0ade1b85`:

| what was rendered | agreement |
| --- | --- |
| one frame into a target texture | all four identical |
| one frame into the window | all four identical |
| 120 presented frames into the window | all four identical |

So the draw commands the interface issues are not what differs. Three mechanisms were
read out of the SDL sources and none of them is it:

- **A texture updated in the middle of a frame is safe.** `SDL_UpdateTexture` calls
  `FlushRenderCommandsIfTextureNeeded`, which flushes the queue first where the pending
  commands reference that texture. The font atlas bakes a glyph the first time it is
  asked for, which is mid frame, and that is ordered correctly on every backend.
- **A frame's vertex data cannot overflow.** The direct3d12 backend recreates its vertex
  buffer where one is too small, and issues the batch early where all 256 slots are used.
- **Nothing is drawn without being cleared first, and nothing is presented without being
  drawn.** `Stage.draw` sleeps instead of presenting where nothing changed, and
  `Root.frame` repaints the whole tree rather than a dirty region.

## What each backend's chain does

`mdd gate swap` presents a run of flat frames through one backend and reads the
buffer each frame is about to be drawn into, before anything clears it. That is
the swapchain rotation seen from inside the process, which is the one thing a
readback can still see.

| backend | the buffer a frame starts with |
| --- | --- |
| direct3d11, direct3d12, opengl, opengles2 | 2 presents back |
| **vulkan** | **4 presents back** |
| direct3d, gpu | 1 present back |

Vulkan's chain is twice as deep as the one Windows runs on, so anything that
reaches the screen without being wholly drawn shows a frame four back there
against two on direct3d11. That is why the same fault reads as worse under it.

It does not explain direct3d12, which measures the same as direct3d11 on every
probe here and is still wrong.

Two more things the same program checks, and both are the same on all seven:

- **A clear reaches past a clip that is still set.** The frame clears before the
  paint stack unwinds, so a clip left behind would have held the clear to it.
  None of them does that.
- **A frame that draws into a texture part way through keeps what it had already
  drawn.** A sheet bakes itself into a texture of its own mid frame, and a
  backend that records render passes has to end one and begin another to do it.
  None of them loses the window's contents over that.

## What is left

A readback cannot see it. `SDL_RenderReadPixels` flushes the queue and reads the
result, so it reports what was rendered rather than what reached the screen. A
fault in presentation is invisible to every measurement above and to any check
that renders into a texture.

What remains unmeasured is the one thing this application does that an ordinary
SDL program does not: it draws and presents only the frames where something
changed, and sleeps otherwise. `--redraw` turns that off, so a run with it and a
run without it differ in nothing else. If the flicker goes with `--redraw`, the
dirty model and the deeper chain are the whole story; if it stays, the fault is
under SDL and the pinning stands.

SDL is at 3.4.14 here against 3.4.16 released, and neither release note mentions
the renderer backends.

Upstream closed one report of the same shape, libsdl-org/SDL#12432, "flickering
between previous and latest output buffer". Its cause was `SDL_RenderPresent`
called more than once in a frame, while a render target was set. This
application presents once, from one place, with no target set, so it is not
that one.

## What it actually looks like

It is not stale frames. It is **wrong glyphs**, and a capture of the composited
window taken from outside the process is what shows it: `CHANNEL RACK` reads
`@FANNEL 'N>@K`, `FM1` to `FM4` read `IK2I3` upward, while `FM5`, `FM6`, the
squares, the noise and the converter directly beneath them are right. The first
operator column reads `AR 987` where thirty one is the most the register holds,
with the three columns beside it correct. Nothing that is not text is ever
wrong.

Six captures of a still window are byte identical to each other, so the
corruption is steady rather than alternating. What reads as flicker is which
draws are wrong changing as the interface updates.

A readback cannot see any of it. `SDL_RenderReadPixels` flushes the queue and
waits, so the frame it returns is always the correct one: ninety presented
frames of changing text, read back at the end, come out the same on all seven
backends. Two probes of that shape have now come back clean against a fault
that a screen capture shows immediately. A capture from outside the process is
the only instrument that works.

The application issues the same draw calls on both backends, which is measured,
so this is not a logic fault in `Paint` or `Font`. The atlas is baked once at
load for codepoints 32 to 255 and never touched again while English is drawn,
`reface` flushes before a face changes, and `binds` flushes on any texture
change.

One thing was tried and is **not** the answer on its own: `Paint.room` grows the
vertex batch and never flushes, so a frame reaches the card as one very large
`SDL_RenderGeometry` call, and the corrupted draws are the earliest ones in the
frame, which is what a staging buffer wrapping would look like. Bounding the
batch by flushing instead of growing cleared the channel rack and left the
operator column exactly as wrong as before. Whatever it is, batch size is at
most part of it.
