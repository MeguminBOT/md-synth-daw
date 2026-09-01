package mdd.play;

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

	public var source:Null<Stream> = null;
	var poured:Int = 0;

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
	}

	public function seek(tick:Int):Void {
		position = tick < 0 ? 0 : tick;
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

		if (!playing) {
			stepped = 0;
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

	function replayed(from:Int, until:Int):Void {
		final held = source;
		if (held == null) return;

		if (poured > held.count || held.tickAt(poured) > from) poured = 0;

		while (poured < held.count && held.tickAt(poured) < from) poured++;

		while (poured < held.count && held.tickAt(poured) < until) {
			stream.raw(held.tickAt(poured), held.kindAt(poured), held.portAt(poured),
				held.valueAt(poured));
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
		stream.clear();
		stream.reset(position);
		poured = 0;
	}

	public inline function seconds():Float {
		return position / Tempo.TICKS;
	}

	public inline function tick():Int {
		return song.tempo.tickAt(position);
	}
}
