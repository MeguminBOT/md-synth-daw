package mdd.play;

import haxe.ds.Vector;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;

/**
	Turns a song into events, sorts them, and plays them into a register stream.

	It is the only thing that decides when a note happens. It never touches a chip: it
	asks `Stream` for every write, which is what makes playback and an export the same
	sound rather than two paths that could drift.

	Events are held as parallel vectors of plain numbers rather than as objects,
	because a span is gathered and sorted once per block and the render thread is
	waiting.
**/
@:unreflective
final class Sequencer {
	/**
		Event: key a part off.
	**/
	public static inline final OFF = 0;

	/**
		Event: write a whole patch to a part.
	**/
	public static inline final PATCH = 1;

	/**
		Event: write one automated register.
	**/
	static inline final TWEAK = 2;

	/**
		Event: tune a part to a note.
	**/
	public static inline final TUNE = 3;

	/**
		Event: one byte to the sample channel.
	**/
	public static inline final DATA = 4;

	/**
		Event: key a part on.
	**/
	public static inline final ON = 5;

	/**
		Event: the writes that put a part in a known state before anything sounds.
	**/
	static inline final SETUP = 6;

	/**
		A `DATA` event carrying a sample byte.
	**/
	static inline final DAC_BYTE = 0;

	/**
		A `DATA` event carrying a square envelope step.
	**/
	static inline final PSG_STEP = 1;

	/**
		How many output samples one square envelope step lasts, which is a sixtieth of a
		second at 44100.
	**/
	public static inline final ENVELOPE_TICKS = 735;

	/**
		How many samples early a key off on an FM channel is written where another note keys the
		channel on at the same sample. The chip copies its key register once a slot, so a key off
		and a key on on one sample are no edge at all and the second note never attacks. One is
		enough: every write due at a sample is applied before the chip steps, and it steps at least
		once a sample. Every other key off lands where its note ends.
	**/
	static inline final GUARD = 1;

	/**
		How long before a key on an FM channel is let go where declicking is on, in samples: 4 ms.
		A key on starts every operator's phase again from nought, and a channel still sounding
		jumps to wherever that is. The quickest release falls 13 dB a millisecond, so the jump
		starts about 50 dB down rather than from the whole note, and the fall itself is too
		gradual to click.
	**/
	public static inline final FADE_LEAD = 176;

	/**
		What a key off event's second value is where it lets the channel go at its quickest
		rather than at its patch's own release. It sorts after a plain key off on the same sample
		and before the next note's patch, which puts the release back.
	**/
	static inline final FADE = 1;

	/**
		What a key off event's second value is where it ends a note whose patch cannot release, by
		letting the channel go at its quickest as well as keying it off. It is a key off in every
		other way, so the note it ends is no longer owed one.
	**/
	static inline final HUSH = 2;

	/**
		The slowest release rate that ever lets go. A carrier at nought or one is slower than
		anything a piece waits for, so its key off is never heard and the note sounds on.
	**/
	static inline final NEVER_RELEASES = 1;

	/**
		The slowest attack rate every carrier must have for a key on to be faded into. A slower
		carrier keys on from wherever the last note left it, which is what makes a legato swell,
		and letting it go first would be heard as a gap.
	**/
	static inline final FAST_ATTACK = 26;

	/**
		How long a converter hit takes to return to the middle where declicking is on, in
		samples: 1.5 ms. The converter holds the last byte it is given, so a hit that stops away
		from the middle steps there and then steps again when the channel is let go.
	**/
	static inline final SETTLE = 66;

	/**
		How far before a span a note may end and still owe it a write, in samples, where declicking
		is on: the settle, and room for a hit read at a low rate.
	**/
	static inline final SETTLE_REACH = 128;

	/**
		Whether to smooth the edges the parts would otherwise click on: a converter hit returns to
		the middle rather than stopping away from it, and an FM channel still sounding is let go
		just before the next note keys it on again. Every write it adds is one a driver could make.
		Playback takes this from the Sound preferences and an export from its own settings, so a
		register format written for the exactness of what it holds can leave it off.
	**/
	public var declick:Bool = true;

	/**
		Whether to end what nothing is playing: a note whose patch cannot release is let go at the
		quickest rate the part has where it ends, and the squares and the noise channel are written
		silent where the piece ends, which is what a level lane holding one past its last note
		would otherwise leave sounding. Everything that does let go is left exactly as it was.
	**/
	public var stuck:Bool = false;

	/**
		Whether the gather under way is only looking one lead ahead for the FM key ons a fade has
		to precede.
	**/
	var fading:Bool = false;

	/**
		The song being read.
	**/
	public final song:Song;

	/**
		What resolves a lane into the voices a part can sound.
	**/
	public final voices:Voices;

	/**
		Sequence only this part, or -1 for every part.

		This is what makes a stem a stem. The events of every other part are never
		gathered, so the chips render nothing else rather than rendering it and having
		it muted afterwards, and what a stem carries is what that part would have
		been given on its own.
	**/
	public var onlyPart:Int = -1;

	/**
		Sequence only the clips on this track, by index, or -1 for every track.

		This is what makes a track stem. The notes on every other track are never gathered, and
		only the parts this track plays notes on are sounded, with whatever automation clips on any
		track drive them. A part the track never plays is left alone entirely, so an automation clip
		panning it does not move its resting level in every stem at once and the set of them still
		sums back to the mix.
	**/
	public var onlyTrack:Int = -1;

	/**
		The parts the track `onlyTrack` names plays notes on, one bit a part, worked out at the start
		of every span.
	**/
	var trackParts:Int = 0;

	/**
		Whether any track was soloed at the start of the span.
	**/
	var soloTracks:Bool = false;

	/**
		Sequence only this pattern, or -1 for the whole arrangement. This is a pattern
		index and not a track, which `onlyTrack` is for.
	**/
	public var alone:Int = -1;

	/**
		The parts an automation clip on the playlist drives anywhere in the song, one bit a part,
		so a key on only looks for a clip over it where one can be. It is the whole song rather
		than the span, so a note that starts in one span and ends in the next is read the same way
		in both.
	**/
	var drivenParts:Int = 0;

	/**
		How many ticks are gathered between collector safe points, so a long span does not
		hold the collector off.
	**/
	public static inline final CHUNK = 8192;

	/**
		How many events one span may hold.
	**/
	public var capacity(default, null):Int;

	/**
		How many events the last span produced.
	**/
	public var count(default, null):Int = 0;

	/**
		How many events were thrown away for want of room in the event buffer.
	**/
	public var dropped(default, null):Int = 0;

	/**
		How many notes were never sounded because the part had no channel free.
	**/
	public var lost(default, null):Int = 0;

	/**
		Where a writer that plays samples its own way, which is what an XGM does, collects each
		converter note as it is sounded: where it starts and where it ends, in samples, and which
		instrument it plays, three entries a note, in the order they are sounded. A kit's hit is
		the instrument its key picks. Null unless such a writer asks, which keeps it off the render
		thread, where nothing may grow.
	**/
	public var strikes:Null<Array<Int>> = null;

	final ticks:Vector<Int>;
	final parts:Vector<Int>;
	final kinds:Vector<Int>;
	final firsts:Vector<Int>;
	final seconds:Vector<Int>;
	final order:Vector<Int>;
	final lines:Array<Null<mdd.song.Automation>> = cpp.NativeArray.create(4);

	/**
		What `owed` holds for a note that sounds until the next one rather than to an end.
	**/
	static inline final HELD = 0x7FFFFFFF;

	/**
		How many output samples apart the lanes a preset carries are read: about a millisecond. A
		driver frame is a sixtieth of a second, and a kick drops over three of them, so a lane read
		once a frame would be heard as steps rather than as a sweep. Only a change of value is
		written, so a lane holding still costs nothing.
	**/
	static inline final LANE_STEP = 44;

	/**
		How long the lanes a preset carries run on past the end of an FM note, in output samples:
		two seconds, so a lane that loops on the last note of a piece still ends. They stop sooner
		where the part keys on again.
	**/
	static inline final TAIL = 88200;

	/**
		Whether any preset the song holds moves anything on its notes, worked out at the start of
		every span. A song whose presets move nothing is sequenced exactly as it was before a
		preset could.
	**/
	var moving:Bool = false;

	/**
		Where the note a preset's lane is being read for keyed on, which `push` records beside every
		event it adds while this is at least nought, and -1 otherwise.
	**/
	var movingFrom:Int = -1;

	/**
		Per event, where the note whose preset moved it keyed on, or -1 for an event no preset
		lane made.
	**/
	final origins:Vector<Int>;

	/**
		Per part, where the note that last keyed it on keyed on, or -1. What a preset's lanes move
		for an earlier note is played only up to there, so a lane running on through a release
		stops where another clip's note takes the part.
	**/
	final keyedAt:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		The last sample a span was sequenced up to, so a span that starts behind it, which is a loop
		back to the start or a seek, forgets `keyedAt`.
	**/
	var reached:Int = 0;

	/**
		The voices a lane resolves into from as far back as a preset's lane can run on, kept apart
		from `voices` so looking back changes nothing a span's own notes do.
	**/
	final reaching:Voices = new Voices();

	/**
		Per part, one past the sample the sounding note's key off is due at, nought where none is
		owed, or `HELD`. A key off only comes from the note it ends, so a note whose track is muted,
		or which is deleted with its clip or on its own while it sounds, would sound on forever;
		this is what keys it off instead.
	**/
	final owed:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		Whether the song may have changed since the last span, which is when every sounding note is
		looked for again to see that it is still there.
	**/
	public var edited:Bool = false;

	/**
		The LFO setting last written, as register `$22` holds it, or -1 before any. An edit that
		changes the song's LFO is written at the start of the next span, so it is heard while the
		song plays rather than only from the next start or seek.
	**/
	var lfoSet:Int = -1;

