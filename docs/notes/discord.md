# Discord presence notes

What Discord's local IPC actually is, what was measured against a running client, and why this
repository speaks it directly instead of linking a library. `src/mdd/native/discord.cpp` is the
transport, `mdd.host.Discord` binds it, and `mdd.app.Presence` decides what is said.

## Why there is no vendored library

`discord-rpc` is archived and `discord-game-sdk` is a closed binary with a licence that binds
redistribution. Neither is a candidate under the vendoring rules. The protocol underneath both is
small enough that writing it is cheaper than depending on either: a socket, an eight byte header and
a JSON payload. Nothing else in the application needs Discord's SDK, because nothing else is being
asked for. Presence is a one way announcement.

## The socket

On Windows a named pipe, `\\.\pipe\discord-ipc-N` for N in 0 to 9. Ten because ten clients can run
at once, and the first that opens is the one to talk to. `CreateFileA` on a pipe that is not there
fails at once with no wait, so walking all ten costs nothing when Discord is not running.

Off Windows a unix socket named `discord-ipc-N` inside the first of `XDG_RUNTIME_DIR`, `TMPDIR`,
`TMP`, `TEMP` and `/tmp` that is set, and also inside `app/com.discordapp.Discord/`, `snap.discord/`
and the Vesktop flatpak's `xdg-run` directory beneath it, because a sandboxed client puts its socket
under its own prefix rather than at the top.

Reads never block. Windows peeks the pipe for how much is waiting before reading any of it; the unix
socket is put in non blocking mode after connecting. Writes block, and are allowed to: a payload is
under a kilobyte and the client's receive buffer is 64 KB.

## The frame

    int32 opcode, little endian
    int32 length, little endian
    length bytes of UTF-8 JSON

| opcode | what |
| --- | --- |
| 0 | handshake, sent first and once |
| 1 | a command or an event |
| 2 | close, in either direction, carrying a code and a message |
| 3 | ping |
| 4 | pong |

The handshake is `{"v":1,"client_id":"<the application id>"}`. Nothing else may be written until it
has been. A ping has to be answered with a pong carrying the same body or the client drops the
connection, which is the one part of this that is not optional.

Setting the presence is opcode 1 with

    {"cmd":"SET_ACTIVITY","nonce":"<anything unique>","args":{"pid":<this process>,"activity":{...}}}

`pid` is required, which is why `mdd_discord_pid` exists at all. Discord uses it to notice that the
process has gone and clear the presence, so nothing has to be sent on the way out.

## What was measured

`mdd gate presence --dial <id>` opens a socket, runs `Presence` against it for eight seconds and
prints what came back. It is a program the gate does not run.

Dialled with an application id that does not exist, against a running client:

    socket discord-ipc-0
    1 frames read, 1 written
    fault: Invalid Client ID

The reply arrives as opcode 2 rather than as an error event, and the connection is closed by the
client immediately after. That is the whole read path exercised: header, length, body, the message
lifted out of the JSON, and the close acted on.

Dialled with the real one:

    socket discord-ipc-0
    connected as Lulu, 1 sent
    2 frames read, 2 written

Two frames because the handshake is answered with a READY carrying the signed in user, and every
command is answered in turn. What says the activity was taken is that the fault stayed empty: an
answer carrying `"evt":"ERROR"` puts its message there, and that is what an id Discord does not know
produced above.

## The activity, and its limits

| field | limit | what this sends |
| --- | --- | --- |
| `details` | 128 | the song's name, and its author when it has one |
| `state` | 128 | what is being done: the bar while playing, the channel and pattern while editing, the work in hand while importing or exporting |
| `assets.large_image` | an asset name | whatever `mdd.xml` names, left out when it names nothing |
| `assets.large_text` | 128 | the census: how many FM, PSG, noise and DAC channels the song uses, then patterns, notes and bars |
| `assets.small_image` | an asset name | one of three from `mdd.xml`, by what the transport is doing |
| `assets.small_text` | 128 | the tempo, the position and the length, and whether it is looping or playing through a driver |
| `party.size` | two numbers | channels carrying notes, out of eleven. Discord draws this as "(7 of 11)" |
| `timestamps.start` | ms since epoch | while stopped, when the song was opened. While playing, the moment the playhead was at zero |
| `timestamps.end` | ms since epoch | while playing a song that is not looping, when it finishes. Discord draws a bar |
| `buttons` | 2, labels of 32 | one, to the repository |

The limits are counted in characters and the fields are cut to 118 before quoting, which leaves room
for whatever escaping adds. Everything is escaped by hand rather than through `haxe.Json`, because
the payload is assembled from known parts and only the song's name and author are arbitrary.

An asset name that has not been uploaded to the application simply does not appear. There is no
error and no fallback, which is why the four names are attributes of `<presence>` rather than
constants: which assets exist belongs to the application, not to the code. An empty name leaves the
image out of the payload entirely, and because `small_text` is the tooltip on `small_image`, an
empty badge takes the tempo and the position with it.

A new application already answers to three names it derives from its own icon and cover image,
`embedded_cover`, `embedded_icon` and `embedded_background`, before anything has been uploaded.

## Timing

Discord throttles activity updates at five in twenty seconds and silently drops the rest, so an
update is built at most every five seconds and only written when it differs from the last one that
went out. The socket is polled every second, which is what answers a ping in time. A failed connect
is retried every twelve seconds, and a connect that fails costs ten immediate failures rather than
any waiting.

An epoch stamp is thirteen digits, which does not fit an `Int` on hxcpp. `Presence.whole` writes the
digits out of a `Float` by hand rather than trusting `Std.string` not to reach for an exponent.

## What is deliberately not sent

No file path, ever, at any level. The song's name is something typed on purpose; the path it was
saved to is not, and it carries a user name on nearly every machine.

The `Sharing` preference has three settings. **Off** never opens the socket. **The application only**
sends no part of the song: no name, no census, no party, no tempo, and the state says no more than
whether something is playing. **The song as well** is the default and sends the table above.

## Setting it up

The presence needs an application id, from an application made at discord.com/developers, in
`mdd.xml`:

    <presence discord="..." cover="embedded_cover"
        playing="embedded_icon" stopped="embedded_icon" working="embedded_icon" />

An empty id means the socket is never opened. The application's name in the developer portal is what
Discord prints after "Playing", so it is the name that has to read correctly rather than anything in
this repository.

The three badges point at one image until three are uploaded, which costs nothing but leaves the
badge the same whatever the transport is doing. Three separate images and it follows.
