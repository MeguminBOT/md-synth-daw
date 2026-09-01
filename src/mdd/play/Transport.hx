package mdd.play;

import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;

@:unreflective
final class Transport {
	public final song:Song;
	public final sequencer:Sequencer;
	public final stream:Stream;

	public var playing(default, null):Bool = false;
	public var position(default, null):Int = 0;

	public var looping:Bool = false;
	public var loopFrom:Int = 0;
	public var loopTo:Int = 0;

	public var served(default, null):Int = 0;
	public var wrapped(default, null):Int = 0;
	public var stepped(default, null):Int = 0;
	public var entering(default, null):Int = 0;

	final gate:sys.thread.Mutex = new sys.thread.Mutex();

	public static inline final AUDITION_BLOCKS = 90;

	public var source:Null<Stream> = null;
	var heardPart:Int = -1;
	var heardNote:Int = 0;
	var heardLeft:Int = 0;
	var heardFresh:Bool = false;
	var poured:Int = 0;
	var hushing:Bool = false;
	var latched:Int = -1;

	var carried:Int = 0;

	public function new(song:Song, capacity:Int = 8192) {
		this.song = song;
		sequencer = new Sequencer(song);
		stream = new Stream(capacity);
	}

	public function play():Void {
		playing = true;
	}

	public function stop():Void {
		playing = false;
		hushing = true;
	}

	public function seek(tick:Int):Void {
		position = tick < 0 ? 0 : tick;
		hushing = true;
		poured = 0;
	}

	public function loop(fromTick:Int, toTick:Int):Void {
		loopFrom = fromTick < 0 ? 0 : fromTick;
		loopTo = toTick;
		looping = toTick > loopFrom;
	}

	public inline function holds():Void {
		gate.acquire();
	}

	public inline function frees():Void {
		gate.release();
	}

	public function advance(frames:Int, rate:Int):Int {
		stream.clear();
		entering = carried;

		if (hushing) {
			hushing = false;
			heardPart = -1;
			stream.reset(position);
		}

		if (!playing) {
			stepped = 0;

			gate.acquire();
			auditioned(position);
			gate.release();

			return position;
		}

		final total = frames * Tempo.TICKS + carried;
		final step = Std.int(total / rate);
		carried = total - step * rate;

		final from = position;
		var until = from + step;

		if (looping && until > loopTo) until = loopTo;

		gate.acquire();

		if (source != null) replayed(from, until);
		else sequencer.emit(stream, from, until);

		auditioned(from);

		gate.release();
		served++;
		stepped = until - from;

		if (looping && until >= loopTo) {
			position = loopFrom;
			wrapped++;
		} else {
			position = until;
		}

		return from;
	}

	public function auditions(part:Part, note:Int):Void {
		gate.acquire();

		heardPart = part.index();
		heardNote = note;
		heardLeft = AUDITION_BLOCKS;
		heardFresh = true;

		gate.release();
	}

	function auditioned(at:Int):Void {
		if (heardPart < 0) return;

		final part:Part = heardPart;

		if (heardFresh) {
			heardFresh = false;

			final instrument = song.instrumentAt(song.rack[heardPart]);

			if (part.fm()) {
				if (instrument != null && instrument.patch != null) {
					stream.patch(at, part, instrument.patch, 110);
				}

				stream.tune(at, part, heardNote);
				stream.keyOn(at, part);
			} else if (part.square()) {
				stream.square(at, part, heardNote);
				stream.loudness(at, part, instrument == null ? null : instrument.envelope, 110, 0);
			} else if (part.noise()) {
				if (instrument != null && instrument.envelope != null) {
					stream.noise(at, instrument.envelope.noise);
				}

				stream.loudness(at, part, instrument == null ? null : instrument.envelope, 110, 0);
			}
		}

		heardLeft--;
		if (heardLeft > 0) return;

		stream.silence(at, part);
		heardPart = -1;
	}

	function replayed(from:Int, until:Int):Void {
		final held = source;
		if (held == null) return;

		if (poured > held.count || (poured < held.count && held.tickAt(poured) > from)) {
			poured = 0;
			latched = -1;
		}

		while (poured < held.count && held.tickAt(poured) < from) poured++;

		while (poured < held.count && held.tickAt(poured) < until) {
			final tick = held.tickAt(poured);
			final kind = held.kindAt(poured);
			final port = held.portAt(poured);
			final value = held.valueAt(poured);

			if (kind != Stream.YM) {
				if ((value & 0x80) != 0) latched = 6 + ((value >> 5) & 3);

				if (latched >= 0 && !song.audible(latched)) {
					poured++;
					continue;
				}

				stream.raw(tick, kind, port, value);
				poured++;
				continue;
			}

			if ((port & 1) != 0) {
				stream.raw(tick, kind, port, value);
				poured++;
				continue;
			}

			final after = poured + 1;
			final paired = after < held.count && held.kindAt(after) == Stream.YM
				&& (held.portAt(after) & 1) != 0;

			final data = paired ? held.valueAt(after) : 0;
			final half = port >> 1;

			final part = value == 0x28 ? Stream.keyPart(data) : Stream.ymPart(half, value);

			if (part >= 0 && !song.audible(part)) {
				poured += paired ? 2 : 1;
				continue;
			}

			stream.raw(tick, kind, port, value);
			poured++;

			if (!paired) continue;

			stream.raw(held.tickAt(after), Stream.YM, held.portAt(after), data);
			poured++;
		}
	}

	public function rewind():Void {
		position = 0;
		carried = 0;
		entering = 0;
		stepped = 0;
		served = 0;
		wrapped = 0;
	}

	public function silence():Void {
		hushing = true;
		poured = 0;
	}

	public inline function seconds():Float {
		return position / Tempo.TICKS;
	}

	public inline function tick():Int {
		return song.tempo.tickAt(position);
	}
}