	/**
		Builds a sequencer over a song.

		@param song The song to read.
		@param voices The voice resolver to use, or null for one of its own.
		@param capacity How many events a span may hold. Anything below 64 becomes 64.
	**/
	public function new(song:Song, voices:Null<Voices> = null, capacity:Int = 16384) {
		this.song = song;
		this.voices = voices == null ? new Voices() : voices;
		this.capacity = capacity < 64 ? 64 : capacity;

		ticks = new Vector<Int>(this.capacity);
		parts = new Vector<Int>(this.capacity);
		kinds = new Vector<Int>(this.capacity);
		firsts = new Vector<Int>(this.capacity);
		seconds = new Vector<Int>(this.capacity);
		order = new Vector<Int>(this.capacity);
		origins = new Vector<Int>(this.capacity);

		for (index in 0...Part.COUNT) keyedAt[index] = -1;
	}

	/**
		Sequences a span given in ticks, which is what an offline render works in.

		@param stream Where the register writes go.
		@param from The first tick.
		@param until One past the last tick.
		@return How many register writes were produced.
	**/
	public function spanned(stream:Stream, from:Int, until:Int):Int {
		lost = 0;

		var at = from;
		var made = 0;

		while (at < until) {
			var edge = at + CHUNK;
			if (edge > until) edge = until;

			made += emit(stream, at, edge);
			lost += dropped;
			at = edge;

			cpp.vm.Gc.safePoint();
		}

		return made;
	}

	public final driver:Driver = new Driver();

	var paced:Null<Stream> = null;

	/**
		Sequences a span given in output samples, which is what the render thread works
		in. Gathers the events, sorts them, and plays them into the stream.

		@param stream Where the register writes go.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
		@return How many register writes were produced.
	**/
	public function emit(stream:Stream, fromSample:Int, toSample:Int):Int {
		count = 0;
		dropped = 0;

		if (toSample <= fromSample) return 0;

		if (fromSample < reached) {
			for (index in 0...Part.COUNT) keyedAt[index] = -1;
		}

		reached = toSample;

		if (fromSample <= 0) {
			lfoSet = lfoOf(song);
			push(0, Part.Fm1, SETUP, lfoSet, 0);
		}

		tracked();
		settle(fromSample);
		gather(fromSample, toSample);
		if (declick) fades(fromSample, toSample);
		if (stuck) hushes(fromSample, toSample);

		sort();

		driver.on = song.driving;
		driver.rate = song.tempo.rate;

		if (!driver.on) {
			play(stream);
			return count;
		}

		if (paced == null) paced = new Stream(capacity * 4);

		final scratch = paced;
		scratch.clear();

		play(scratch);
		driver.paces(scratch, stream, toSample);

		return count;
	}

	/**
		Collects a write silencing every square and the noise channel where the piece ends, so a
		level lane holding one past its last note does not leave it sounding with nothing playing
		it. A part already silent takes the write and sounds no different for it.

		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function hushes(fromSample:Int, toSample:Int):Void {
		final ends = song.tempo.samplesAt(song.ends());
		if (ends < fromSample || ends >= toSample) return;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (!part.square() && !part.noise()) continue;
			if (!wanted(part)) continue;

			push(ends, part, OFF, 0, 0);
		}
	}

	/**
		Collects a fade for every FM key on one lead past the span, so each fade lands inside the
		span it belongs to and a span of any length finds the same ones.

		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function fades(fromSample:Int, toSample:Int):Void {
		fading = true;
		gather(fromSample + FADE_LEAD, toSample + FADE_LEAD);
		fading = false;
	}

	/**
		Forgets every key off owed, which is right once the chips have been silenced another way.
	**/
	public function quiets():Void {
		for (index in 0...Part.COUNT) owed[index] = 0;
	}

	/**
		@param song A song.
		@return Its LFO switch and rate packed as register `$22` holds them.
	**/
	static inline function lfoOf(song:Song):Int {
		return (song.lfoOn ? 8 : 0) | (song.lfoRate & 7);
	}

	/**
		Keys off every part owed a key off that is not coming: one due before this span, and, where
		the song may have changed, one whose note is no longer there to end it.

		@param fromSample The first sample of the span.
	**/
	function settle(fromSample:Int):Void {
		final checking = edited;
		edited = false;

		if (checking && lfoSet >= 0 && lfoOf(song) != lfoSet) {
			lfoSet = lfoOf(song);
			push(fromSample, Part.Fm1, SETUP, lfoSet, 0);
		}

		final tick = checking ? song.tempo.tickAt(fromSample) : 0;

		for (index in 0...Part.COUNT) {
			final due = owed[index];
			if (due == 0) continue;

			final part:Part = index;
			final late = due != HELD && due - 1 < fromSample;

			if (!late && !(checking && !still(part, tick, due == HELD))) continue;

			owed[index] = 0;
			push(fromSample, part, OFF, 0, 0);
		}
	}

	/**
		@param track A track.
		@return Whether the notes on it are sounded: it is heard in the mix, and it is the track a
			track stem is of where one is being rendered.
	**/
	inline function heard(track:mdd.song.Track):Bool {
		return sounds(track) && (onlyTrack < 0
			|| (onlyTrack < song.tracks.length && song.tracks[onlyTrack] == track));
	}

	/**
		@param track A track.
		@return Whether it is heard in the mix, by its mute and by every track's solo as they stood
			at the start of the span.
	**/
	inline function sounds(track:mdd.song.Track):Bool {
		return soloTracks ? track.soloed : !track.muted;
	}

	/**
		@param part Which part.
		@param tick Where the playhead is.
		@param held Whether the note sounds until the next one, so that any note started before
			the playhead still counts.
		@return Whether a note on that part is still there at that tick, on a track that is not
			muted and a part the mixer lets through.
	**/
	function still(part:Part, tick:Int, held:Bool):Bool {
		if (!wanted(part)) return false;

		if (alone >= 0) {
			final pattern = song.patternAt(alone);
			return pattern != null && covered(pattern.lane(part), tick, held);
		}

		for (track in song.tracks) {
			if (!heard(track)) continue;

			for (clip in track.clips) {
				if (clip.kind != mdd.song.Clip.PATTERN) continue;
				if (clip.at > tick || clip.ends() <= tick) continue;

				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				if (covered(pattern.lane(part), tick - clip.origin(), held)) return true;
			}
		}

		return false;
	}

	/**
		@param lane The lane to look in.
		@param local A tick inside the pattern.
		@param held Whether any note started at or before it counts, rather than only one that
			has not yet ended.
		@return Whether a note covers that tick.
	**/
	static function covered(lane:mdd.song.Lane, local:Int, held:Bool):Bool {
		for (note in lane.notes) {
			if (note.at > local) break;
			if (held || note.at + note.length > local) return true;
		}

		return false;
	}

	/**
		@param part A part.
		@return Whether this render should sound it, which takes the mixer and both stem
			filters into account.
	**/
	inline function wanted(part:Part):Bool {
		return song.audible(part) && (onlyPart < 0 || part.index() == onlyPart)
			&& (onlyTrack < 0 || (trackParts & (1 << part.index())) != 0);
	}

	/**
		Works out which parts the track a track stem is of plays notes on.
	**/
	function tracked():Void {
		soloTracks = song.soloingTracks();
		moving = false;

		for (instrument in song.instruments) {
			if (instrument.moves() > 0) {
				moving = true;
				break;
			}
		}

		trackParts = 0;
		if (onlyTrack < 0 || onlyTrack >= song.tracks.length) return;

		for (clip in song.tracks[onlyTrack].clips) {
			if (clip.kind != mdd.song.Clip.PATTERN) continue;

			final pattern = song.patternAt(clip.pattern);
			if (pattern == null) continue;

			for (index in 0...Part.COUNT) {
				if (pattern.lanes[index].notes.length > 0) trackParts |= 1 << index;
			}
		}
	}

	/**
		Walks the arrangement and collects every event that falls inside the span.

		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function gather(fromSample:Int, toSample:Int):Void {
		final tempo = song.tempo;

		var low = tempo.tickAt(declick && !fading ? fromSample - SETTLE_REACH : fromSample) - 1;
		if (low < 0) low = 0;

		final high = tempo.tickAt(toSample) + 1;

		drivenParts = 0;

		if (alone >= 0) {
			final pattern = song.patternAt(alone);
			if (pattern != null) {
				walk(pattern, 0, 0, pattern.length, 0, low, high, fromSample, toSample);
			}

			return;
		}

		for (track in song.tracks) {
			if (!sounds(track)) continue;

			for (clip in track.clips) {
				if (clip.automates() && clip.part >= 0 && clip.part < Part.COUNT) {
					drivenParts |= 1 << clip.part;
				}
			}
		}

		for (track in song.tracks) {
			if (!heard(track)) continue;

			var index = 0;

			while (index < track.clips.length) {
				final clip = track.clips[index];
				index++;

				if (clip.kind == mdd.song.Clip.AUTOMATION) continue;

				var until = clip.ends();

				while (index < track.clips.length
						&& follows(clip, track.clips[index], until)) {
					until = track.clips[index].ends();
					index++;
				}

				if (clip.at > high || until <= low) continue;

				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				walk(pattern, clip.origin(), clip.at, until, clip.transpose, low, high,
					fromSample, toSample);
			}
		}

		if (drivenParts == 0 || fading) return;

		for (track in song.tracks) {
			if (!sounds(track)) continue;

			for (clip in track.clips) {
				if (clip.at > high || clip.ends() <= low) continue;
				if (!clip.automates()) continue;

				drove(clip, low, high, fromSample, toSample);
			}
		}
	}

	/**
		@param part Which part.
		@param target Which parameter.
		@param slot Which operator, or -1 for any.
		@param tick A tick on the playlist.
		@return The automation clip driving that lane of the part over the tick, or null where
			none does. Nothing does while a pattern plays alone, which is when no clip writes
			either, and where two clips cover the same tick the one furthest down the playlist
			answers.
	**/
	function driverOf(part:Part, target:Int, slot:Int, tick:Int):Null<mdd.song.Clip> {
		if (alone >= 0) return null;

		var found:Null<mdd.song.Clip> = null;

		for (track in song.tracks) {
			if (!sounds(track)) continue;

			for (clip in track.clips) {
				if (!clip.automates() || clip.part != part.index()) continue;
				if (clip.at > tick || clip.ends() <= tick) continue;

				final line = clip.line;
				if (line == null || line.points.length == 0 || line.target != target) continue;
				if (slot >= 0 && line.slot != slot) continue;

				found = clip;
			}
		}

		return found;
	}

