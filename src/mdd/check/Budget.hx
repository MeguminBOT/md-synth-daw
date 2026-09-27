package mdd.check;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.play.Stream;
import mdd.song.Automation;
import mdd.song.Clip;
import mdd.song.Lane;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Song;

@:unreflective

/**
	What the song is asking of the hardware, and everything it asks that the hardware
	will not do.

	It is checked two ways, and both are needed. Reading the song finds what a person
	wrote that cannot sound, and reading the register stream finds what the sequencer
	actually produced: a note that fits on its own can still be refused because three
	others were already sounding.
**/
final class Budget {
	/**
		Which machine is being checked against.
	**/
	public final profile:Profile;

	/**
		Everything the last check found.
	**/
	public final found:Array<Diagnostic> = [];
	final troubles:Array<Note> = [];

	/**
		How many frames the register writes are counted over, for the per frame limit.
	**/
	public static inline final FRAMES = 60;

	/**
		The most FM operators sounding at once, counting an operator its instrument does not
		silence with its total level, over the arrangement and every pattern played on its own.
	**/
	public var operators(default, null):Int = 0;

	/**
		The most FM channels sounding at once, the same way. The converter is not among them.
	**/
	public var fmChannels(default, null):Int = 0;

	/**
		The most square and noise channels sounding at once, the same way.
	**/
	public var psgChannels(default, null):Int = 0;

	/**
		How many bytes of samples the music reaches for. A bank sitting in the library
		is not counted: what a cartridge has to carry is the sample a note plays.
	**/
	public var sampleBytes(default, null):Int = 0;

	/**
		How many of the diagnostics are faults rather than warnings.
	**/
	public var faults(default, null):Int = 0;

	/**
		Where every note starts and ends, one number each, laid out as `SPREAD` says: the tick,
		then whether it starts, which part, and how many operators it sounds.
	**/
	final moments:Array<Float> = [];

	/**
		How many notes each part is sounding at the moment being swept.
	**/
	final holding:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		How many operators each part is sounding at the moment being swept.
	**/
	final holdingOperators:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		What a tick is multiplied by in `moments`, leaving room under it for whether the note
		starts, which part it is on and how many operators it sounds.
	**/
	static inline final SPREAD = 256.0;

	/**
		Builds a budget against one machine.

		@param profile The machine to check against.
	**/
	public function new(profile:Profile) {
		this.profile = profile;
	}

	/**
		Throws away the last check.
	**/
	public function clear():Void {
		found.resize(0);
		troubles.resize(0);
		operators = 0;
		fmChannels = 0;
		psgChannels = 0;
		sampleBytes = 0;
		faults = 0;
	}

	/**
		@return How many of the diagnostics are warnings rather than faults.
	**/
	public inline function warnings():Int {
		return found.length;
	}

	/**
		@param note A note.
		@return Whether anything found points at it, which is what hatches it in the roll.
	**/
	public function troubled(note:Note):Bool {
		for (held in troubles) if (held == note) return true;
		return false;
	}

	/**
		Records one diagnostic.

		@param severity `Diagnostic.WARNING` or `Diagnostic.FAULT`.
		@param part Which part it is about.
		@param at Where in the song, in ticks.
		@param saying Which string says what is wrong.
		@param reason Which string says why.
		@param remedy Which string says what would fix it.
		@param values What goes in the places those three leave.
		@param pattern Which pattern, or -1.
		@param note The note that caused it, or null.
	**/
	function raise(severity:Int, part:Part, at:Int, saying:Int, reason:Int,
			remedy:Int, values:Array<String>, pattern:Int = -1,
			note:Null<Note> = null):Void {
		found.push(new Diagnostic(severity, part, at, saying, reason, remedy, values,
			pattern, note));
		if (severity == Diagnostic.FAULT) faults++;
		if (note != null) troubles.push(note);
	}

