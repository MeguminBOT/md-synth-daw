package mdd.play;

import haxe.ds.Vector;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;

@:unreflective
final class Sequencer {
	public static inline final OFF = 0;
	public static inline final PATCH = 1;
	static inline final TWEAK = 2;
	public static inline final TUNE = 3;
	public static inline final DATA = 4;
	public static inline final ON = 5;
	static inline final SETUP = 6;

	static inline final DAC_BYTE = 0;
	static inline final PSG_STEP = 1;

	public static inline final ENVELOPE_TICKS = 735;
	static inline final GUARD = 0;

	public final song:Song;
	public final voices:Voices;

	public var alone:Int = -1;

	public static inline final CHUNK = 8192;

	public var capacity(default, null):Int;
	public var count(default, null):Int = 0;
	public var dropped(default, null):Int = 0;
	public var lost(default, null):Int = 0;

	final ticks:Vector<Int>;
	final parts:Vector<Int>;
	final kinds:Vector<Int>;
	final firsts:Vector<Int>;
	final seconds:Vector<Int>;
	final order:Vector<Int>;
	final lines:Vector<Null<mdd.song.Automation>> = new Vector<Null<mdd.song.Automation>>(4);

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
	}

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
		}

		return made;
	}

	public final driver:Driver = new Driver();

	var paced:Null<Stream> = null;

	public function emit(stream:Stream, fromSample:Int, toSample:Int):Int {
		count = 0;
		dropped = 0;

		if (toSample <= fromSample) return 0;

		if (fromSample <= 0) push(0, Part.Fm1, SETUP, (song.lfoOn ? 8 : 0) | (song.lfoRate & 7), 0);

		gather(fromSample, toSample);
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

	function gather(fromSample:Int, toSample:Int):Void {
		final tempo = song.tempo;

		var low = tempo.tickAt(fromSample) - 1;
		if (low < 0) low = 0;

		final high = tempo.tickAt(toSample) + 1;

		if (alone >= 0) {
			final pattern = song.patternAt(alone);
			if (pattern != null) {
				walk(pattern, 0, 0, pattern.length, 0, low, high, fromSample, toSample);
			}

			return;
		}

		for (track in song.tracks) {
			if (track.muted) continue;

			for (clip in track.clips) {
				if (clip.at > high || clip.ends() <= low) continue;
				if (clip.kind == mdd.song.Clip.AUTOMATION) continue;

				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				walk(pattern, clip.origin(), clip.at, clip.ends(), clip.transpose, low, high,
					fromSample, toSample);
			}
		}

		for (track in song.tracks) {
			if (track.muted) continue;

			for (clip in track.clips) {
				if (clip.at > high || clip.ends() <= low) continue;
				if (!clip.drawn()) continue;

				drove(clip, low, high, fromSample, toSample);
			}
		}
	}

	var underTranspose:Int = 0;

	function noteUnder(part:Part, tick:Int):Null<mdd.song.Note> {
		var found:Null<mdd.song.Note> = null;
		underTranspose = 0;

		for (track in song.tracks) {
			if (track.muted) continue;

			for (clip in track.clips) {
				if (clip.kind != mdd.song.Clip.PATTERN) continue;
				if (clip.at > tick || clip.ends() <= tick) continue;

				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				final local = tick - clip.origin();

				for (note in pattern.lane(part).notes) {
					if (note.at > local) break;

					found = note;
					underTranspose = clip.transpose;
				}
			}
		}

		return found;
	}

	function drove(clip:mdd.song.Clip, low:Int, high:Int, fromSample:Int,
			toSample:Int):Void {
		final line = clip.line;
		if (line == null || line.points.length == 0) return;

		final part:Part = clip.part;
		if (!song.audible(part)) return;

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
			note.instrument);
	}

	function walk(pattern:mdd.song.Pattern, origin:Int, from:Int, until:Int, transpose:Int,
			low:Int, high:Int, fromSample:Int, toSample:Int):Void {
		if (from > high || until <= low) return;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (!song.audible(part)) continue;

			final lane = pattern.lane(part);
			if (lane.notes.length == 0 && lane.automation.length == 0) continue;

			final least = from - origin;
			var head = low - origin;
			if (head < least) head = least;

			voices.resolve(lane, head, high - origin + 1);
			sound(lane, origin, from, until, transpose, part, fromSample, toSample);
			tweaked(lane, origin, part, head, high - origin + 1, transpose, fromSample, toSample);
		}
	}

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

		for (slice in 0...voices.count) {
			var start = origin + voices.startAt(slice);
			var ends = origin + voices.endAt(slice);

			if (start < from) start = from;
			if (ends > until) ends = until;
			if (ends <= start) continue;

			final tied = part.fm() && voices.tiedAt(slice);
			final held = part.fm() && voices.heldAt(slice);

			final onSample = tempo.samplesAt(start);
			final ending = tempo.samplesAt(ends);
			final offSample = !held && ending - onSample > GUARD * 2 ? ending - GUARD : ending;
			final pitch = voices.pitchAt(slice) + transpose;
			final velocity = louder(part, voices.velocityAt(slice));
			final named = voices.instrumentAt(slice);

			if (onSample >= fromSample && onSample < toSample) {
				if (!tied) {
					push(onSample, part, PATCH, named,
						bent != null && part.noise() ? -1 : velocity);

					if (part.fm()) {
						push(onSample, part, TWEAK, spread(part, sided, start - from,
							named), 1);

						for (line in lane.automation) {
							if (!mdd.song.Automation.operates(line.target)) continue;
							if (line.target == mdd.song.Automation.LEVEL) continue;

							final want = line.heldAt(start - from);
							if (want < 0) continue;

							push(onSample, part, TWEAK, (line.slot << 8) | (want & 0xFF),
								2 + line.target);
						}
					}
				}

				if (bent == null || !rides(part, bent)) {
					push(onSample, part, TUNE, pitch, 0);
				} else {
					final offset = bent.heldAt(start - from);
					final want = voices.pitchAt(slice);

					if (part.fm()) {
						push(onSample, part, TUNE, worded(offset, want, transpose), 1);
					} else push(onSample, part, TUNE, periodic(offset, want, transpose), 2);
				}

				if (!tied && !(part.sampled() && bent != null)) {
					push(onSample, part, ON, velocity, named);
				}

			}

			if (!held && offSample >= fromSample && offSample < toSample
					&& !(part.sampled() && bent != null)) {
				push(offSample, part, OFF, 0, 0);
			}

			if (part.sampled()) sampled(onSample, offSample, named, fromSample, toSample);
			else if ((part.square() || part.noise()) && lines[0] == null) {
				shaped(onSample, offSample, part, named, velocity, fromSample, toSample);
			}
		}
	}

	inline function carries(part:Part, line:mdd.song.Automation):Bool {
		final level = line.target == mdd.song.Automation.LEVEL;
		final tune = line.target == mdd.song.Automation.TUNE;

		final shaping = part.fm() && mdd.song.Automation.operates(line.target) && !level;

		if (!level && !tune && !shaping
			&& line.target != mdd.song.Automation.SIDES) return false;

		return part.fm() || level || tune;
	}

	function lined(at:Int, part:Part, line:mdd.song.Automation, value:Int, transpose:Int,
			pitch:Int, velocity:Int, named:Int):Void {
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

	inline function rides(part:Part, line:mdd.song.Automation):Bool {
		if (line.target == mdd.song.Automation.LEVEL) return true;

		return line.target == mdd.song.Automation.TUNE && line.slot == 0
			&& (part.fm() || part.square());
	}

	inline function pitched(pitch:Int, transpose:Int):Int {
		final want = pitch + transpose;
		return want < 0 ? 0 : (want > 127 ? 127 : want);
	}

	function worded(offset:Int, pitch:Int, transpose:Int):Int {
		if (pitch < 0) return offset & 0x3FFF;

		return Tuning.word(offset, pitched(pitch, transpose));
	}

	function periodic(offset:Int, pitch:Int, transpose:Int):Int {
		if (pitch < 0) return offset & 0x3FF;

		final want = Stream.periodOf(pitched(pitch, transpose)) + offset;
		return want < 0 ? 0 : (want > 0x3FF ? 0x3FF : want);
	}

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

	inline function starts(tick:Int):Bool {
		final under = sounding(tick);
		return under >= 0 && voices.startAt(under) == tick;
	}

	var wroteValue:Int = 0;
	var wroteUnder:Int = -2;

	function put(at:Int, part:Part, line:mdd.song.Automation, value:Int, transpose:Int,
			riding:Bool, tick:Int):Void {
		final under = riding ? sounding(tick) : -1;
		if (under == wroteUnder && value == wroteValue) return;

		wroteUnder = under;
		wroteValue = value;

		if (under < 0) lined(at, part, line, value, transpose, -1, -1, -1);
		else {
			lined(at, part, line, value, transpose, voices.pitchAt(under),
				voices.velocityAt(under), voices.instrumentAt(under));
		}
	}

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

	function sounding(tick:Int):Int {
		var found = -1;

		for (slice in 0...voices.count) {
			if (voices.startAt(slice) > tick) break;
			found = slice;
		}

		return found;
	}

	function tweaked(lane:mdd.song.Lane, origin:Int, part:Part, head:Int, tail:Int,
			transpose:Int, fromSample:Int, toSample:Int):Void {
		if (lane.automation.length == 0) return;
		if (!part.fm() && !part.square() && !part.noise() && !part.sampled()) return;

		final tempo = song.tempo;

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
						&& !(riding && starts(point.at))) {
					put(at, part, line, point.value, transpose, riding, point.at);
				}

				if (!mdd.song.Automation.moves(point.shape)) continue;
				if (index >= line.points.length) continue;

				ramped(part, line, point, line.points[index], origin, transpose, riding,
					fromSample, toSample);
			}
		}
	}

	public function prime(stream:Stream, fromSample:Int):Void {
		count = 0;
		dropped = 0;

		driver.forget();
		if (paced != null) paced.forget();

		push(fromSample, Part.Fm1, SETUP,
			(song.lfoOn ? 8 : 0) | (song.lfoRate & 7), 0);

		final tick = song.tempo.tickAt(fromSample);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (!song.audible(part)) continue;

			primed(part, tick, fromSample);
		}

		sort();
		play(stream);
	}

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
				if (track.muted) continue;

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
			for (note in lane.notes) {
				if (note.at > local) break;

				named = note.instrument;
				under = note;
			}

			for (line in lane.automation) {
				if (line.target == mdd.song.Automation.SIDES) sided = line;
			}
		}

		if (part.fm()) {
			push(at, part, PATCH, named, under == null ? 127 : louder(part, under.velocity));
			push(at, part, TWEAK, spread(part, sided, local, named), 1);
		}

		if (lane == null) return;

		for (line in lane.automation) {
			if (!carries(part, line)) continue;
			if (line.points.length == 0 || line.points[0].at > local) continue;

			final want = line.heldAt(local);
			if (want < 0 && !rides(part, line)) continue;

			if (!rides(part, line)) {
				lined(at, part, line, want, transpose, -1, -1, -1);
				continue;
			}

			if (under == null) {
				lined(at, part, line, want, transpose, -1, -1, -1);
				continue;
			}

			final held = line.seek(local + 1) - 1;
			if (held >= 0 && line.points[held].at < under.at) continue;

			lined(at, part, line, want, transpose, under.pitch, under.velocity,
				under.instrument);
		}
	}

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

	inline function masked(part:Part, value:Int):Int {
		final pan = song.pan[part.index()] & 3;
		return (value & 0x3F) | ((((value >> 6) & pan) & 3) << 6);
	}

	function sampled(onSample:Int, offSample:Int, named:Int, fromSample:Int, toSample:Int):Void {
		final instrument = instrumentOf(named, Part.Dac);
		if (instrument == null) return;

		final sample = song.sampleAt(instrument.sample);
		if (sample == null || sample.length() == 0) return;

		final rate = sample.rate < 1 ? 1 : sample.rate;
		final step = Tempo.TICKS / rate;


		final frame = song.stallEvery < 8 ? 735.0 : song.stallEvery;
		final stalls = song.stallAt >= 0 && song.stallFor > 0;

		var when = onSample + 0.0;

		var next = stalls
			? Math.floor(onSample / frame) * frame + song.stallAt : 0.0;

		if (stalls) while (next < onSample) next += frame;

		var index = 0;

		while (index < sample.length()) {
			if (stalls && when >= next) {
				when += song.stallFor;
				next += frame;
				continue;
			}

			final at = Math.round(when);
			if (at >= toSample || at >= offSample) break;

			if (at >= fromSample) push(at, Part.Dac, DATA, quieter(sample.bytes[index]),
				DAC_BYTE);

			when += step;
			index++;
		}
	}

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

	inline function quieter(value:Int):Int {
		final held = song.volume[Part.Dac.index()];
		if (held >= Song.LOUDEST) return value;

		final want = 0x80 + Std.int((value - 0x80) * held / Song.LOUDEST);
		return want < 0 ? 0 : (want > 255 ? 255 : want);
	}

	inline function louder(part:Part, velocity:Int):Int {
		return Velocity.scaled(velocity, song.volume[part.index()]);
	}

	function instrumentOf(named:Int, part:Part):Null<Instrument> {
		final want = named >= 0 ? named : song.rack[part.index()];
		return song.instrumentAt(want);
	}

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
		order[count] = count;
		count++;
	}

	inline function before(left:Int, right:Int):Bool {
		if (ticks[left] != ticks[right]) return ticks[left] < ticks[right];
		if (parts[left] != parts[right]) return parts[left] < parts[right];
		if (kinds[left] != kinds[right]) return kinds[left] < kinds[right];
		if (seconds[left] != seconds[right]) return seconds[left] < seconds[right];
		if (firsts[left] != firsts[right]) return firsts[left] < firsts[right];

		return left < right;
	}

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

	function play(stream:Stream):Void {
		for (index in 0...count) {
			final at = order[index];

			final tick = ticks[at];
			final part:Part = parts[at];
			final first = firsts[at];
			final second = seconds[at];

			switch (kinds[at]) {
				case OFF:
					stream.silence(tick, part);

				case PATCH:
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