	/**
		@param part Which part.
		@param tick A tick on the playlist where a voice ends.
		@param slice The voice, among the ones resolved for the lane being sounded.
		@param origin Where that lane's pattern starts on the playlist.
		@return Whether another note keys the part on exactly there: the next voice in the same
			lane, or a note in any clip playing the part from that tick, which is how a note at the
			start of one bar follows the last note of the bar before.
	**/
	function struckAt(part:Part, tick:Int, slice:Int, origin:Int):Bool {
		if (slice + 1 < voices.count && origin + voices.startAt(slice + 1) == tick) return true;
		if (alone >= 0) return false;

		for (track in song.tracks) {
			if (!heard(track)) continue;

			for (clip in track.clips) {
				if (clip.kind != mdd.song.Clip.PATTERN) continue;
				if (clip.at > tick || clip.ends() <= tick) continue;

				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				final local = tick - clip.origin();
				final lane = pattern.lane(part);
				final found = lane.seek(local);

				if (found < lane.notes.length && lane.notes[found].at == local) return true;
			}
		}

		return false;
	}

	/**
		@param part Which part.
		@param lane The lane the note is in.
		@param local Where the note starts in that lane.
		@param tick Where it starts on the playlist.
		@param driven Whether any automation clip drives the part.
		@return Whether a square or the noise channel has a level lane over the note, in its own
			pattern or in a clip driving it. The level that lane holds where the note starts is
			written in place of the loudness the key on would write, which would otherwise land
			after it and put the note back at its full level for a frame.
	**/
	function levelled(part:Part, lane:mdd.song.Lane, local:Int, tick:Int, driven:Bool):Bool {
		if (!part.square() && !part.noise()) return false;

		for (line in lane.automation) {
			if (line.held(mdd.song.Automation.LEVEL, 0) && line.points.length > 0) return true;
		}

		return driven && driverOf(part, mdd.song.Automation.LEVEL, 0, tick) != null;
	}

	/**
		Collects the level every level lane over a note holds where it keys on, so the note starts
		at that level rather than at its instrument's own until the lane next moves. A key on loads
		the whole preset, and a level lane holds from one note to the next the way a total level
		does on the chip. A point exactly where the note starts is left to be written where it
		sits.

		@param part Which part.
		@param local Where the note starts in its lane.
		@param tick Where it starts on the playlist.
		@param at The sample it keys on at.
		@param driven Whether any automation clip drives the part.
		@param transpose Semitones to shift every note by.
		@param pitch The note, before the transpose.
		@param velocity Its velocity, 0 to 127.
		@param named Which instrument it plays.
	**/
	function keyedLevels(part:Part, local:Int, tick:Int, at:Int, driven:Bool, transpose:Int, pitch:Int,
			velocity:Int, named:Int):Void {
		if (!part.fm() && !part.square() && !part.noise()) return;

		for (slot in 0...(part.fm() ? 4 : 1)) {
			final clip = driven ? driverOf(part, mdd.song.Automation.LEVEL, slot, tick) : null;
			final line = clip == null ? lines[slot] : clip.line;
			if (line == null || line.points.length == 0) continue;

			final within = clip == null ? local : tick - clip.at;
			if (line.marks(within)) continue;

			lined(at, part, line, line.valueAt(within), transpose, pitch, velocity, named);
		}
	}

	/**
		Collects what the automation clips driving an FM part's operators hold where a note keys
		on, which is what the note starts on in place of its patch's own values, the same as a
		lane in the note's own pattern.

		@param part An FM part.
		@param tick Where the note starts on the playlist.
		@param at The sample it keys on at.
	**/
	function operated(part:Part, tick:Int, at:Int):Void {
		for (track in song.tracks) {
			if (!sounds(track)) continue;

			for (clip in track.clips) {
				if (!clip.automates() || clip.part != part.index()) continue;
				if (clip.at > tick || clip.ends() <= tick) continue;

				final line = clip.line;
				if (line == null || line.points.length == 0) continue;
				if (!mdd.song.Automation.operates(line.target)) continue;
				if (line.target == mdd.song.Automation.LEVEL) continue;
				if (driverOf(part, line.target, line.slot, tick) != clip) continue;

				push(at, part, TWEAK, (line.slot << 8) | (line.heldAt(tick - clip.at) & 0xFF),
					2 + line.target);
			}
		}
	}

	var underTranspose:Int = 0;
	var underLane:Null<mdd.song.Lane> = null;
	var reading:Null<mdd.song.Lane> = null;

	/**
		@param part Which part.
		@param tick A tick.
		@return The note sounding on that part at that tick, or null for none. An FM note still
			sounds in its release after it ends; a square's or the noise channel's does not.
	**/
	function noteUnder(part:Part, tick:Int):Null<mdd.song.Note> {
		var found:Null<mdd.song.Note> = null;
		var ended = false;
		underTranspose = 0;
		underLane = null;

		for (track in song.tracks) {
			if (!heard(track)) continue;

			for (clip in track.clips) {
				if (clip.kind != mdd.song.Clip.PATTERN) continue;
				if (clip.at > tick || clip.ends() <= tick) continue;

				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				final local = tick - clip.origin();
				final lane = pattern.lane(part);
				final last = lane.seek(local + 1) - 1;
				if (last < 0) continue;

				final note = lane.notes[last];

				found = note;
				ended = note.ends() <= local;
				underTranspose = clip.transpose;
				underLane = lane;
			}
		}

		if (ended && !part.fm()) found = null;

		return found;
	}

	/**
		Collects the automation a clip drives on a part it does not otherwise own.

		@param clip The clip being read.
		@param low The first tick of the clip inside the span.
		@param high One past the last.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function drove(clip:mdd.song.Clip, low:Int, high:Int, fromSample:Int,
			toSample:Int):Void {
		final line = clip.line;
		if (line == null || line.points.length == 0) return;

		final part:Part = clip.part;
		if (!wanted(part)) return;

		final tempo = song.tempo;
		final riding = rides(part, line);

		var head = low - clip.at;
		if (head < 0) head = 0;

		final tail = high - clip.at + 1;

		var index = line.seek(head);
		if (index > 0) index--;

		wroteUnder = -2;

		while (index < line.points.length) {
			final point = line.points[index];
			if (point.at > tail) break;

			index++;

			final at = tempo.samplesAt(clip.at + point.at);

			if (at >= fromSample && at < toSample) {
				drives(at, part, line, point.value, clip.at + point.at, riding);
			}

			if (!mdd.song.Automation.moves(point.shape)) continue;
			if (index >= line.points.length) continue;

			ramping(clip, part, line, point, line.points[index], riding, fromSample,
				toSample);
		}
	}

	/**
		Collects the steps of one automation ramp between two points.

		@param clip The clip being read.
		@param part Which part it plays on.
		@param line The automation lane being read.
		@param from The point the ramp starts at.
		@param to The point it reaches.
		@param riding Whether the lane rides a sounding note rather than setting up a new one.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function ramping(clip:mdd.song.Clip, part:Part, line:mdd.song.Automation,
			from:mdd.song.Point, to:mdd.song.Point, riding:Bool, fromSample:Int,
			toSample:Int):Void {
		final tempo = song.tempo;
		final rate = song.tempo.rate < 1 ? 60 : song.tempo.rate;
		final step = Std.int(Tempo.TICKS / rate);
		if (step < 1) return;

		final head = tempo.samplesAt(clip.at + from.at);
		final ends = tempo.samplesAt(clip.at + to.at);
		if (ends <= head) return;

		var when = head + step;
		if (when < fromSample) when += Std.int((fromSample - when) / step) * step;

		var was = mdd.song.Automation.between(from, to, tempo.tickAt(when - step) - clip.at);

		while (when < ends && when < toSample) {
			final tick = tempo.tickAt(when) - clip.at;
			final value = mdd.song.Automation.between(from, to, tick);

			if (value != was) {
				was = value;
				if (when >= fromSample) drives(when, part, line, value, clip.at + tick, riding);
			}

			when += step;
		}
	}

	/**
		Records one automation write as an event.

		@param at The sample it happens at.
		@param part Which part it plays on.
		@param line The automation lane being read.
		@param value The value the lane holds there.
		@param tick The tick it happens at.
		@param riding Whether the lane rides a sounding note.
	**/
	function drives(at:Int, part:Part, line:mdd.song.Automation, value:Int, tick:Int,
			riding:Bool):Void {
		final note = riding ? noteUnder(part, tick) : null;

		if (note == null) {
			if (riding) return;
			lined(at, part, line, value, 0, -1, -1, -1);
			return;
		}

		if (value == wroteValue && wroteUnder == note.pitch) return;

		wroteValue = value;
		wroteUnder = note.pitch;

		lined(at, part, line, value, underTranspose, note.pitch, note.velocity,
			chosen(underLane, part, note.instrument, note.at));
	}