	/**
		Checks what a person wrote: notes on parts the machine does not have, notes
		outside what a part can reach, more overlapping than a part has channels, and
		more sample data than there is room for.

		@param song The song to check.
		@return How many diagnostics were found.
	**/
	public function overSong(song:Song):Int {
		clear();

		for (index in 0...song.patterns.length) overPattern(song, index);

		sampled(song);
		peaked(song);

		if (profile.sampleBytes > 0 && sampleBytes > profile.sampleBytes) {
			raise(Diagnostic.WARNING, Part.Dac, 0, Locale.WARN_SAMPLES_OVER,
				Locale.WARN_SAMPLES_OVER_WHY, Locale.WARN_SAMPLES_OVER_FIX,
				["" + sampleBytes, profile.name, "" + profile.sampleBytes]);
		}

		return found.length;
	}

	/**
		Adds up the samples the music plays, each one once however often it is struck.

		A preset that is merely loaded costs nothing, which is why a new piece reads
		nought however many banks ship: every other counter here reads what is played
		rather than what is to hand, and a cartridge carries the samples the music
		reaches for. Which instrument a note reaches is worked out the way the
		sequencer works it out, so a key the kit has nothing rooted at costs nothing
		either.

		@param song The song to read.
	**/
	function sampled(song:Song):Void {
		final counted:Array<Bool> = [for (index in 0...song.samples.length) false];

		for (pattern in song.patterns) {
			for (which in 0...Part.COUNT) {
				final part:Part = which;
				if (!part.sampled()) continue;

				for (note in pattern.lane(part).notes) {
					final kit = song.drums ? song.drumAt(note.pitch) : -1;
					if (song.drums && kit < 0) continue;

					final which = kit >= 0 ? kit
						: (note.instrument >= 0 ? note.instrument : song.rack[part.index()]);

					final instrument = song.instrumentAt(which);
					if (instrument == null) continue;

					final at = instrument.sample;
					if (at < 0 || at >= counted.length || counted[at]) continue;

					final sample = song.sampleAt(at);
					if (sample == null) continue;

					counted[at] = true;
					sampleBytes += sample.length();
				}
			}
		}
	}

	/**
		Finds the busiest moments of the arrangement and of every pattern played on its own, since
		either can be played: the most FM operators, FM channels and square and noise channels
		sounding at once. A note sounds from where it starts until it or its clip ends, which is
		where the sequencer keys it on and off, and a part is one channel however many of its
		notes overlap. Every clip on the playlist is counted whether or not its track is muted,
		because muting is how a piece is listened to rather than what it asks of the machine.

		@param song The song to read.
	**/
	function peaked(song:Song):Void {
		moments.resize(0);

		for (track in song.tracks) {
			for (clip in track.clips) {
				if (clip.kind != Clip.PATTERN) continue;

				final pattern = song.patternAt(clip.pattern);
				if (pattern != null) placed(song, pattern, clip.origin(), clip.at, clip.ends());
			}
		}

		swept();

		for (pattern in song.patterns) {
			moments.resize(0);
			placed(song, pattern, 0, 0, pattern.length);
			swept();
		}
	}

	/**
		Adds where every note of a pattern starts and ends, placed on the playlist, to `moments`.

		@param song The song, for the instruments the notes play.
		@param pattern The pattern.
		@param origin Where the pattern's own start lands.
		@param from The first tick it plays, where a note starting earlier is not keyed.
		@param until One past the last, where a note still sounding is cut.
	**/
	function placed(song:Song, pattern:Pattern, origin:Int, from:Int, until:Int):Void {
		for (which in 0...Part.COUNT) {
			final part:Part = which;
			if (part.sampled()) continue;

			final lane = pattern.lane(part);

			for (note in lane.notes) {
				final start = origin + note.at;
				if (start < from || start >= until) continue;

				final ends = origin + note.ends() < until ? origin + note.ends() : until;
				if (ends <= start) continue;

				final sounded = part.fm() ? audible(song, lane, part, note) : 0;

				moments.push(start * SPREAD + 128 + which * 8 + sounded);
				moments.push(ends * SPREAD + which * 8);
			}
		}
	}

