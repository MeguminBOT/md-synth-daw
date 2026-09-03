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
	public static inline final TWEAK = 2;
	public static inline final TUNE = 3;
	public static inline final DATA = 4;
	public static inline final ON = 5;
	public static inline final SETUP = 6;

	public static inline final DAC_BYTE = 0;
	public static inline final PSG_STEP = 1;

	public static inline final ENVELOPE_TICKS = 735;
	public static inline final GUARD = 0;

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

	public function emit(stream:Stream, fromSample:Int, toSample:Int):Int {
		count = 0;
		dropped = 0;

		if (toSample <= fromSample) return 0;

		if (fromSample <= 0) push(0, Part.Fm1, SETUP, (song.lfoOn ? 8 : 0) | (song.lfoRate & 7), 0);

		gather(fromSample, toSample);
		sort();
		play(stream);

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
				walk(pattern, 0, pattern.length, 0, low, high, fromSample, toSample);
			}

			return;
		}

		for (track in song.tracks) {
			if (track.muted) continue;

			for (clip in track.clips) {
				if (clip.at > high || clip.ends() <= low) continue;

				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				walk(pattern, clip.at, clip.ends(), clip.transpose, low, high, fromSample,
					toSample);
			}
		}
	}

	function walk(pattern:mdd.song.Pattern, from:Int, until:Int, transpose:Int, low:Int,
			high:Int, fromSample:Int, toSample:Int):Void {
		if (from > high || until <= low) return;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (!song.audible(part)) continue;

			final lane = pattern.lane(part);
			if (lane.notes.length == 0 && lane.automation.length == 0) continue;

			var head = low - from;
			if (head < 0) head = 0;

			voices.resolve(lane, head, high - from + 1);
			sound(lane, from, until, transpose, part, fromSample, toSample);
			tweaked(lane, from, part, head, high - from + 1, transpose, fromSample, toSample);
		}
	}

	function sound(lane:mdd.song.Lane, from:Int, until:Int, transpose:Int, part:Part,
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
			var start = from + voices.startAt(slice);
			var ends = from + voices.endAt(slice);

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

							final want = line.heldAt(start - from);
							if (want < 0) continue;

							final level = line.target == mdd.song.Automation.LEVEL;

							push(onSample, part, TWEAK,
								(line.slot << 8) | (want & (level ? 0x7F : 0xFF)),
								level ? 0 : 2 + line.target);
						}
					}
				}

				if (bent == null) push(onSample, part, TUNE, pitch, 0);
				else if (part.fm()) {
					if (bent.heldAt(start - from) < 0) push(onSample, part, TUNE, pitch, 0);
				} else push(onSample, part, TUNE, bent.heldAt(start - from) & 0x3FF, 2);

				final levelled = (part.square() || part.noise()) && lines[0] != null;

				if (!tied && !levelled && !(part.sampled() && bent != null)) {
					push(onSample, part, ON, velocity, named);
				}

				if (lines[0] != null && !part.fm()) {
					push(onSample, part, DATA, lines[0].heldAt(start - from) & 0x0F,
						PSG_STEP);
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

	function lined(at:Int, part:Part, line:mdd.song.Automation, value:Int,
			transpose:Int):Void {
		final level = line.target == mdd.song.Automation.LEVEL;
		final tune = line.target == mdd.song.Automation.TUNE;

		final shaping = part.fm() && mdd.song.Automation.operates(line.target) && !level;

		if (shaping) {
			push(at, part, TWEAK, (line.slot << 8) | (value & 0xFF), 2 + line.target);
		} else if (level && !part.fm()) push(at, part, DATA, value & 0x0F, PSG_STEP);
		else if (level) push(at, part, TWEAK, (line.slot << 8) | (value & 0x7F), 0);
		else if (tune && part.sampled()) push(at, part, TUNE, value, 5);
		else if (tune && part.noise()) push(at, part, TUNE, value & 0x0F, 4);
		else if (tune && !part.fm()) push(at, part, TUNE, value & 0x3FF, 2);
		else if (tune && line.slot > 0) {
			push(at, part, TUNE, (line.slot << 14) | shifted(value, transpose), 3);
		} else if (tune) push(at, part, TUNE, shifted(value, transpose), 1);
		else push(at, part, TWEAK, masked(part, value), 1);
	}

	function tweaked(lane:mdd.song.Lane, from:Int, part:Part, head:Int, tail:Int,
			transpose:Int, fromSample:Int, toSample:Int):Void {
		if (lane.automation.length == 0) return;
		if (!part.fm() && !part.square() && !part.noise() && !part.sampled()) return;

		final tempo = song.tempo;

		for (line in lane.automation) {
			if (!carries(part, line)) continue;

			var index = line.seek(head);
			if (index > 0) index--;

			while (index < line.points.length) {
				final point = line.points[index];
				if (point.at > tail) break;

				index++;

				final at = tempo.samplesAt(from + point.at);
				if (at < fromSample || at >= toSample) continue;

				lined(at, part, line, point.value, transpose);
			}
		}
	}

	public function prime(stream:Stream, fromSample:Int):Void {
		count = 0;
		dropped = 0;

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
					local = tick - clip.at;
					transpose = clip.transpose;
				}
			}
		}

		var named = song.rack[part.index()];
		var sided:Null<mdd.song.Automation> = null;

		if (lane != null) {
			for (note in lane.notes) {
				if (note.at > local) break;
				named = note.instrument;
			}

			for (line in lane.automation) {
				if (line.target == mdd.song.Automation.SIDES) sided = line;
			}
		}

		if (part.fm()) {
			push(at, part, PATCH, named, 127);
			push(at, part, TWEAK, spread(part, sided, local, named), 1);
		}

		if (lane == null) return;

		for (line in lane.automation) {
			if (!carries(part, line)) continue;
			if (line.points.length == 0 || line.points[0].at > local) continue;

			final want = line.heldAt(local);
			if (want < 0) continue;

			lined(at, part, line, want, transpose);
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
				final want = velocity < 0 ? 0 : (velocity > 127 ? 127 : velocity);
				final quiet = 15 - Std.int(want * 15 / 127);
				push(at, part, DATA, quiet + envelope.at(index), PSG_STEP);
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
		final held = song.volume[part.index()];
		if (held >= Song.LOUDEST) return velocity;

		final want = Std.int(velocity * held / Song.LOUDEST);
		return want < 0 ? 0 : (want > 127 ? 127 : want);
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
		if (firsts[left] != firsts[right]) return firsts[left] < firsts[right];
		if (seconds[left] != seconds[right]) return seconds[left] < seconds[right];

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
						stream.noise(tick, instrument.envelope.noise);
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
