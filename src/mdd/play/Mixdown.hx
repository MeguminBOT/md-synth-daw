package mdd.play;

import haxe.atomic.AtomicInt;
import haxe.ds.Vector;
import mdd.song.Song;
import mdd.song.Tempo;

/**
	The offline render an export is: the whole song through the same sequencer, the
	same register stream and the same render path playback uses, into one float buffer.

	It runs on a worker thread while the interface keeps drawing, so every long loop in
	it reaches a collector safe point. A thread that never allocates never lets the
	collector run, and telling the collector to ignore the thread instead frees what
	only that thread is holding: a bounce came back marked stopped with nothing having
	stopped it. The render and the stream are held in fields here for the same reason,
	because a field is traced and a register may not be.
**/
@:unreflective
final class Mixdown {
	public static inline final PER_SECOND = 32768;
	public static inline final LEAST_ROOM = 1 << 20;
	public static inline final MOST_ROOM = 1 << 25;

	public var samples(default, null):Vector<cpp.Float32>;
	public var frames(default, null):Int = 0;
	public var channels(default, null):Int = 2;
	public var rate(default, null):Int = 44100;
	public var console(default, null):Int = Render.MODEL_ONE;

	public var peak(default, null):Float = 0;
	public var gain(default, null):Float = 1;
	public var writes(default, null):Int = 0;
	public var lost(default, null):Int = 0;

	public static inline final WHOLE = 1000;
	static inline final RESTS = 1 << 16;

	var working:Null<Render> = null;
	var feeding:Null<Stream> = null;

	public final reached:AtomicInt = new AtomicInt(0);
	public final stopping:AtomicInt = new AtomicInt(0);

	/**
		Private: use `of` or `made`.
	**/
	function new() {
		samples = new Vector<cpp.Float32>(0);
	}

	/**
		@param span How many samples the export covers.
		@return How many floats a buffer needs to hold it, in stereo.
	**/
	public static function roomFor(span:Int):Int {
		final seconds = span / Tempo.TICKS;
		final want = Std.int(seconds * PER_SECOND);

		return want < LEAST_ROOM ? LEAST_ROOM : (want > MOST_ROOM ? MOST_ROOM : want);
	}

	/**
		@return How long the rendered audio is, in seconds.
	**/
	public inline function seconds():Float {
		return frames / rate;
	}

	/**
		Builds a mixdown and runs it, which is the whole of an export render.

		@param song The song to render.
		@param mixing What the export is set to.
		@return The finished mixdown, with its samples in place.
	**/
	public static function of(song:Song, mixing:Mixing):Mixdown {
		final made = new Mixdown();
		made.runs(song, mixing);

		return made;
	}

	/**
		Builds an empty mixdown for a caller that will drive `runs` itself. Construction
		goes through a static because hxcpp emits a dynamic constructor for every class
		and a `Dynamic` cannot unbox into a `cpp.Star`.

		@return An empty mixdown.
	**/
	public static function made():Mixdown {
		return new Mixdown();
	}

	/**
		@return How far through the render is, 0 to 1, for a progress bar to read from another
			thread.
	**/
	public inline function reach():Float {
		return reached.load() / WHOLE;
	}

	/**
		Asks the render to stop at the next block. Safe from another thread.
	**/
	public inline function stops():Void {
		stopping.store(1);
	}

	/**
		@return Whether it was asked to stop.
	**/
	public inline function stopped():Bool {
		return stopping.load() != 0;
	}

	/**
		Renders the whole song: sequence it, render it, pad it, fade it and normalise
		it. This is the worker thread.

		@param song The song to render.
		@param mixing What the export is set to.
	**/
	public function runs(song:Song, mixing:Mixing):Void {
		rate = mixing.worksAt();
		channels = mixing.channels();
		console = mixing.console;

		final span = song.tempo.samplesAt(song.ends());
		final sounding = Std.int(span * (rate / Tempo.TICKS));

		if (sounding <= 0) {
			reached.store(WHOLE);
			return;
		}

		final ahead = Math.round(mixing.padStart * rate);
		final behind = Math.round(mixing.padEnd * rate);

		frames = ahead + sounding + behind;
		samples = new Vector<cpp.Float32>(frames * channels);

		var wiped = 0;

		while (wiped < samples.length) {
			final until = wiped + RESTS < samples.length ? wiped + RESTS : samples.length;

			while (wiped < until) {
				samples[wiped] = 0;
				wiped++;
			}

			cpp.vm.Gc.safePoint();
		}

		feeding = new Stream(roomFor(span));

		final stream = feeding;
		final sequencer = new Sequencer(song);

		sequencer.spanned(stream, 0, span);

		writes = stream.count;
		lost = sequencer.lost + stream.dropped;

		poured(stream, ahead, sounding + behind);
		faded(mixing, ahead);
		levelled(mixing);

		working = null;
		feeding = null;

		reached.store(WHOLE);
	}

	/**
		Renders one span of the stream into the samples buffer, a block at a time, with
		a collector safe point between blocks.

		@param stream The register writes for the span.
		@param ahead How many samples of silence come before the piece.
		@param many How many samples this span covers.
	**/
	function poured(stream:Stream, ahead:Int, many:Int):Void {
		working = new Render(rate, Render.BLOCK);

		final render = working;
		render.console = console;
		var done = 0;
		var told = 0;

		while (done < many) {
			if (stopped()) break;

			cpp.vm.Gc.safePoint();

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

			final held = Std.int(done * (WHOLE - 1.0) / many);

			if (held != told) {
				told = held;
				reached.store(held);
			}
		}
	}

	/**
		Applies the fade at the end of the piece.

		@param mixing What the export is set to.
		@param ahead How many samples of silence come before the piece.
	**/
	function faded(mixing:Mixing, ahead:Int):Void {
		if (mixing.fade <= 0) return;

		final over = Math.round(mixing.fade * rate);
		if (over < 1 || over > frames) return;

		final from = frames - over;

		var index = 0;

		while (index < over) {
			final until = index + RESTS < over ? index + RESTS : over;

			while (index < until) {
				final much = 1.0 - index / over;
				final at = (from + index) * channels;

				for (side in 0...channels) samples[at + side] *= much;
				index++;
			}

			cpp.vm.Gc.safePoint();
		}
	}

	/**
		Finds the peak and scales the whole buffer so it lands on the ceiling.

		@param mixing What the export is set to.
	**/
	function levelled(mixing:Mixing):Void {
		peak = 0;

		final many = frames * channels;
		var index = 0;

		while (index < many) {
			final until = index + RESTS < many ? index + RESTS : many;

			while (index < until) {
				final value = samples[index];
				final much = value < 0 ? -value : value;

				if (much > peak) peak = much;
				index++;
			}

			cpp.vm.Gc.safePoint();
		}

		gain = 1;

		if (!mixing.normalise || peak <= 0) return;

		final want = Math.pow(10, mixing.ceiling / 20.0);
		gain = want / peak;

		var scaled = 0;

		while (scaled < many) {
			final until = scaled + RESTS < many ? scaled + RESTS : many;

			while (scaled < until) {
				samples[scaled] *= gain;
				scaled++;
			}

			cpp.vm.Gc.safePoint();
		}

		peak = want;
	}
}