	/**
		Walks `moments` in order and keeps the most of each that sounded at once. A note ending
		on a tick is let go before one starting on it, so two notes back to back on one part are
		one channel.
	**/
	function swept():Void {
		if (moments.length == 0) return;

		moments.sort(function(first:Float, second:Float):Int {
			return first < second ? -1 : (first > second ? 1 : 0);
		});

		for (which in 0...Part.COUNT) {
			holding[which] = 0;
			holdingOperators[which] = 0;
		}

		var index = 0;

		while (index < moments.length) {
			final tick = Math.ffloor(moments[index] / SPREAD);

			while (index < moments.length && Math.ffloor(moments[index] / SPREAD) == tick) {
				final rest = Std.int(moments[index] - tick * SPREAD);
				final which = (rest & 127) >> 3;

				if (rest >= 128) {
					holding[which]++;
					if ((rest & 7) > holdingOperators[which]) holdingOperators[which] = rest & 7;
				} else if (--holding[which] <= 0) {
					holding[which] = 0;
					holdingOperators[which] = 0;
				}

				index++;
			}

			var fm = 0;
			var psg = 0;
			var sounding = 0;

			for (which in 0...Part.COUNT) {
				final part:Part = which;
				if (holding[which] == 0) continue;

				if (part.fm()) {
					fm++;
					sounding += holdingOperators[which];
				} else if (!part.sampled()) {
					psg++;
				}
			}

			if (fm > fmChannels) fmChannels = fm;
			if (psg > psgChannels) psgChannels = psg;
			if (sounding > operators) operators = sounding;
		}
	}

	/**
		How many operators a note on an FM part sounds: those its instrument does not silence with
		a total level of 127. The instrument is chosen the way the sequencer chooses it, the
		lane's preset automation from its first point on, then the note's own, then the rack's.

		@param song The song.
		@param lane The lane the note is in.
		@param part Which part the lane is.
		@param note The note.
		@return How many operators it sounds, nought where there is no patch to read.
	**/
	static function audible(song:Song, lane:Lane, part:Part, note:Note):Int {
		var named = note.instrument;

		for (line in lane.automation) {
			if (line.target != Automation.INSTRUMENT) continue;

			if (line.points.length > 0 && line.points[0].at <= note.at) {
				final want = line.heldAt(note.at);
				if (song.instrumentAt(want) != null) named = want;
			}

			break;
		}

		final instrument = song.instrumentAt(named >= 0 ? named : song.rack[part.index()]);
		if (instrument == null || instrument.patch == null) return 0;

		var many = 0;
		for (slot in 0...4) if (instrument.patch.totalLevel[slot] < 127) many++;

		return many;
	}

	/**
		Checks one pattern.

		@param song The song it belongs to.
		@param index Which pattern.
	**/
	function overPattern(song:Song, index:Int):Void {
		final pattern = song.patterns[index];

		for (which in 0...Part.COUNT) {
			final part:Part = which;
			final lane = pattern.lane(part);
			if (lane.notes.length == 0) continue;

			if (!profile.carries(part)) {
				raise(Diagnostic.FAULT, part, lane.notes[0].at, Locale.WARN_PART_ABSENT,
					Locale.WARN_PART_ABSENT_WHY, Locale.WARN_PART_ABSENT_FIX,
					["" + lane.notes.length, profile.name, part.name()], index,
					lane.notes[0]);
				continue;
			}

			overlapping(index, part, lane.notes);
			ranged(index, part, lane.notes);
			sounding(song, index, part, lane);
			droning(index, part, lane, pattern.length);
		}

		final dac = pattern.lane(Part.Dac);
		final sixth = pattern.lane(Part.Fm6);

		if (dac.notes.length > 0 && sixth.notes.length > 0) {
			for (note in sixth.notes) {
				for (sampled in dac.notes) {
					if (note.at >= sampled.ends() || sampled.at >= note.ends()) continue;

					raise(Diagnostic.FAULT, Part.Fm6, note.at, Locale.WARN_DAC_HOLDS_SIX,
						Locale.WARN_DAC_HOLDS_SIX_WHY, Locale.WARN_DAC_HOLDS_SIX_FIX, [],
						index, note);
					break;
				}
			}
		}
	}

