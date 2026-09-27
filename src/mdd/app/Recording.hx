package mdd.app;

import haxe.ds.Vector;
import mdd.song.Clip;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.edit.AddNote;

@:unreflective

/**
	What recording writes while it is armed: every key played on a MIDI keyboard, or clicked on the
	piano roll's keyboard, becomes a note at the playhead, starting on the nearest grid line.

	While the song plays, a note lasts as long as its key was held, rounded to the grid. While it
	is stopped, a note is one grid step long, and once every key held is let go the playhead moves
	on by that step, so a run of keys pressed one after another lays out in order and keys held
	together make a chord. With the grid off, a step is a beat.

	A note goes on the channel chosen when its key went down, into the pattern chosen then, and
	only where that pattern is under the playhead: a key pressed while the song plays something
	else is heard and not written. Each note is written when its key is let go, as one step on the
	undo stack.

	The session owns it, so a song opened in place of another records into the new one.
**/
final class Recording {
	/**
		A key that is not held.
	**/
	static inline final UP = -1;

	/**
		A tick where no clip of the pattern plays.
	**/
	static inline final NOWHERE = -0x7FFFFFFF;

	final session:Session;

	/**
		The tick each key went down at on the playlist, or `UP`.
	**/
	final pressedAt:Vector<Int> = new Vector<Int>(128);

	/**
		Whether each held key went down while the song played, which is what decides whether it
		lasts as long as it was held or a grid step.
	**/
	final playing:Vector<Bool> = new Vector<Bool>(128);

	/**
		How hard each held key was played.
	**/
	final struck:Vector<Int> = new Vector<Int>(128);

	/**
		The part each held key records on.
	**/
	final parts:Vector<Int> = new Vector<Int>(128);

	/**
		The pattern each held key records into.
	**/
	final patterns:Vector<Int> = new Vector<Int>(128);

	/**
		Where that pattern starts on the playlist under the clip it was pressed in.
	**/
	final origins:Vector<Int> = new Vector<Int>(128);

	var held:Int = 0;
	var lastTick:Int = 0;

	/**
		Builds the recording for a session.

		@param session The session it writes into.
	**/
	public function new(session:Session) {
		this.session = session;
		for (pitch in 0...128) pressedAt[pitch] = UP;
	}

	/**
		Starts a note at the playhead, where recording is armed.

		@param pitch The MIDI note number.
		@param velocity How hard it was played, 1 to 127.
	**/
	public function pressed(pitch:Int, velocity:Int):Void {
		if (pitch < 0 || pitch > 127 || !session.arming) return;
		if (pressedAt[pitch] != UP) released(pitch);

		final tick = session.transport.tick();
		final origin = placed(session.pattern, tick);
		if (origin == NOWHERE) return;

		pressedAt[pitch] = tick;
		playing[pitch] = session.transport.playing;
		struck[pitch] = velocity < 1 ? 1 : (velocity > 127 ? 127 : velocity);
		parts[pitch] = session.part.index();
		patterns[pitch] = session.pattern;
		origins[pitch] = origin;

		if (playing[pitch]) lastTick = tick;
		held++;
	}

	/**
		Ends a held note and writes it. Where the song is stopped and this was the last key held,
		the playhead moves on a grid step past where the note starts.

		@param pitch The MIDI note number.
	**/
	public function released(pitch:Int):Void {
		if (pitch < 0 || pitch > 127 || pressedAt[pitch] == UP) return;

		if (playing[pitch]) {
			finishes(pitch, session.transport.playing ? session.transport.tick() : lastTick);
			return;
		}

		final from = pressedAt[pitch];
		final origin = origins[pitch];
		final next = origin + session.snapped(from - origin) + step();
		final pattern = session.song.patternAt(patterns[pitch]);

		finishes(pitch, from + step());

		if (held > 0 || session.transport.playing || pattern == null) return;

		final wraps = session.alone && next - origin >= pattern.length;
		session.transport.seek(session.song.tempo.samplesAt(wraps ? origin : next));
	}

	/**
		Writes a note one grid step long where the playhead is, which is what clicking a key on the
		piano roll's keyboard records, and moves the playhead on the way a key let go does.

		@param pitch The MIDI note number.
	**/
	public function strikes(pitch:Int):Void {
		pressed(pitch, 100);
		released(pitch);
	}

	/**
		Called once a frame. Keeps where the playhead is while the song plays, and ends every key
		still held once recording is disarmed or the song stops under a key pressed while it
		played.
	**/
	public function follows():Void {
		final going = session.transport.playing;
		if (going && session.arming) lastTick = session.transport.tick();

		if (held == 0) return;

		for (pitch in 0...128) {
			if (pressedAt[pitch] == UP) continue;

			if (playing[pitch] && (!going || !session.arming)) finishes(pitch, lastTick);
			else if (!playing[pitch] && !session.arming) finishes(pitch, pressedAt[pitch] + step());
		}
	}

	/**
		@return How long a note is that was not held while the song played: a grid step, or a
			beat with the grid off.
	**/
	inline function step():Int {
		return session.snap < 1 ? session.song.tempo.ppqn : session.snap;
	}

	/**
		@param pattern A pattern.
		@param tick A tick on the playlist.
		@return Where the pattern starts on the playlist under the clip playing it at that tick,
			or `NOWHERE` where no clip of it plays there. Played on its own, the pattern starts
			at nought.
	**/
	function placed(pattern:Int, tick:Int):Int {
		if (session.alone) return 0;

		for (track in session.song.tracks) {
			for (clip in track.clips) {
				if (clip.kind != Clip.PATTERN || clip.pattern != pattern) continue;
				if (tick >= clip.at && tick < clip.ends()) return clip.origin();
			}
		}

		return NOWHERE;
	}

	/**
		Lets a held key go and writes its note.

		@param pitch The MIDI note number.
		@param until The tick it was let go at on the playlist.
	**/
	function finishes(pitch:Int, until:Int):Void {
		final from = pressedAt[pitch];

		pressedAt[pitch] = UP;
		held--;

		writes(parts[pitch], patterns[pitch], origins[pitch], from, until, pitch, struck[pitch]);
	}

	/**
		Writes one note into a pattern, starting on the grid line nearest where it began. A note
		let go before it began, which is one held across the end of a loop, runs to the end of the
		pattern instead.

		@param part Which part it plays on.
		@param index Which pattern it goes into.
		@param origin Where that pattern starts on the playlist.
		@param from The tick it began at on the playlist.
		@param until The tick it ended at.
		@param pitch The MIDI note number.
		@param velocity How hard it was played.
	**/
	function writes(part:Int, index:Int, origin:Int, from:Int, until:Int, pitch:Int,
			velocity:Int):Void {
		final pattern = session.song.patternAt(index);
		if (pattern == null) return;

		final at = session.snapped(from - origin);
		if (at < 0 || at >= pattern.length) return;

		final grid = session.snap;
		var length = until >= from ? until - from : pattern.length - at;

		if (grid >= 1) length = Math.round(length / grid) * grid;
		if (length < (grid >= 1 ? grid : 1)) length = grid >= 1 ? grid : 1;

		final kind:Part = part;
		final note = new Note(at, length, pitch, velocity);
		if (kind.sampled() && session.song.drums) note.instrument = session.song.drumAt(pitch);

		session.does(new AddNote(index, kind, note));
	}
}