	/**
		@param head The clip a run of them started with.
		@param next The clip after it on the same track.
		@param until Where the run reaches so far, in ticks.
		@return Whether the next clip carries the run on rather than starting one of its
			own: the same pattern, the same transpose, beginning exactly where the run
			reaches, and reading that pattern from exactly where the run left off.

		That is the shape a cut leaves behind, and walking the two as one is what keeps a
		cut from restarting the music. Two copies of the same pattern laid side by side
		both read it from their own start, so they do not join and each sounds on its
		own, which is what somebody who placed two of them asked for.
	**/
	static function follows(head:mdd.song.Clip, next:mdd.song.Clip,
			until:Int):Bool {
		if (next.kind == mdd.song.Clip.AUTOMATION) return false;
		if (next.pattern != head.pattern) return false;
		if (next.transpose != head.transpose) return false;
		if (next.at != until) return false;

		return next.origin() == head.origin();
	}

	/**
		Walks one pattern and collects every lane in it.

		@param pattern The pattern to read.
		@param origin Where the pattern starts on the playlist, in ticks: its clip's position less
			how far into the pattern the clip reads.
		@param from The first tick inside the pattern to read.
		@param until One past the last.
		@param transpose Semitones to shift every note by.
		@param low The first tick of the span, in ticks.
		@param high One past the last.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function walk(pattern:mdd.song.Pattern, origin:Int, from:Int, until:Int, transpose:Int,
			low:Int, high:Int, fromSample:Int, toSample:Int):Void {
		if (from > high || until <= low) return;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (!wanted(part)) continue;
			if (fading && !part.fm()) continue;

			final lane = pattern.lane(part);
			if (lane.notes.length == 0 && lane.automation.length == 0) continue;

			final least = from - origin;
			var head = low - origin;
			if (head < least) head = least;

			voices.resolve(lane, head, high - origin + 1);
			sound(lane, origin, from, until, transpose, part, fromSample, toSample);
			if (!fading) tweaked(lane, origin, part, head, high - origin + 1, transpose, fromSample, toSample);
			if (moving && !fading) moved(lane, origin, from, until, transpose, part, fromSample, toSample);
		}
	}

	/**
		Collects what the presets a lane's notes play move over the span: every lane a preset
		carries, read from its note's key on until the part's next note, or on an FM part on through
		the release until the lane ends or `TAIL` has passed. A lane the pattern or a clip driving
		the part already automates is theirs rather than the preset's, and a tied note goes on
		reading from where its run of notes keyed on, the way a square's envelope does.

		@param lane The lane to read.
		@param origin Where the pattern starts on the playlist, in ticks.
		@param from The first tick of the pattern to read.
		@param until One past the last.
		@param transpose Semitones to shift every note by.
		@param part Which part it plays on.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function moved(lane:mdd.song.Lane, origin:Int, from:Int, until:Int, transpose:Int, part:Part,
			fromSample:Int, toSample:Int):Void {
		if (lane.notes.length == 0) return;
		if (!part.fm() && !part.square() && !part.noise()) return;

		final tempo = song.tempo;
		final back = part.fm() && fromSample > TAIL ? fromSample - TAIL : (part.fm() ? 0 : fromSample);

		var head = tempo.tickAt(back) - 1 - origin;
		if (head < from - origin) head = from - origin;

		reaching.policy = voices.policy;
		reaching.resolve(lane, head, tempo.tickAt(toSample) + 2 - origin);

		final driven = (drivenParts & (1 << part.index())) != 0;

		for (slice in 0...reaching.count) {
			var start = origin + reaching.startAt(slice);
			var ends = origin + reaching.endAt(slice);

			if (start < from) start = from;
			if (ends > until) ends = until;
			if (ends <= start) continue;

			final named = chosen(lane, part, reaching.instrumentAt(slice), reaching.startAt(slice));
			final instrument = instrumentOf(named, part);
			if (instrument == null || instrument.lanes.length == 0) continue;

			final onSample = tempo.samplesAt(start);
			var stop = part.fm() ? tempo.samplesAt(ends) + TAIL : tempo.samplesAt(ends);

			if (slice + 1 < reaching.count) {
				final next = tempo.samplesAt(origin + reaching.startAt(slice + 1));
				if (next < stop) stop = next;
			}

			if (stop <= fromSample || onSample >= toSample) continue;

			final tied = (part.fm() || part.square()) && reaching.tiedAt(slice);
			final first = tied ? tiedFrom(lane, reaching.startAt(slice)) : null;
			final clock = first == null ? onSample : tempo.samplesAt(origin + first.at);

			for (line in instrument.lanes) {
				if (!movable(part, line) || line.points.length == 0) continue;
				if (claimed(lane, part, line, start, driven)) continue;

				swept(line, part, clock, onSample, stop,
					!tied && line.target != mdd.song.Automation.PITCH, transpose,
					reaching.pitchAt(slice), reaching.velocityAt(slice), named, fromSample, toSample);
			}
		}
	}

	/**
		Collects one lane a preset carries over part of a note, inside the span: its value where that
		part starts, where that is a key on, and then every change of value, read every `LANE_STEP`
		from the key on.

		@param line The lane.
		@param part Which part it plays on.
		@param clock Where the note, or the run of tied notes it belongs to, keyed on, which the
			lane is read from.
		@param onSample Where this part of the note starts.
		@param stop Where the lane stops being read.
		@param opens Whether to write the lane's value where this part starts.
		@param transpose Semitones to shift every note by.
		@param pitch The note, before the transpose.
		@param velocity Its velocity, 0 to 127.
		@param named Which instrument it plays.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function swept(line:mdd.song.Automation, part:Part, clock:Int, onSample:Int, stop:Int, opens:Bool,
			transpose:Int, pitch:Int, velocity:Int, named:Int, fromSample:Int, toSample:Int):Void {
		final reach = line.reach();
		final lasts = reach < 0 ? stop : sampleOf(line, clock, reach) + LANE_STEP;
		final ends = stop < toSample ? (stop < lasts ? stop : lasts) : (toSample < lasts ? toSample : lasts);

		movingFrom = clock;

		if (opens && onSample >= fromSample && onSample < toSample) {
			lined(onSample, part, line, laneAt(line, clock, onSample), transpose, pitch, velocity, named);
		}

		var step = Std.int((onSample - clock) / LANE_STEP) + 1;
		final least = fromSample - clock;

		if (step * LANE_STEP < least) step = Std.int((least + LANE_STEP - 1) / LANE_STEP);

		final bends = line.target == mdd.song.Automation.PITCH;

		var when = clock + step * LANE_STEP;
		var was = laneAt(line, clock, when - LANE_STEP < onSample ? onSample : when - LANE_STEP);
		var wrote = bends ? pitchWord(part, was, pitch, transpose) : 0;

		while (when < ends) {
			final value = laneAt(line, clock, when);

			if (value != was) {
				was = value;

				final word = bends ? pitchWord(part, value, pitch, transpose) : 0;

				if (!bends || word != wrote) {
					wrote = word;
					lined(when, part, line, value, transpose, pitch, velocity, named);
				}
			}

			when += LANE_STEP;
		}

		movingFrom = -1;
	}

	/**
		@param line A lane a preset carries.
		@param clock Where its note keyed on.
		@param when A sample.
		@return What the lane holds there, following its curves and going round its loop.
	**/
	function laneAt(line:mdd.song.Automation, clock:Int, when:Int):Int {
		final tempo = song.tempo;
		final elapsed = line.synced
			? Math.floor((tempo.ticksAt(when) - tempo.ticksAt(clock)) * mdd.song.Automation.BEAT / tempo.ppqn)
			: Math.floor((when - clock) * 1000.0 / Tempo.TICKS);

		return line.valueAt(line.looped(elapsed));
	}

	/**
		@param line A lane a preset carries.
		@param clock Where its note keyed on.
		@param at A place on the lane, in its own units.
		@return The sample that place falls on.
	**/
	function sampleOf(line:mdd.song.Automation, clock:Int, at:Int):Int {
		if (!line.synced) return clock + Math.ceil(at * Tempo.TICKS / 1000.0);

		final tempo = song.tempo;
		final tick = Math.ceil(tempo.ticksAt(clock) + at * tempo.ppqn / mdd.song.Automation.BEAT);

		return tempo.samplesAt(tick);
	}

	/**
		@param part Which part.
		@param line A lane a preset carries.
		@return Whether a preset may move that on that part: any FM parameter but the pattern's own
			pitch and the preset lane, a square's pitch, and the noise channel's mode. A square's and
			the noise channel's level is its envelope's.
	**/
	static inline function movable(part:Part, line:mdd.song.Automation):Bool {
		final target = line.target;

		if (part.fm()) {
			return target != mdd.song.Automation.TUNE && target != mdd.song.Automation.INSTRUMENT
				&& target < mdd.song.Automation.BASES.length;
		}

		if (part.square()) return target == mdd.song.Automation.PITCH;
		return part.noise() && target == mdd.song.Automation.TUNE;
	}

	/**
		@param lane The lane the note is in.
		@param part Which part it plays on.
		@param line A lane a preset carries.
		@param tick Where the note starts on the playlist.
		@param driven Whether any automation clip drives the part.
		@return Whether the pattern or a clip driving the part automates what that lane moves, which
			then belongs to them: a pitch lane of either takes a preset's pitch.
	**/
	function claimed(lane:mdd.song.Lane, part:Part, line:mdd.song.Automation, tick:Int,
			driven:Bool):Bool {
		final pitch = line.target == mdd.song.Automation.PITCH;
		final target = pitch ? mdd.song.Automation.TUNE : line.target;
		final slot = pitch ? 0 : line.slot;

		for (held in lane.automation) {
			if (held.held(target, slot) && held.points.length > 0) return true;
		}

		if (!driven) return false;

		return driverOf(part, target, mdd.song.Automation.operates(target) ? slot : -1, tick) != null;
	}

