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
	public static inline final TUNE = 2;
	public static inline final ON = 3;
	public static inline final DATA = 4;

	public static inline final DAC_BYTE = 0;
	public static inline final PSG_STEP = 1;

	public static inline final ENVELOPE_TICKS = 735;

	public final song:Song;
	public final voices:Voices;

	public var alone:Int = -1;

	public var capacity(default, null):Int;
	public var count(default, null):Int = 0;
	public var dropped(default, null):Int = 0;

	final ticks:Vector<Int>;
	final parts:Vector<Int>;
	final kinds:Vector<Int>;
	final firsts:Vector<Int>;
	final seconds:Vector<Int>;
	final order:Vector<Int>;

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

	public function emit(stream:Stream, fromSample:Int, toSample:Int):Int {
		count = 0;
		dropped = 0;

		if (toSample <= fromSample) return 0;

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
			if (lane.notes.length == 0) continue;

			voices.resolve(lane);
			sound(from, until, transpose, part, fromSample, toSample);
		}
	}

	function sound(from:Int, until:Int, transpose:Int, part:Part, fromSample:Int,
			toSample:Int):Void {
		final tempo = song.tempo;

		for (slice in 0...voices.count) {
			var start = from + voices.startAt(slice);
			var ends = from + voices.endAt(slice);

			if (start < from) start = from;
			if (ends > until) ends = until;
			if (ends <= start) continue;

			final onSample = tempo.samplesAt(start);
			final offSample = tempo.samplesAt(ends);
			final pitch = voices.pitchAt(slice) + transpose;
			final velocity = louder(part, voices.velocityAt(slice));
			final named = voices.instrumentAt(slice);

			if (onSample >= fromSample && onSample < toSample) {
				push(onSample, part, PATCH, named, velocity);
				push(onSample, part, TUNE, pitch, 0);
				push(onSample, part, ON, velocity, 0);
			}

			if (offSample >= fromSample && offSample < toSample) {
				push(offSample, part, OFF, 0, 0);
			}

			if (part.sampled()) sampled(onSample, offSample, named, fromSample, toSample);
			else if (part.square() || part.noise()) {
				shaped(onSample, offSample, part, named, velocity, fromSample, toSample);
			}
		}
	}

	function sampled(onSample:Int, offSample:Int, named:Int, fromSample:Int, toSample:Int):Void {
		final instrument = instrumentOf(named, Part.Dac);
		if (instrument == null) return;

		final sample = song.sampleAt(instrument.sample);
		if (sample == null || sample.length() == 0) return;

		final rate = sample.rate < 1 ? 1 : sample.rate;
		final step = Tempo.TICKS / rate;

		var index = 0;
		if (fromSample > onSample) index = Std.int((fromSample - onSample) / step);

		while (index < sample.length()) {
			final at = onSample + Math.round(index * step);
			if (at >= toSample || at >= offSample) break;

			if (at >= fromSample) push(at, Part.Dac, DATA, quieter(sample.bytes[index]),
				DAC_BYTE);
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
		return seconds[left] < seconds[right];
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
					if (part.noise() && instrument != null && instrument.envelope != null) {
						stream.noise(tick, instrument.envelope.noise);
					}

				case TUNE:
					if (part.fm()) stream.tune(tick, part, first);
					else if (part.square()) stream.square(tick, part, first);

				case ON:
					if (part.fm()) stream.keyOn(tick, part);
					else if (part.square() || part.noise()) {
						final instrument = instrumentOf(-1, part);
						stream.loudness(tick, part, instrument == null ? null : instrument.envelope,
							first, 0);
					} else if (part.sampled()) stream.sampling(tick, true);

				case DATA:
					if (second == DAC_BYTE) stream.byte(tick, first);
					else stream.attenuate(tick, part, first);

				case _:
			}
		}
	}
}
