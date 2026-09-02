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

	var heardPart:Int = -1;
	var heardNote:Int = 0;
	var heardLeft:Int = 0;
	var heardFresh:Bool = false;
	var hushing:Bool = false;
	final sounded:haxe.ds.Vector<Bool> = new haxe.ds.Vector<Bool>(Part.COUNT);

	var carried:Int = 0;

	public function new(song:Song, capacity:Int = 8192) {
		this.song = song;
		sequencer = new Sequencer(song);
		for (index in 0...Part.COUNT) sounded[index] = true;
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

		watched();

		if (hushing) {
			hushing = false;
			heardPart = -1;
			stream.reset(position);
			stream.lfo(position, song.lfoOn, song.lfoRate);
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

		gate.acquire();

		final ranged = looping && loopTo > loopFrom;
		final ending = ranged ? loopTo : ends();
		final bounded = ending > from;

		if (bounded && until > ending) until = ending;

		sequencer.emit(stream, from, until);
		auditioned(from);

		gate.release();
		served++;
		stepped = until - from;

		if (bounded && until >= ending) {
			if (looping) {
				position = ranged ? loopFrom : 0;
				wrapped++;
			} else {
				position = 0;
				playing = false;
				hushing = true;
			}
		} else {
			position = until;
		}

		return from;
	}

	function ends():Int {
		final alone = sequencer.alone;

		if (alone >= 0) {
			final pattern = song.patternAt(alone);
			return pattern == null ? 0 : song.tempo.samplesAt(pattern.length);
		}

		final last = song.ends();
		if (last <= 0) return 0;

		return song.tempo.samplesAt(last + song.tempo.ppqn * 4);
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
					stream.patch(at, part, instrument.patch, 110, song.pan[heardPart]);
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

	function watched():Void {
		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final now = song.audible(part);

			if (now == sounded[index]) continue;

			sounded[index] = now;
			if (now) continue;

			stream.silence(position, part);
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
	}

	public inline function seconds():Float {
		return position / Tempo.TICKS;
	}

	public inline function tick():Int {
		return song.tempo.tickAt(position);
	}
}