	/**
		Finds where more notes overlap on one part than it has channels.

		@param pattern Which pattern.
		@param part Which part.
		@param notes Its notes, in tick order.
	**/
	function overlapping(pattern:Int, part:Part, notes:Array<Note>):Void {
		var sounding = -1;
		var held:Null<Note> = null;

		for (note in notes) {
			if (note.at < sounding && held != null) {
				raise(Diagnostic.WARNING, part, note.at, Locale.WARN_ONE_VOICE,
					Locale.WARN_ONE_VOICE_WHY, Locale.WARN_ONE_VOICE_FIX,
					[part.name(), "" + held.at], pattern, note);
				continue;
			}

			sounding = note.ends();
			held = note;
		}
	}

	/**
		Finds notes played by a patch that never lets go. A release rate of nought or one is slower
		than anything a piece waits for, so the key off at the note's end is not heard and the
		channel sounds on until the next note keys it on again, or forever where none does. A
		driver hides it by always keying on again in time; a piece that stops does not.

		@param song The song, for the patch a note plays.
		@param pattern Which pattern.
		@param part Which part.
		@param lane Its lane.
	**/
	function sounding(song:Song, pattern:Int, part:Part, lane:mdd.song.Lane):Void {
		if (!part.fm()) return;

		for (note in lane.notes) {
			final named = note.instrument >= 0 ? note.instrument : song.rack[part.index()];
			final instrument = song.instrumentAt(named);
			final patch = instrument == null ? null : instrument.patch;

			if (patch == null) continue;

			var slowest = 15;

			for (slot in 0...4) {
				if (!patch.carries(slot)) continue;
				if (patch.release[slot] < slowest) slowest = patch.release[slot];
			}

			if (slowest > 1) continue;

			raise(Diagnostic.WARNING, part, note.at, Locale.WARN_NEVER_RELEASES,
				Locale.WARN_NEVER_RELEASES_WHY, Locale.WARN_NEVER_RELEASES_FIX,
				[instrument == null ? "" : instrument.name, "" + slowest], pattern, note);

			return;
		}
	}

	/**
		Finds a square or the noise channel left sounding by a level lane after its last note. A
		note's end writes the channel silent, and a point after it writes the lane's own value over
		that, so the channel carries on with nothing playing it.

		@param pattern Which pattern.
		@param part Which part.
		@param lane Its lane.
		@param length How long the pattern is, in ticks.
	**/
	function droning(pattern:Int, part:Part, lane:mdd.song.Lane, length:Int):Void {
		if (!part.square() && !part.noise()) return;

		var ends = 0;
		for (note in lane.notes) if (note.ends() > ends) ends = note.ends();

		for (line in lane.automation) {
			if (line.target != mdd.song.Automation.LEVEL || line.slot > 0) continue;
			if (line.points.length == 0) continue;

			final last = line.points[line.points.length - 1];
			if (last.at < ends) continue;

			final held = line.heldAt(length - 1);
			if (held < 0 || held >= mdd.play.Velocity.PSG_OFF) continue;

			raise(Diagnostic.WARNING, part, last.at, Locale.WARN_LEFT_SOUNDING,
				Locale.WARN_LEFT_SOUNDING_WHY, Locale.WARN_LEFT_SOUNDING_FIX,
				[part.name(), "" + held], pattern, lane.notes.length > 0 ? lane.notes[0] : null);

			return;
		}
	}

