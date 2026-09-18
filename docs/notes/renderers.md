# Renderer notes

Which SDL backend draws the interface, and what has been established about the two that
are wrong.

SDL3 ships `direct3d11`, `direct3d12`, `opengl`, `opengles2`, `vulkan` and `software`, and
`SDL_CreateRenderer` takes any of them by name. Windows starts at `direct3d11`.

The preferences offer every backend the build has except `software` and `gpu`, and name each for
the interface it drives: `direct3d` is DirectX 9, `direct3d11` DirectX 11, `direct3d12` DirectX 12,
`opengl` OpenGL, `opengles2` OpenGL ES and `vulkan` Vulkan. The setting keeps the SDL name.

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

## What it is not, from the other side

A screen capture taken outside the process shows the fault at once, so it is the
instrument. With it, none of the following reproduces the fault on vulkan or on
direct3d12, every one read off the screen rather than out of the renderer:

| what was run | how it came out |
| --- | --- |
| an empty document, small window | right |
| an empty document, full screen | right |
| a piece loaded, full screen | right |
| a piece loaded and playing | right |
| the same with the pointer walked over the panels | right |
| the same with the window focused and in front | right |
| six minutes of it playing, forty two readings of the channel rack | one reading, no change |
| six starts and kills before the run that was looked at | right |
| a window of text through one backend | right |
| text drawn into a texture and blitted, beside text drawn straight | right |
| the face shut and baked again part way through a run | right |
| direct3d12, a piece loaded and playing | right |

Two mechanisms were modelled on purpose because each would have explained why one
backend differs and another does not, and neither did it:

- **A face baked again while it is being drawn.** `Stage.faces` calls `shed`,
  which destroys every atlas, and bakes new ones. A reference left on the old
  one is a texture that direct3d11 keeps alive under its driver and vulkan does
  not. Modelled in `mdd gate swap --hold`, and the text stays right.
- **A pointer into collected memory.** The vertices are handed to SDL as a raw
  pointer into a `Vector`, which the collector may move. `SDL_RenderGeometryRaw`
  copies them at the call, so the window is a single call wide and the same on
  every backend.

The application issues the same draw calls whichever backend is under it, which
is measured, so nothing in `Paint` or `Font` is the fault on its own. What is
left is a state the reported sessions were in and a fresh run is not, and no
reading taken from inside the process can see it.

What would settle it is a capture of the window taken at the moment somebody is
watching it go wrong, rather than a capture of a run that was started to look
for it.

## Zoom

Both reports say the fault shows at certain zoom levels. `mdd gate shot --direct --sweep <file>`
shows its window and zooms the playlist, or with `--centre 1` the roll, from all the way out to all
the way in, a wheel step of 1.25 at a time, presenting every step for as many frames as `--frames`
asks at vsync and writing the step's number into the file as it starts. A capture taken from outside
the process at every step, with `PrintWindow` and `PW_RENDERFULLCONTENT`, reads what the compositor
was given rather than what was rendered.

| what was swept | steps | agreement |
| --- | --- | --- |
| the playlist of Hyper Loop, 1600x1000, 60 frames a step | 22 | direct3d11, vulkan and direct3d12 byte identical at every step |

So no zoom level draws wrongly when it is held still. Each step presents the same frame sixty
times, and a flicker needs frames that differ, so what this leaves is the interface changing
while the zoom is where the reports put it.

## The window going bright

The other half of what is reported is the window flashing white, which is not a
colour anything here clears to: the frame is cleared to the theme's ground and
the ground is dark in every theme that ships. A vulkan swapchain image is
undefined until something writes it, and it becomes undefined again whenever the
chain is made again, which a resize does, so an undefined image reaching the
screen is the one thing that would read as white.

Read from a patch of the window that stays dark, as fast as the screen can be
read, it does not happen:

| how it was run | readings | brightest |
| --- | --- | --- |
| full screen, playing, resized every few hundred readings | 17836 over 150 s | 119 |
| a small window, playing, a patch that is empty playlist | 53268 over 420 s | 7.5 |

The first of those sampled the middle of the window, which is where the clips
are drawn in light grey, so 119 is the clips rather than a flash. The second
sampled a corner that is dark in normal use, and nothing there ever rose above
eight out of two hundred and fifty five.

Around a hundred and twenty readings a second against a screen at a hundred and
forty four means a flash lasting a single frame is more likely seen than missed.
Ten minutes of it were watched and none was.

Neither fault reproduces while nobody is at the machine. Both need somebody
driving the interface, which is the one thing none of this can manufacture:
the pointer can be walked over the panels and keys can be posted to the window,
but nothing here clicks, drags, scrolls or opens anything.