	/**
		@param part Which part.
		@param named Which instrument a note plays.
		@return The pitch lane that instrument carries, where it has one the part takes, or null.
	**/
	function bendOf(part:Part, named:Int):Null<mdd.song.Automation> {
		if (!part.fm() && !part.square()) return null;

		final instrument = instrumentOf(named, part);
		if (instrument == null) return null;

		final line = instrument.lane(mdd.song.Automation.PITCH, 0);
		return line == null || line.points.length == 0 ? null : line;
	}

	/**
		@param part Which part.
		@param cents How far from the note, in hundredths of a semitone.
		@param pitch The note, before the transpose.
		@param transpose Semitones to shift every note by.
		@return What a preset's pitch lane writes: the FM block and frequency word, or the square
			period, of the note that far away, laid out the way the note table lays a note out so a
			key scale and a detune read the same as they do on a note. -1 for no note.
	**/
	function pitchWord(part:Part, cents:Int, pitch:Int, transpose:Int):Int {
		if (pitch < 0) return -1;

		final note = pitched(pitch, transpose);
		if (cents == 0) return part.fm() ? Stream.wordOf(note) : Stream.periodOf(note);

		var whole = note * 100 + cents;
		if (whole < 0) whole = 0;
		if (whole > 12700) whole = 12700;

		final base = Std.int(whole / 100);
		final left = whole - base * 100;

		if (!part.fm()) {
			final period = Math.round(Stream.periodOf(base) * Math.pow(2, -left / 1200.0));
			return period < 1 ? 1 : (period > 0x3FF ? 0x3FF : period);
		}

		final found = Math.round(Stream.frequencyOf(base) * Math.pow(2, left / 1200.0));
		return ((Stream.blockOf(base) & 7) << 11) | (found > 0x7FF ? 0x7FF : found);
	}

	/**
		Resolves one lane into voices and collects a key on, a tune and a key off for
		each of them.

		Where the converter is a kit, a note on a key the kit has nothing rooted at is
		passed over whole rather than sounded on whatever the rack holds. It reaches
		the chip with nothing at all, not even the write that returns the converter to
		the middle, so an imported drum track keeps the keys the file wrote and the
		ones general midi leaves empty stay quiet.

		@param lane The lane to read.
		@param origin Where the pattern starts on the playlist, in ticks: its clip's position less
			how far into the pattern the clip reads.
		@param from The first tick to read.
		@param until One past the last.
		@param transpose Semitones to shift every note by.
		@param part Which part it plays on.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function sound(lane:mdd.song.Lane, origin:Int, from:Int, until:Int, transpose:Int, part:Part,
			fromSample:Int, toSample:Int):Void {
		final tempo = song.tempo;
		var sided:Null<mdd.song.Automation> = null;
		var bent:Null<mdd.song.Automation> = null;

		for (slot in 0...4) lines[slot] = null;

		for (line in lane.automation) {
			if (line.target == mdd.song.Automation.SIDES) {
				if (part.fm() && sided == null) sided = line;
				continue;
			}

			if (line.target == mdd.song.Automation.TUNE) {
				if (line.slot == 0 && bent == null) bent = line;
				continue;
			}

			if (line.target != mdd.song.Automation.LEVEL) continue;
			if (line.slot >= 0 && line.slot < 4) lines[line.slot] = line;
		}

		final driven = (drivenParts & (1 << part.index())) != 0;

		for (slice in 0...voices.count) {
			var start = origin + voices.startAt(slice);
			var ends = origin + voices.endAt(slice);

			if (start < from) start = from;
			if (ends > until) ends = until;
			if (ends <= start) continue;

			final local = start - origin;
			final legato = part.fm() || part.square();
			final tied = legato && voices.tiedAt(slice);
			final held = legato && voices.heldAt(slice);

			final onSample = tempo.samplesAt(start);

			if (fading) {
				if (!tied && onSample >= fromSample && onSample < toSample && attacksFast(chosen(lane,
						part, voices.instrumentAt(slice), voices.startAt(slice)), part)) {
					push(onSample - FADE_LEAD, part, OFF, 0, FADE);
				}

				continue;
			}

			final starting = onSample >= fromSample && onSample < toSample;
			final ending = tempo.samplesAt(ends);
			final early = ending - GUARD;
			final offSample = !held && part.fm() && ending - onSample > GUARD * 2
				&& (starting || (ending >= fromSample && early < toSample))
				&& struckAt(part, ends, slice, origin) ? early : ending;
			final pitch = voices.pitchAt(slice) + transpose;
			final velocity = louder(part, voices.velocityAt(slice));
			final named = chosen(lane, part, voices.instrumentAt(slice), voices.startAt(slice));

			if (part.sampled() && song.drums && song.drumAt(pitch) < 0) continue;

			final bender = driven && (starting || part.sampled())
				? driverOf(part, mdd.song.Automation.TUNE, 0, start) : null;
			final tuning = bender == null ? bent : bender.line;
			final tunedAt = bender == null ? local : start - bender.at;

			if (starting) {
				if (!tied) {
					push(onSample, part, PATCH, named,
						tuning != null && part.noise() ? -1 : velocity);

					if (part.fm()) {
						final sider = driven
							? driverOf(part, mdd.song.Automation.SIDES, -1, start) : null;

						push(onSample, part, TWEAK, sider == null ? spread(part, sided, local, named)
							: spread(part, sider.line, start - sider.at, named), 1);

						for (line in lane.automation) {
							if (!mdd.song.Automation.operates(line.target)) continue;
							if (line.target == mdd.song.Automation.LEVEL) continue;
							if (driven && driverOf(part, line.target, line.slot, start) != null) continue;

							final want = line.heldAt(local);
							if (want < 0) continue;

							push(onSample, part, TWEAK, (line.slot << 8) | (want & 0xFF),
								2 + line.target);
						}

						if (driven) operated(part, start, onSample);
					}
				}

				final bend = moving && tuning == null ? bendOf(part, named) : null;

				if (bend != null && !claimed(lane, part, bend, start, driven)) {
					final head = tied ? tiedFrom(lane, voices.startAt(slice)) : null;

					movingFrom = head == null ? onSample : tempo.samplesAt(origin + head.at);
					lined(onSample, part, bend, laneAt(bend, movingFrom, onSample), transpose,
						voices.pitchAt(slice), voices.velocityAt(slice), named);
					movingFrom = -1;
				} else if (tuning == null || !rides(part, tuning)) {
					push(onSample, part, TUNE, pitch, 0);
				} else {
					final offset = tuning.heldAt(tunedAt);
					final want = voices.pitchAt(slice);

					if (part.fm()) {
						push(onSample, part, TUNE, worded(offset, want, transpose), 1);
					} else push(onSample, part, TUNE, periodic(offset, want, transpose), 2);
				}

				if (!tied && !(part.sampled() && tuning != null)
						&& !levelled(part, lane, local, start, driven)) {
					push(onSample, part, ON, velocity, named);
				}

				if (!tied) {
					keyedLevels(part, local, start, onSample, driven, transpose, voices.pitchAt(slice),
						voices.velocityAt(slice), named);
				}

				if (!part.sampled()) {
					final was = owed[part.index()];
					final due = held ? HELD : offSample + 1;

					owed[part.index()] = was == HELD || due == HELD ? due : (due > was ? due : was);
				}

			}

			final letGo = part.sampled() ? sampled(onSample, offSample, named, pitch,
				declick && struckAt(part, ends, slice, origin), fromSample, toSample) : offSample;

			if (!held && letGo >= fromSample && letGo < toSample
					&& !(part.sampled() && tuning != null)) {
				push(letGo, part, OFF, 0, stuck && part.fm() && !releases(named, part) ? HUSH : 0);
			}

			if ((part.square() || part.noise()) && lines[0] == null
					&& !(driven && driverOf(part, mdd.song.Automation.LEVEL, 0, start) != null)) {
				final head = tied ? tiedFrom(lane, voices.startAt(slice)) : null;

				if (head == null) {
					shaped(onSample, offSample, part, named, velocity, fromSample, toSample);
				} else {
					shaped(tempo.samplesAt(origin + head.at), offSample, part,
						chosen(lane, part, head.instrument, head.at), louder(part, head.velocity),
						onSample > fromSample ? onSample : fromSample, toSample);
				}
			}
		}
	}

	/**
		@param part Which part.
		@param line The automation lane being read.
		@return True where that lane is one the part can actually take.
	**/
	inline function carries(part:Part, line:mdd.song.Automation):Bool {
		final level = line.target == mdd.song.Automation.LEVEL;
		final tune = line.target == mdd.song.Automation.TUNE;

		final shaping = part.fm() && mdd.song.Automation.operates(line.target) && !level;

		if (!level && !tune && !shaping
			&& line.target != mdd.song.Automation.SIDES) return false;

		return part.fm() || level || tune;
	}

