# Renderer notes

Which SDL backend draws the interface, and what was wrong with vulkan.

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

## What was wrong

Both faults are vulkan's, both sit below this application, and both are measured on the screen
rather than in the renderer. A still window is correct on every backend; what goes wrong is a single
frame here and there while the interface is changing, which is why a screenshot of an idle window, a
readback and a comparison of the draw commands all came back clean.

### How it is measured

The application is driven with real input: the pointer over the playlist and then over the roll,
the control key held, and the wheel turned twenty notches in and twenty out, once with the transport
stopped and once with it playing. Every frame the compositor produces is taken with Desktop
Duplication, which reads what Windows put on the screen, so a frame the renderer drew correctly but
the display showed wrongly is seen as wrong. A run is 84 seconds and about 4,400 frames.

Two things are counted in each frame:

- **A glitch**: pixels that differ from the frame before and from the frame after, spread across
  panels that have nothing to do with one another. A playhead, a key lighting under a note or a zoom
  step changes one region; this changes the channel rack, the synthesiser panel and the transport
  bar at once.
- **A repeat**: a frame identical to one from two to four frames earlier and not to the one before
  it, which is an old image returning to the screen.

### Glyphs drawn from another frame's vertices

The first fault is the one the reports describe as wrong glyphs. For one frame, labels across the
window turn into other characters: `CHANNEL RACK` reads `@HANNEL ITK@K`, `FM1` to `FM4` become
strings of other glyphs, a total level of 34 reads `9` and two marks, and the frames either side are
correct. It happens most at the roll's widest zooms with the transport running, which is where the
most geometry changes from one frame to the next.

SDL's vulkan renderer copies each frame's vertices into one set of mapped buffers, starting from the
first of them again every frame. Before recording a frame it waits only for the frame as many
presents back as the swap chain has images, four here. A frame it has already submitted can still be
waiting for its image to come free when the next frame's vertices are copied over its own, and it is
then drawn with its own draw calls and the next frame's vertices. Every quad after the first place
the two frames differ takes another quad's corners and texture coordinates, which is a glyph
somewhere else in the atlas. The direct3d12 backend waits for the device at every present and cannot
do this; the direct3d11 and opengl drivers manage their own buffers.

`mdd_render_present` waits for the device after every present on vulkan, through the
`vkDeviceWaitIdle` of the instance SDL publishes on the renderer, so one frame is in flight and the
copy never lands on vertices a frame still needs.

### A frame from two presents earlier

The second fault is an old image coming back for one refresh: the screen shows frames A and B and
then A again, byte for byte, with the time readout going backwards, before carrying on. During
playback that is a playhead jumping back two pixels for seven milliseconds; on a zoom step it is the
whole previous zoom level flashing. Two presents back is what a two buffer flip swap chain shows when
it flips a buffer nothing new was copied into, and a windowed vulkan swap chain on Windows is
presented through one.

It follows the present mode and nothing else:

| vulkan present mode | wait after present | runs | glitches | repeats |
| --- | --- | --- | --- | --- |
| strict FIFO | no | 6 | 32 | 111 |
| strict FIFO | yes | 4 | 0 | 53 |
| relaxed FIFO | no | 2 | 2 | 0 |
| relaxed FIFO | yes | 5 | 0 | 0 |
| vsync off | yes | 2 | 0 | 1 |

Turning off every implicit layer the machine loads into a vulkan application, two frame capture
hooks, an overlay and a post processor, changed neither count. A synchronised vulkan renderer is therefore
asked for adaptive vsync, which SDL turns into the relaxed FIFO present mode. It still waits for the
display, and only presents at once when a frame is already late.

### The other backends

Measured the same way on the same machine, with no change made to either:

| backend | runs | glitches | repeats |
| --- | --- | --- | --- |
| direct3d11 | 3 | 0 | 0 |
| direct3d12 | 4 | 0 | 0 |
| opengl | 2 | 0 | 0 |

direct3d12 was reported as flickering as well and does not here. SDL's direct3d12 backend waits for
the device at every present and keeps each texture upload's buffer until the batch that uses it has
run, so neither mechanism above reaches it. What the report saw on direct3d12 is not established.

## Zoom

`mdd gate shot --direct --sweep <file>` shows its window and zooms the playlist, or with `--centre 1`
the roll, from all the way out to all the way in, a wheel step of 1.25 at a time, presenting every
step for as many frames as `--frames` asks at vsync and writing the step's number into the file as it
starts, so a capture taken from outside the process can say which step it saw. All 22 steps of Hyper
Loop are byte identical on direct3d11, vulkan and direct3d12, and so are the still frames of the
application itself after every step of the session above: no zoom level draws wrongly once it has
settled.

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

Vulkan's chain is twice as deep as the one Windows runs on, which is also how
many frames SDL lets it have in flight before waiting, and that depth is what
leaves room for the first fault below.

Two more things the same program checks, and both are the same on all seven:

- **A clear reaches past a clip that is still set.** The frame clears before the
  paint stack unwinds, so a clip left behind would have held the clear to it.
  None of them does that.
- **A frame that draws into a texture part way through keeps what it had already
  drawn.** A sheet bakes itself into a texture of its own mid frame, and a
  backend that records render passes has to end one and begin another to do it.
  None of them loses the window's contents over that.

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
