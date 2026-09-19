package mdd.play;

import mdd.host.Atomic;
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

	public var samples(default, null):Vector<cpp.Float32>;
	public var frames(default, null):Int = 0;
	public var channels(default, null):Int = 2;
	public var rate(default, null):Int = 44100;
	public var console(default, null):Int = Render.MODEL_ONE;

	/**
		Whether the writes smooth the edges the parts would otherwise click on, taken from the
		export's own settings.
	**/
	public var declick(default, null):Bool = true;

	/**
		Whether the writes end what nothing is playing, taken from the export's own settings.
	**/
	public var stuck(default, null):Bool = false;

	public var peak(default, null):Float = 0;
	public var gain(default, null):Float = 1;
	public var writes(default, null):Int = 0;
	public var lost(default, null):Int = 0;

	public static inline final WHOLE = 1000;
	static inline final RESTS = 1 << 16;

	/**
		How long the output stage is run before anything is recorded, in seconds.

		The coupling capacitor is a high pass, and a render that starts with it at rest
		steps its own resting offset through it: the six channels each sit at a constant
		offset even in silence, and the sum of those is a step at sample nought. Running
		it through silence first settles the filter, so a bounce begins where a console
		that has been switched on for a while begins.

		It matters most for stems: every stem holds a different number of resting
		channels, so without this each one carries a different thump and the set of them
		no longer sums to the mix.
	**/
	static inline final SETTLE = 0.100;

	var working:Null<Render> = null;
	var feeding:Null<Stream> = null;

	/**
		Which part this render is of, or -1 for the whole mix.
	**/
	public var onlyPart:Int = -1;

	/**
		Which track this render is of, by index, or -1 for the whole mix.
	**/
	public var onlyTrack:Int = -1;

	/**
		The gain to scale by instead of working one out, or nought to work one out.

		A stem takes the gain the mix arrived at, so the stems sum back to the mix. A
		stem normalised on its own would come back at whatever loudness it happened to
		reach, and the set of them would sum to something else entirely.
	**/
	public var sharedGain:Float = 0;

	/**
		How many renders this job is, so a progress bar spans all of them rather than
		jumping back to nothing at every stem.
	**/
	public final passes:Atomic = new Atomic(1);

	/**
		Which of those renders is running.
	**/
	public final pass:Atomic = new Atomic(0);

	/**
		How far through the render in hand it is, from nought to `WHOLE`.
	**/
	public final reached:Atomic = new Atomic(0);

	/**
		How far through the whole job it is, from nought to `WHOLE`.

		A reader takes this one reading rather than working it out from the pass, the
		count of passes and the progress within one. Those are three values a thread
		cannot change together, and a reader landing between two of them at a pass
		boundary combines a pass that has started with the one before it finishing,
		which reads as a bar that jumps backwards.
	**/
	final whole:Atomic = new Atomic(0);
	public final stopping:Atomic = new Atomic(0);

	/**
		Private: use `of` or `made`.
	**/
	function new() {
		samples = new Vector<cpp.Float32>(0);
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
		@return How far through the whole job is, 0 to 1, for a progress bar to read from
			another thread. Where the job is several renders this spans all of them.
	**/
	public function reach():Float {
		return whole.load() / WHOLE;
	}

	/**
		Says how many renders this job is, before any of them start.

		@param many How many.
	**/
	public function spans(many:Int):Void {
		passes.store(many < 1 ? 1 : many);
		marked();
	}

	/**
		Moves on to the next render of the job.

		@param which Which one is starting, counted from nought.
	**/
	public function steps(which:Int):Void {
		pass.store(which);
		reached.store(0);
		marked();
	}

	/**
		Says how far through the render in hand it is.

		@param much How far, from nought to `WHOLE`.
	**/
	function reaching(much:Int):Void {
		reached.store(much);
		marked();
	}

	/**
		Works the whole job out into the one value a reader takes.
	**/
	function marked():Void {
		final many = passes.load();
		final inner = reached.load();

		final held = many <= 1 ? inner
			: Std.int((pass.load() * WHOLE + inner) / many);

		whole.store(held < 0 ? 0 : (held > WHOLE ? WHOLE : held));
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
		declick = mixing.declick;
		stuck = mixing.stuck;

		final span = song.tempo.samplesAt(song.ends());
		final sounding = Std.int(span * (rate / Tempo.TICKS));

		if (sounding <= 0) {
			reaching(WHOLE);
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

		feeding = Stream.reserved(span);

		final stream = feeding;
		final sequencer = new Sequencer(song);
		sequencer.declick = declick;
		sequencer.stuck = stuck;
		sequencer.onlyPart = onlyPart;
		sequencer.onlyTrack = onlyTrack;

		sequencer.spanned(stream, 0, span);

		writes = stream.count;
		lost = sequencer.lost + stream.dropped;

		poured(stream, ahead, sounding + behind);
		faded(mixing, ahead);
		levelled(mixing);

		working = null;
		feeding = null;

		reaching(WHOLE);
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

		var warmed = 0;
		final warming = Std.int(rate * SETTLE);

		while (warmed < warming) {
			final took = render.fill(Render.BLOCK);
			if (took <= 0) break;

			warmed += took;
		}

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
				reaching(held);
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

		if (sharedGain > 0) gain = sharedGain;
		else {
			if (!mixing.normalise || peak <= 0) return;
			gain = Math.pow(10, mixing.ceiling / 20.0) / peak;
		}

		if (gain == 1) return;

		var scaled = 0;

		while (scaled < many) {
			final until = scaled + RESTS < many ? scaled + RESTS : many;

			while (scaled < until) {
				samples[scaled] *= gain;
				scaled++;
			}

			cpp.vm.Gc.safePoint();
		}

		peak *= gain;
	}
}