	/**
		Turns one automation value into the register write it means, which depends on
		which lane it is and on what the part is playing.

		@param at The sample it happens at.
		@param part Which part it plays on.
		@param line The automation lane being read.
		@param value The value the lane holds.
		@param transpose Semitones to shift every note by.
		@param pitch The note sounding, for a lane that bends it.
		@param velocity The velocity sounding, for a lane that scales it.
		@param named Which instrument the note plays.
	**/
	function lined(at:Int, part:Part, line:mdd.song.Automation, value:Int, transpose:Int,
			pitch:Int, velocity:Int, named:Int):Void {
		if (line.target == mdd.song.Automation.INSTRUMENT) return;

		if (line.target == mdd.song.Automation.PITCH) {
			final word = pitchWord(part, value, pitch, transpose);
			if (word < 0) return;

			if (part.fm()) push(at, part, TUNE, word, 1);
			else if (part.square()) push(at, part, TUNE, word, 2);

			return;
		}

		final level = line.target == mdd.song.Automation.LEVEL;
		final tune = line.target == mdd.song.Automation.TUNE;

		final shaping = part.fm() && mdd.song.Automation.operates(line.target) && !level;

		if (shaping) {
			push(at, part, TWEAK, (line.slot << 8) | (value & 0xFF), 2 + line.target);
			return;
		}

		if (level) {
			final want = attenuated(part, line.slot, value, velocity, named);

			if (part.fm()) push(at, part, TWEAK, (line.slot << 8) | (want & 0x7F), 0);
			else push(at, part, DATA, want & 0x0F, PSG_STEP);

			return;
		}

		if (!tune) {
			push(at, part, TWEAK, masked(part, value), 1);
			return;
		}

		if (part.sampled()) push(at, part, TUNE, value, 5);
		else if (part.noise()) push(at, part, TUNE, value & 0x0F, 4);
		else if (!part.fm()) push(at, part, TUNE, periodic(value, pitch, transpose), 2);
		else if (line.slot > 0) {
			push(at, part, TUNE, (line.slot << 14) | shifted(value, transpose), 3);
		} else push(at, part, TUNE, worded(value, pitch, transpose), 1);
	}

	/**
		@param part Which part.
		@param line The automation lane being read.
		@return True where that lane changes a note already sounding rather than setting one up.
	**/
	inline function rides(part:Part, line:mdd.song.Automation):Bool {
		if (line.target == mdd.song.Automation.LEVEL) return true;

		return line.target == mdd.song.Automation.TUNE && line.slot == 0
			&& (part.fm() || part.square());
	}

	/**
		@param pitch A MIDI note number.
		@param transpose Semitones to shift every note by.
		@return It transposed and held to 0 to 127.
	**/
	inline function pitched(pitch:Int, transpose:Int):Int {
		final want = pitch + transpose;
		return want < 0 ? 0 : (want > 127 ? 127 : want);
	}

	/**
		@param offset A recorded tuning offset in frequency word units.
		@param pitch The note sounding.
		@param transpose Semitones to shift every note by.
		@return The FM block and frequency word to write.
	**/
	function worded(offset:Int, pitch:Int, transpose:Int):Int {
		if (pitch < 0) return offset & 0x3FFF;

		return Tuning.word(offset, pitched(pitch, transpose));
	}

	/**
		@param offset A recorded tuning offset in period units.
		@param pitch The note sounding.
		@param transpose Semitones to shift every note by.
		@return The square period to write.
	**/
	function periodic(offset:Int, pitch:Int, transpose:Int):Int {
		if (pitch < 0) return offset & 0x3FF;

		final want = Stream.periodOf(pitched(pitch, transpose)) + offset;
		return want < 0 ? 0 : (want > 0x3FF ? 0x3FF : want);
	}

	/**
		@param part Which part it plays on.
		@param slot Which operator, 0 to 3.
		@param offset The automated total level.
		@param velocity The velocity sounding.
		@param named Which instrument the note plays.
		@return The total level to write, which is the automated one for a modulator and the
			velocity scaled one for a carrier.
	**/
	function attenuated(part:Part, slot:Int, offset:Int, velocity:Int, named:Int):Int {
		if (velocity < 0) return part.fm() ? (offset & 0x7F) : (offset & 0x0F);

		final want = louder(part, velocity);

		if (!part.fm()) {
			final held = Velocity.quiets(want) + offset;
			return held < 0 ? 0 : (held > 15 ? 15 : held);
		}

		final instrument = instrumentOf(named, part);
		final patch = instrument == null ? null : instrument.patch;

		if (patch == null) return offset & 0x7F;

		final held = Stream.levelOf(patch, slot, want) + offset;
		return held < 0 ? 0 : (held > 127 ? 127 : held);
	}

	/**
		@param tick A tick.
		@return Whether a note begins on it.
	**/
	inline function starts(tick:Int):Bool {
		final under = sounding(tick);
		return under >= 0 && voices.startAt(under) == tick;
	}

	var wroteValue:Int = 0;
	var wroteUnder:Int = -2;

	/**
		Records one automation value, reading whatever note is sounding under it.

		A lane that rides a note writes nothing where there is no note under it to ride, or where
		a square or the noise channel's note has ended, which would otherwise sound the channel
		again in a rest. The next note's key on writes what the lane holds by then.

		@param at The sample it happens at.
		@param part Which part it plays on.
		@param line The automation lane being read.
		@param value The value the lane holds.
		@param transpose Semitones to shift every note by.
		@param riding Whether the lane rides a sounding note.
		@param tick The tick it happens at.
	**/
	function put(at:Int, part:Part, line:mdd.song.Automation, value:Int, transpose:Int,
			riding:Bool, tick:Int):Void {
		var under = riding ? sounding(tick) : -1;

		if (riding) {
			if (under >= 0 && !part.fm() && voices.endAt(under) <= tick) under = -1;
			if (under < 0) return;
		}

		if (under == wroteUnder && value == wroteValue) return;

		wroteUnder = under;
		wroteValue = value;

		if (under < 0) lined(at, part, line, value, transpose, -1, -1, -1);
		else {
			lined(at, part, line, value, transpose, voices.pitchAt(under),
				voices.velocityAt(under),
				chosen(reading, part, voices.instrumentAt(under), voices.startAt(under)));
		}
	}

	/**
		Collects the steps of one ramp for a lane the part owns.

		@param part Which part it plays on.
		@param line The automation lane being read.
		@param from The point the ramp starts at.
		@param to The point it reaches.
		@param base Where the lane sits in ticks.
		@param transpose Semitones to shift every note by.
		@param riding Whether the lane rides a sounding note.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function ramped(part:Part, line:mdd.song.Automation, from:mdd.song.Point,
			to:mdd.song.Point, base:Int, transpose:Int, riding:Bool, fromSample:Int,
			toSample:Int):Void {
		final tempo = song.tempo;
		final rate = song.tempo.rate < 1 ? 60 : song.tempo.rate;
		final step = Std.int(Tempo.TICKS / rate);
		if (step < 1) return;

		final head = tempo.samplesAt(base + from.at);
		final tail = tempo.samplesAt(base + to.at);
		if (tail <= head) return;

		var when = head + step;
		if (when < fromSample) when += Std.int((fromSample - when) / step) * step;

		var was = mdd.song.Automation.between(from, to,
			tempo.tickAt(when - step) - base);

		while (when < tail && when < toSample) {
			final value = mdd.song.Automation.between(from, to, tempo.tickAt(when) - base);

			if (value != was) {
				was = value;

				if (when >= fromSample) {
					put(when, part, line, value, transpose, riding, tempo.tickAt(when) - base);
				}
			}

			when += step;
		}
	}

	/**
		@param tick A tick.
		@return The sample that tick falls on, through the tempo map.
	**/
	function sounding(tick:Int):Int {
		var found = -1;

		for (slice in 0...voices.count) {
			if (voices.startAt(slice) > tick) break;
			found = slice;
		}

		return found;
	}

	/**
		Collects the per note automation a lane carries, as against a channel wide lane.

		@param lane The lane to read.
		@param origin Where the pattern starts on the playlist, in ticks: its clip's position less
			how far into the pattern the clip reads.
		@param part Which part it plays on.
		@param head The first tick to read.
		@param tail One past the last.
		@param transpose Semitones to shift every note by.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function tweaked(lane:mdd.song.Lane, origin:Int, part:Part, head:Int, tail:Int,
			transpose:Int, fromSample:Int, toSample:Int):Void {
		if (lane.automation.length == 0) return;
		if (!part.fm() && !part.square() && !part.noise() && !part.sampled()) return;

		final tempo = song.tempo;
		reading = lane;

		for (line in lane.automation) {
			if (!carries(part, line)) continue;

			final riding = rides(part, line);

			var index = line.seek(head);
			if (index > 0) index--;

			wroteUnder = -2;

			while (index < line.points.length) {
				final point = line.points[index];
				if (point.at > tail) break;

				index++;

				final at = tempo.samplesAt(origin + point.at);

				if (at >= fromSample && at < toSample
						&& !(riding && line.target == mdd.song.Automation.TUNE && starts(point.at))) {
					put(at, part, line, point.value, transpose, riding, point.at);
				}

				if (!mdd.song.Automation.moves(point.shape)) continue;
				if (index >= line.points.length) continue;

				ramped(part, line, point, line.points[index], origin, transpose, riding,
					fromSample, toSample);
			}
		}
	}

	/**
		Writes everything a part needs to be in the state the song says it is in at a
		position, which is what makes a seek land on the same sound as playing up to it.

		@param stream Where the register writes go.
		@param fromSample The sample being seeked to.
	**/
	public function prime(stream:Stream, fromSample:Int):Void {
		count = 0;
		dropped = 0;

		driver.forget();
		if (paced != null) paced.forget();

		for (index in 0...Part.COUNT) keyedAt[index] = -1;
		reached = fromSample;

		tracked();

		lfoSet = lfoOf(song);
		push(fromSample, Part.Fm1, SETUP, lfoSet, 0);

		final tick = song.tempo.tickAt(fromSample);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (!wanted(part)) continue;

			primed(part, tick, fromSample);
		}

