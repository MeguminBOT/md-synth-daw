package mdd.play;

import haxe.atomic.AtomicInt;
import haxe.ds.Vector;
import mdd.song.Song;
import mdd.song.Tempo;

@:unreflective
final class Mixdown {
	public static inline final PER_SECOND = 32768;
	public static inline final LEAST_ROOM = 1 << 20;
	public static inline final MOST_ROOM = 1 << 25;

	public var samples(default, null):Vector<cpp.Float32>;
	public var frames(default, null):Int = 0;
	public var channels(default, null):Int = 2;
	public var rate(default, null):Int = 44100;

	public var peak(default, null):Float = 0;
	public var gain(default, null):Float = 1;
	public var writes(default, null):Int = 0;
	public var lost(default, null):Int = 0;

	public static inline final WHOLE = 1000;

	public final reached:AtomicInt = new AtomicInt(0);
	public final stopping:AtomicInt = new AtomicInt(0);

	function new() {
		samples = new Vector<cpp.Float32>(0);
	}

	public static function roomFor(span:Int):Int {
		final seconds = span / Tempo.TICKS;
		final want = Std.int(seconds * PER_SECOND);

		return want < LEAST_ROOM ? LEAST_ROOM : (want > MOST_ROOM ? MOST_ROOM : want);
	}

	public inline function seconds():Float {
		return frames / rate;
	}

	public static function of(song:Song, mixing:Mixing):Mixdown {
		final made = new Mixdown();
		made.runs(song, mixing);

		return made;
	}

	public static function made():Mixdown {
		return new Mixdown();
	}

	public inline function reach():Float {
		return reached.load() / WHOLE;
	}

	public inline function stops():Void {
		stopping.store(1);
	}

	public inline function stopped():Bool {
		return stopping.load() != 0;
	}

	public function runs(song:Song, mixing:Mixing):Void {
		rate = mixing.worksAt();
		channels = mixing.channels();

		final span = song.tempo.samplesAt(song.ends());
		final sounding = Std.int(span * (rate / Tempo.TICKS));

		if (sounding <= 0) return;

		final ahead = Math.round(mixing.padStart * rate);
		final behind = Math.round(mixing.padEnd * rate);

		frames = ahead + sounding + behind;
		samples = new Vector<cpp.Float32>(frames * channels);

		for (index in 0...samples.length) samples[index] = 0;

		final stream = new Stream(roomFor(span));
		final sequencer = new Sequencer(song);

		sequencer.spanned(stream, 0, span);

		writes = stream.count;
		lost = sequencer.lost + stream.dropped;

		poured(stream, ahead, sounding + behind);
		faded(mixing, ahead);
		levelled(mixing);
	}

	function poured(stream:Stream, ahead:Int, many:Int):Void {
		final render = new Render(rate, Render.BLOCK);
		var done = 0;
		var told = 0;

		while (done < many) {
			if (stopped()) return;

			final from = Std.int(done * (Tempo.TICKS / rate));
			final took = render.serve(stream, from, Render.BLOCK, 0);

			if (took <= 0) break;

			for (index in 0...took) {
				final at = ahead + done + index;
				if (at >= frames) break;

				final left = render.block[index * 2];
				final right = render.block[index * 2 + 1];

				if (channels == 1) {
					samples[at] = (left + right) * 0.5;
					continue;
				}

				samples[at * 2] = left;
				samples[at * 2 + 1] = right;
			}

			done += took;

			final held = Std.int(done * WHOLE / many);

			if (held != told) {
				told = held;
				reached.store(held);
			}
		}

		reached.store(WHOLE);
	}

	function faded(mixing:Mixing, ahead:Int):Void {
		if (mixing.fade <= 0) return;

		final over = Math.round(mixing.fade * rate);
		if (over < 1 || over > frames) return;

		final from = frames - over;

		for (index in 0...over) {
			final much = 1.0 - index / over;
			final at = (from + index) * channels;

			for (side in 0...channels) samples[at + side] *= much;
		}
	}

	function levelled(mixing:Mixing):Void {
		peak = 0;

		for (index in 0...frames * channels) {
			final value = samples[index];
			final much = value < 0 ? -value : value;

			if (much > peak) peak = much;
		}

		gain = 1;

		if (!mixing.normalise || peak <= 0) return;

		final want = Math.pow(10, mixing.ceiling / 20.0);
		gain = want / peak;

		for (index in 0...frames * channels) samples[index] *= gain;

		peak = want;
	}
}