	/**
		Finds notes outside what the part can reach.

		@param pattern Which pattern.
		@param part Which part.
		@param notes Its notes.
	**/
	function ranged(pattern:Int, part:Part, notes:Array<Note>):Void {
		for (note in notes) {
			if (part.square()) {
				if (note.pitch >= profile.lowestSquare) continue;

				raise(Diagnostic.WARNING, part, note.at, Locale.WARN_BELOW_SQUARE,
					Locale.WARN_BELOW_SQUARE_WHY, Locale.WARN_BELOW_SQUARE_FIX,
					["" + profile.lowestSquare], pattern, note);
				continue;
			}

			if (!part.fm()) continue;
			if (note.pitch >= profile.lowestFm && note.pitch <= profile.highestFm) continue;

			raise(Diagnostic.WARNING, part, note.at, Locale.WARN_OUTSIDE_BLOCK,
				Locale.WARN_OUTSIDE_BLOCK_WHY, Locale.WARN_OUTSIDE_BLOCK_FIX,
				["" + profile.lowestFm, "" + profile.highestFm], pattern, note);
		}
	}

	/**
		Checks what the sequencer actually produced: writes to parts the machine does
		not have, and more writes in a frame than a driver could make.

		@param stream The register writes to check.
		@return How many diagnostics were found.
	**/
	public function overStream(stream:Stream):Int {
		clear();

		final frame = Std.int(mdd.song.Tempo.TICKS / FRAMES);

		var half = 0;
		var address = -1;

		var frameAt = 0;
		var written = 0;
		var said = false;

		for (index in 0...stream.count) {
			final kind = stream.kindAt(index);
			final port = stream.portAt(index);
			final value = stream.valueAt(index);
			final at = stream.tickAt(index);

			while (at >= frameAt + frame) {
				frameAt += frame;
				written = 0;
				said = false;
			}

			if (kind == Stream.PSG || (port & 1) != 0) {
				if (kind == Stream.PSG || address != 0x2A) written++;
			}

			if (profile.perFrame > 0 && written > profile.perFrame && !said
					&& frameAt > 0) {
				said = true;

				raise(Diagnostic.WARNING, halfPart(half, address < 0 ? 0x40 : address),
					frameAt, Locale.WARN_FRAME_BUSY, Locale.WARN_FRAME_BUSY_WHY,
					Locale.WARN_FRAME_BUSY_FIX, ["" + written, "" + profile.perFrame]);
			}

			if (kind == Stream.PSG) {
				if (profile.carries(Part.Psg1)) continue;

				raise(Diagnostic.FAULT, Part.Psg1, at, Locale.WARN_PSG_ABSENT,
					Locale.WARN_PSG_ABSENT_WHY, Locale.WARN_PSG_ABSENT_FIX,
					[profile.name]);
				continue;
			}

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (address < 0) continue;

			if (half == 0 && address == 0x28) {
				if (profile.keyed(value & 7)) continue;

				raise(Diagnostic.FAULT, keyedPart(value & 7), at, Locale.WARN_KEY_ABSENT,
					Locale.WARN_KEY_ABSENT_WHY, Locale.WARN_KEY_ABSENT_FIX,
					[profile.name, "" + ((value & 7) & 3),
					"" + (((value & 4) != 0) ? 1 : 0)]);
				continue;
			}

			if (profile.holds(half, address)) continue;

			raise(Diagnostic.FAULT, halfPart(half, address), at,
				Locale.WARN_REGISTER_ABSENT, Locale.WARN_REGISTER_ABSENT_WHY,
				Locale.WARN_REGISTER_ABSENT_FIX,
				[StringTools.hex(address, 2), "" + half, profile.name]);
		}

		return found.length;
	}

	/**
		@param select A byte written to the key on register.
		@return Which part it names.
	**/
	static function keyedPart(select:Int):Part {
		final within = select & 3;
		if (within == 3) return Part.Fm1;
		return within + ((select & 4) != 0 ? 3 : 0);
	}

	/**
		@param half Which half of the FM register file.
		@param address The register address within it.
		@return Which part that register belongs to.
	**/
	static function halfPart(half:Int, address:Int):Part {
		final held = Stream.ymPart(half, address);
		return held < 0 ? Part.Fm1 : held;
	}
}