		sort();
		play(stream);
	}

	/**
		Collects the setup events for one part at a position.

		@param part Which part.
		@param tick The tick being seeked to.
		@param at The sample it falls on.
	**/
	function primed(part:Part, tick:Int, at:Int):Void {
		var lane:Null<mdd.song.Lane> = null;
		var local = 0;
		var transpose = 0;

		if (alone >= 0) {
			final pattern = song.patternAt(alone);

			if (pattern != null) {
				lane = pattern.lane(part);
				local = tick;
			}
		} else {
			for (track in song.tracks) {
				if (!heard(track)) continue;

				for (clip in track.clips) {
					if (clip.at > tick || clip.ends() <= tick) continue;

					final pattern = song.patternAt(clip.pattern);
					if (pattern == null) continue;

					final held = pattern.lane(part);
					if (held.notes.length == 0 && held.automation.length == 0) continue;

					lane = held;
					local = tick - clip.origin();
					transpose = clip.transpose;
				}
			}
		}

		var named = song.rack[part.index()];
		var sided:Null<mdd.song.Automation> = null;
		var under:Null<mdd.song.Note> = null;

		if (lane != null) {
			final last = lane.seek(local + 1) - 1;

			if (last >= 0) {
				final note = lane.notes[last];

				named = note.instrument;
				under = note;
			}

			for (line in lane.automation) {
				if (line.target == mdd.song.Automation.SIDES) sided = line;
			}

			named = chosen(lane, part, under == null ? -1 : under.instrument,
				under == null ? local : under.at);
		}

		if (part.fm()) {
			final sider = driverOf(part, mdd.song.Automation.SIDES, -1, tick);
			final clock = under == null ? -1 : song.tempo.samplesAt(tick - local + under.at);

			movingFrom = clock;
			push(at, part, PATCH, named, under == null ? 127 : louder(part, under.velocity));
			movingFrom = -1;

			push(at, part, TWEAK, sider == null ? spread(part, sided, local, named)
				: spread(part, sider.line, tick - sider.at, named), 1);

			if (moving && under != null) {
				restoredLanes(at, part, lane, under, clock, song.tempo.samplesAt(tick - local + under.ends()),
					tick, transpose, named);
			}
		}

		final sounded = under != null && (part.fm() || under.ends() > local) ? under : null;

		if (lane != null) {
			for (line in lane.automation) {
				if (!carries(part, line)) continue;
				if (line.points.length == 0) continue;
				if (driverOf(part, line.target, line.slot, tick) != null) continue;

				restored(at, part, line, local, sounded, transpose, named);
			}
		}

		if (alone >= 0) return;

		for (track in song.tracks) {
			if (!sounds(track)) continue;

			for (clip in track.clips) {
				if (!clip.automates() || clip.part != part.index()) continue;
				if (clip.at > tick || clip.ends() <= tick) continue;

				final line = clip.line;
				if (line == null || !carries(part, line)) continue;
				if (line.points.length == 0) continue;
				if (driverOf(part, line.target, line.slot, tick) != clip) continue;

				restored(at, part, line, tick - clip.at, sounded, transpose, named);
			}
		}
	}

	/**
		Writes what the lanes a note's preset carries hold at a position being seeked to, where the
		position is still inside what they move: before the next note, and no more than `TAIL`
		past the note's end.

		@param at The sample being seeked to.
		@param part An FM part.
		@param lane The lane the note is in.
		@param under The note.
		@param clock Where it keyed on.
		@param ending Where it ends.
		@param tick The tick being seeked to.
		@param transpose Semitones to shift every note by.
		@param named Which instrument it plays.
	**/
	function restoredLanes(at:Int, part:Part, lane:Null<mdd.song.Lane>, under:mdd.song.Note,
			clock:Int, ending:Int, tick:Int, transpose:Int, named:Int):Void {
		final instrument = instrumentOf(named, part);
		if (instrument == null || instrument.lanes.length == 0 || at >= ending + TAIL) return;

		movingFrom = clock;

		for (line in instrument.lanes) {
			if (!movable(part, line) || line.points.length == 0) continue;
			if (lane != null && claimed(lane, part, line, tick, true)) continue;

			lined(at, part, line, laneAt(line, clock, at), transpose, under.pitch, under.velocity, named);
		}

		movingFrom = -1;
	}

	/**
		Writes what one automation lane holds at a position being seeked to, which is what the same
		lane would have written by then had the song played up to it. A lane that rides a note
		writes nothing where no note sounds there.

		@param at The sample being seeked to.
		@param part Which part.
		@param line The lane, from the part's own pattern or from a clip driving it.
		@param within The position in the lane's own ticks.
		@param under The note sounding there, or null for none.
		@param transpose Semitones to shift every note by.
		@param named Which instrument the note plays.
	**/
	function restored(at:Int, part:Part, line:mdd.song.Automation, within:Int,
			under:Null<mdd.song.Note>, transpose:Int, named:Int):Void {
		final riding = rides(part, line);
		final want = riding && line.target == mdd.song.Automation.LEVEL ? line.valueAt(within)
			: line.heldAt(within);

		if (!riding) {
			if (want >= 0) lined(at, part, line, want, transpose, -1, -1, -1);
			return;
		}

		if (under == null) return;

		lined(at, part, line, want, transpose, under.pitch, under.velocity, named);
	}

	/**
		@param part Which part it plays on.
		@param line The lane to read, or null for the instrument default.
		@param tick The tick to read it at.
		@param named Which instrument the note plays.
		@return The value that lane holds there.
	**/
	function spread(part:Part, line:Null<mdd.song.Automation>, tick:Int, named:Int):Int {
		var value = line == null ? -1 : line.heldAt(tick);

		if (value < 0) {
			final instrument = instrumentOf(named, part);
			final patch = instrument == null ? null : instrument.patch;

			value = patch == null ? 0xC0
				: (0xC0 | ((patch.ams & 3) << 4) | (patch.pms & 7));
		}

		return masked(part, value);
	}

	/**
		@param word A packed block and frequency word.
		@param semitones How far to move it.
		@return The word moved by that many semitones, carrying between blocks where it has to.
	**/
	static function shifted(word:Int, semitones:Int):Int {
		final held = word & 0x3FFF;
		if (semitones == 0) return held;

		var block = (held >> 11) & 7;
		var scaled = (held & 0x7FF) * Math.pow(2, semitones / 12.0);

		while (scaled >= 2048 && block < 7) {
			scaled *= 0.5;
			block++;
		}

		while (scaled < 1024 && block > 0) {
			scaled *= 2;
			block--;
		}

		var found = Math.round(scaled);
		if (found > 2047) found = 2047;
		if (found < 0) found = 0;

		return (block << 11) | found;
	}

	/**
		@param part Which part.
		@param value A register value.
		@return It held to the bits that part actually uses.
	**/
	inline function masked(part:Part, value:Int):Int {
		final pan = song.pan[part.index()] & 3;
		return (value & 0x3F) | ((((value >> 6) & pan) & 3) << 6);
	}

	/**
		Collects the sample channel bytes one note plays, at the rate the sample was
		recorded at.

		Where declicking is on, a hit that stops away from the middle returns there over
		`SETTLE`, from where it ran out or from where its note cut it, unless the next hit starts
		exactly where it was cut and takes the converter over.

		@param onSample Where the note begins.
		@param offSample Where it ends.
		@param named Which instrument the note plays.
		@param pitch The note sounding, which is the key a kit is read at.
		@param struck Whether another note keys the converter on exactly where this one ends.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
		@return Where the converter may be let go: where the note ends, or later where the return
			to the middle runs past it.
	**/
	function sampled(onSample:Int, offSample:Int, named:Int, pitch:Int, struck:Bool,
			fromSample:Int, toSample:Int):Int {
		final kit = song.drums ? song.drumAt(pitch) : -1;
		final instrument = kit >= 0 ? song.instrumentAt(kit)
			: instrumentOf(named, Part.Dac);
		if (instrument == null) return offSample;

		final sample = song.sampleAt(instrument.sample);
		if (sample == null || sample.length() == 0) return offSample;

		final held = strikes;

		if (held != null && onSample >= fromSample && onSample < toSample) {
			held.push(onSample);
			held.push(offSample);
			held.push(kit >= 0 ? kit : (named >= 0 ? named : song.rack[Part.Dac.index()]));
		}

		final rate = sample.rate < 1 ? 1 : sample.rate;
		final step = Tempo.TICKS / rate;


		final frame = song.stallEvery < 8 ? 735.0 : song.stallEvery;
		final stalls = song.stallAt >= 0 && song.stallFor > 0;

		var when = onSample + 0.0;

		var next = stalls
			? Math.floor(onSample / frame) * frame + song.stallAt : 0.0;

		if (stalls) while (next < onSample) next += frame;

		var index = 0;
		var playing = false;

		final ahead:Float = fromSample < offSample ? fromSample : offSample;

		while (index < sample.length()) {
			if (stalls && when >= next) {
				when += song.stallFor;
				next += frame;
				continue;
			}

			if (when + 0.5 >= ahead) break;

			when += step;
			index++;
		}

		while (index < sample.length()) {
			if (stalls && when >= next) {
				when += song.stallFor;
				next += frame;
				continue;
			}

			final at = Math.round(when);
			if (at >= offSample) break;

			if (at >= toSample) {
				playing = true;
				break;
			}

			if (at >= fromSample) push(at, Part.Dac, DATA, quieter(sample.bytes[index]),
				DAC_BYTE);

			when += step;
			index++;
		}

		if (!declick || playing || index == 0) return offSample;

		final cut = index < sample.length();
		if (cut && struck) return offSample;

		final last = quieter(sample.bytes[index - 1]);
		if (last == 0x80) return offSample;

		final many = Math.ceil(SETTLE / step);
		var letGo = offSample;

		for (left in 0...many) {
			final at = Math.round(when);
			if (struck && at >= offSample) break;

			if (at >= fromSample && at < toSample) {
				push(at, Part.Dac, DATA, 0x80 + Math.round((last - 0x80) * eased(many - 1 - left, many)),
					DAC_BYTE);
			}

			if (at + 1 > letGo) letGo = at + 1;
			when += step;
		}

		return letGo;
	}

	/**
		@param left How many steps are left after this one.
		@param many How many the whole return takes.
		@return How much of the way from the middle a step that far from the end still stands: a
			half cosine from one down to nought on the last step.
	**/
	static inline function eased(left:Int, many:Int):Float {
		return 0.5 - 0.5 * Math.cos(Math.PI * left / many);
	}

	/**
		@param named Which instrument a note plays.
		@param part Its FM part.
		@return Whether its patch lets go at a key off, which a carrier at `NEVER_RELEASES` or below
			does not.
	**/
	function releases(named:Int, part:Part):Bool {
		final instrument = instrumentOf(named, part);
		final patch = instrument == null ? null : instrument.patch;
		if (patch == null) return true;

		for (slot in 0...4) {
			if (patch.carries(slot) && patch.release[slot] <= NEVER_RELEASES) return false;
		}

		return true;
	}

	/**
		@param named Which instrument a note plays.
		@param part Its FM part.
		@return Whether every carrier of that instrument's patch attacks at `FAST_ATTACK` or faster,
			so a fade before its key on is filled straight back in.
	**/
	function attacksFast(named:Int, part:Part):Bool {
		final instrument = instrumentOf(named, part);
		final patch = instrument == null ? null : instrument.patch;
		if (patch == null) return false;

		for (slot in 0...4) {
			if (patch.carries(slot) && patch.attack[slot] < FAST_ATTACK) return false;
		}

		return true;
	}

	/**
		Finds where a run of tied notes began, which is where a square's envelope started: a tie
		changes the note without starting it again. Allocates nothing.

		@param lane The lane the notes are in.
		@param at Where a tied note starts in that lane.
		@return The first note of the run, or null where no note starts there.
	**/
	function tiedFrom(lane:mdd.song.Lane, at:Int):Null<mdd.song.Note> {
		final notes = lane.notes;
		var index = lane.seek(at);

		if (index >= notes.length || notes[index].at != at) return null;

		while (index > 0 && notes[index].tied && notes[index - 1].ends() >= notes[index].at) index--;

		return notes[index];
	}

	/**
		Collects the steps of a square envelope across one note.

		@param onSample Where the note begins.
		@param offSample Where it ends.
		@param part Which part it plays on.
		@param named Which instrument the note plays.
		@param velocity The velocity it sounds at.
		@param fromSample The first sample of the span.
		@param toSample One past the last sample of the span.
	**/
	function shaped(onSample:Int, offSample:Int, part:Part, named:Int, velocity:Int,
			fromSample:Int, toSample:Int):Void {
		final instrument = instrumentOf(named, part);
		if (instrument == null || instrument.envelope == null) return;

		final envelope = instrument.envelope;
		if (envelope.steps.length == 0) return;

		final speed = envelope.speed < 1 ? 1 : envelope.speed;
		final step = ENVELOPE_TICKS * speed;

		var index = 1;
		if (fromSample > onSample) index = Std.int((fromSample - onSample) / step);
		if (index < 1) index = 1;

		while (true) {
			final at = onSample + index * step;
			if (at >= toSample || at >= offSample) break;

			if (at >= fromSample) {
				push(at, part, DATA, Velocity.quiets(velocity) + envelope.at(index),
					PSG_STEP);
			}

			index++;
		}
	}

	/**
		@param value An attenuation.
		@return It held to the four bits the square part has.
	**/
	inline function quieter(value:Int):Int {
		final held = song.volume[Part.Dac.index()];
		if (held >= Song.LOUDEST) return value;

		final want = 0x80 + Std.int((value - 0x80) * held / Song.LOUDEST);
		return want < 0 ? 0 : (want > 255 ? 255 : want);
	}

	/**
		@param part Which part.
		@param velocity A velocity, 0 to 127.
		@return The attenuation that velocity means on that part.
	**/
	inline function louder(part:Part, velocity:Int):Int {
		return Velocity.scaled(velocity, song.volume[part.index()]);
	}

	/**
		@param named An instrument index, or -1 for the part default.
		@param part Which part.
		@return The instrument, or null where there is none.
	**/
	function instrumentOf(named:Int, part:Part):Null<Instrument> {
		final want = named >= 0 ? named : song.rack[part.index()];
		return song.instrumentAt(want);
	}

	/**
		Which instrument a note plays once the lane's preset automation is read. Runs on the
		render thread and allocates nothing.

		The lane wins over the note from its first point on, because loading a preset into a
		part and writing a note in the tracker both name an instrument on every note, and a
		lane that gave way to them would never be heard. The converter is left to its notes,
		because a kit picks its hit by the instrument each note names.

		@param lane The lane the note is in, or null where there is none.
		@param part Which part the note plays on.
		@param named Which instrument the note names, or -1 for the rack.
		@param tick Where the note starts in the lane, in ticks.
		@return The preset the lane holds at that tick, or what the note names where the lane
			has no point at or before it, holds an index no instrument is at, or the part is
			the converter.
	**/
	function chosen(lane:Null<mdd.song.Lane>, part:Part, named:Int, tick:Int):Int {
		if (lane == null || part.sampled()) return named;

		for (line in lane.automation) {
			if (line.target != mdd.song.Automation.INSTRUMENT) continue;
			if (line.points.length == 0 || line.points[0].at > tick) return named;

			final want = line.heldAt(tick);
			return song.instrumentAt(want) == null ? named : want;
		}

		return named;
	}

	/**
		Adds one event, or counts it in `dropped` where the buffer is full.

		@param tick The sample it happens at.
		@param part Which part it is for.
		@param kind Which event, `OFF` to `SETUP`.
		@param first The first value the event carries.
		@param second The second, where it carries one.
	**/
	function push(tick:Int, part:Part, kind:Int, first:Int, second:Int):Void {
		if (count >= capacity) {
			dropped++;
			return;
		}

		ticks[count] = tick;
		parts[count] = part.index();
		kinds[count] = kind;
		firsts[count] = first;
		seconds[count] = second;
		origins[count] = movingFrom;
		order[count] = count;
		count++;
	}

	/**
		@param left An event index.
		@param right Another.
		@return Whether the first must be played before the second. Events at the same sample are
			ordered by kind, so a key off never lands after the key on that replaced it.
	**/
	inline function before(left:Int, right:Int):Bool {
		if (ticks[left] != ticks[right]) return ticks[left] < ticks[right];
		if (parts[left] != parts[right]) return parts[left] < parts[right];
		if (kinds[left] != kinds[right]) return kinds[left] < kinds[right];
		if (seconds[left] != seconds[right]) return seconds[left] < seconds[right];
		if (firsts[left] != firsts[right]) return firsts[left] < firsts[right];

		return left < right;
	}

	/**
		Sorts the span into playing order, into `order` rather than by moving the events.
	**/
	function sort():Void {
		var start = Std.int(count / 2);

		while (start > 0) {
			start--;
			sift(start, count);
		}

		var ends = count;

		while (ends > 1) {
			ends--;

			final swap = order[0];
			order[0] = order[ends];
			order[ends] = swap;

			sift(0, ends);
		}
	}

	/**
		Sorts one run of the order array.

		@param from The first index.
		@param until One past the last.
	**/
	function sift(from:Int, until:Int):Void {
		var root = from;

		while (root * 2 + 1 < until) {
			var child = root * 2 + 1;

			if (child + 1 < until && before(order[child], order[child + 1])) child++;
			if (!before(order[root], order[child])) return;

			final swap = order[root];
			order[root] = order[child];
			order[child] = swap;

			root = child;
		}
	}

	/**
		Turns every event of the sorted span into register writes.

		@param stream Where those writes go.
	**/
	function play(stream:Stream):Void {
		for (index in 0...count) {
			final at = order[index];

			final tick = ticks[at];
			final part:Part = parts[at];
			final first = firsts[at];
			final second = seconds[at];
			final origin = origins[at];

			if (origin >= 0 && origin < keyedAt[part.index()]) continue;

			switch (kinds[at]) {
				case OFF:
					if (second == FADE) stream.fades(tick, part);
					else {
						if (second == HUSH) stream.fades(tick, part);
						else stream.silence(tick, part);

						final due = owed[part.index()];
						if (due != HELD && tick + 1 >= due) owed[part.index()] = 0;
					}

				case PATCH:
					keyedAt[part.index()] = origin >= 0 ? origin : tick;

					final instrument = instrumentOf(first, part);
					if (instrument != null && instrument.patch != null) {
						stream.patch(tick, part, instrument.patch, second);
					}
					if (part.noise() && second >= 0 && instrument != null
							&& instrument.envelope != null) {
						stream.noise(tick, instrument.envelope.noise, false);
					}

				case TUNE:
					if (second == 5) stream.sampling(tick, first != 0);
					else if (second == 4) stream.noise(tick, first & 0x0F);
					else if (second == 3) {
						stream.operatorFrequency(tick, (first >> 14) & 3, first & 0x3FFF);
					} else if (second == 2) stream.period(tick, part, first);
					else if (second == 1) stream.frequency(tick, part, first);
					else if (part.fm()) stream.tune(tick, part, first);
					else if (part.square()) stream.square(tick, part, first);

				case ON:
					if (part.fm()) stream.keyOn(tick, part);
					else if (part.square() || part.noise()) {
						final instrument = instrumentOf(second, part);
						stream.loudness(tick, part, instrument == null ? null : instrument.envelope,
							first, 0);
					} else if (part.sampled()) stream.sampling(tick, true);

				case DATA:
					if (second == DAC_BYTE) stream.byte(tick, first);
					else stream.attenuate(tick, part, first);

				case TWEAK:
					if (second >= 2) {
						stream.shaping(tick, part, mdd.song.Automation.BASES[second - 2],
							(first >> 8) & 3, first & 0xFF);
					} else if (second == 0) {
						stream.totalLevel(tick, part, (first >> 8) & 3, first & 0x7F);
					} else stream.sides(tick, part, first);

				case SETUP:
					stream.lfo(tick, (first & 8) != 0, first & 7);

				case _:
			}
		}
	}
}
