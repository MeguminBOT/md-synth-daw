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

## What is left

A readback cannot see it. `SDL_RenderReadPixels` flushes the queue and reads the result,
so it reports what was rendered rather than what reached the screen. A fault in
presentation, which is where the swapchain and the frames in flight differ between
`direct3d11` and the other two, is invisible to every measurement above and to any check
that renders into a texture.

What would settle it is a capture of the window itself while the transport runs, taken
outside the process, against the same scene on two backends.
