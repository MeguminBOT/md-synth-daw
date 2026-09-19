package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Project;
import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.Clip;
import mdd.song.Instrument;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Sample;
import mdd.song.Song;
import mdd.song.Track;

/**
	A declicked song keeps the edges the parts would otherwise click on smooth: a converter hit
	returns to the middle rather than stopping away from it, and an FM channel still sounding is
	let go just before the next note resets its phase. Each is measured as the energy through a
	fourth order high pass at 1.5 kHz from 1 ms before the edge to 6 ms after it, in decibels against
	the note's own level, rendered through the Mega Drive 2's output stage, the brighter of the two,
	with the switch off and on. The same measure taken in the middle of the note is the floor: what
	the tone and the part's own grain put through the filter. An edge that clicks stands clear of
	that floor with the switch off, and sits on it with the switch on. The 4 ms before that window
	are measured the same way, because that is where a fade runs, and a fade that clicked itself
	would only have moved the click.

	It also holds what the switch must not change: a slow attack still swells legato, the writes
	come out the same whatever length of span they are sequenced in, and the switch is saved.
**/
@:unreflective
class DeclickCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	/**
		Samples in the window a click is measured over: 1 ms before an edge and 6 ms after it.
	**/
	static inline final BEFORE = 44;

	static inline final AFTER = 264;

	/**
		Samples in the window before that, where a fade leading an edge runs: 4 ms.
	**/
	static inline final LEADING = 176;

	/**
		How far behind the register writes the rendered sound runs, in samples: the resampler's
		group delay. Found by `latency` rather than assumed, and every edge is measured where it is
		heard rather than where it was written.
	**/
	static var late:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  declick");

		latency();
		converter();
		retriggered();
		swelled();
		squares();
		spans();
		saved();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	/**
		Finds how far the rendered sound runs behind the writes: the converter stepping from the
		middle to a held byte on the first sample is heard where the step is half way up.
	**/
	static function latency():Void {
		final song = made();
		final held = new Sample("held", 16000, 60);
		final bytes = new Vector<Int>(1600);
		for (index in 0...bytes.length) bytes[index] = 0xC0;
		held.hold(bytes);
		song.sample(held);

		final step = new Instrument("step", Part.Dac);
		step.sample = 0;
		song.instrument(step);

		final pattern = song.add(new Pattern("step", 96));
		pattern.lane(Part.Dac).add(new Note(0, 48, 60, 127, song.instruments.length - 1));
		placed(song, pattern);

		final heard = rendered(song, false, Part.Dac);
		var top = 0.0;
		for (index in 0...2000) if (Math.abs(heard[index]) > top) top = Math.abs(heard[index]);

		late = 0;
		while (late < 2000 && Math.abs(heard[late]) < top / 2) late++;

		Sys.println("      the sound runs " + late + " samples behind the writes, where a step is heard half way up");
	}

	/**
		A hit cut by its note with nothing after it, and a hit that runs out away from the middle
		inside a longer note.
	**/
	static function converter():Void {
		final song = made();
		final tone = new Sample("tone", 16000, 60);
		final bytes = new Vector<Int>(4800);
		for (index in 0...bytes.length) bytes[index] = 128 + Math.round(100 * Math.sin(2 * Math.PI * 150 * index / 16000));
		tone.hold(bytes);
		song.sample(tone);

		final short = new Sample("short", 16000, 60);
		final ends = new Vector<Int>(1627);
		for (index in 0...ends.length) ends[index] = 128 + Math.round(100 * Math.sin(2 * Math.PI * 150 * index / 16000));
		short.hold(ends);
		song.sample(short);

		final cut = new Instrument("cut", Part.Dac);
		cut.sample = 0;
		song.instrument(cut);

		final runs = new Instrument("runs out", Part.Dac);
		runs.sample = 1;
		song.instrument(runs);

		final cutting = song.instruments.length - 2;
		final running = song.instruments.length - 1;

		final pattern = song.add(new Pattern("hits", 96 * 8));
		final cuts:Array<Int> = [];
		final outs:Array<Int> = [];

		for (index in 0...4) {
			pattern.lane(Part.Dac).add(new Note(index * 96, 23, 60, 127, cutting));
			cuts.push(index * 96 + 23);
		}

		for (index in 4...8) {
			pattern.lane(Part.Dac).add(new Note(index * 96, 48, 60, 127, running));
			outs.push(index * 96);
		}

		placed(song, pattern);

		final off = rendered(song, false, Part.Dac);
		final on = rendered(song, true, Part.Dac);
		final level = steady(off, song.tempo.samplesAt(10), 1200);

		compared("a hit cut by its note", off, on, [for (tick in cuts) song.tempo.samplesAt(tick)], null, level);
		compared("a hit running out off the middle", off, on,
			[for (tick in outs) song.tempo.samplesAt(tick) + Math.round(1627 * 44100 / 16000)],
			[for (tick in outs) song.tempo.samplesAt(tick + 48)], level);
	}

	/**
		A held sine on FM1 keyed on again every half beat, back to back and then with a gap its
		release is still sounding through.
	**/
	static function retriggered():Void {
		final song = made();
		final sine = sineOn(song, "sine", 31);
		final pattern = song.add(new Pattern("notes", 96 * 8));
		final strikes:Array<Int> = [];
		final gapped:Array<Int> = [];

		for (index in 0...8) {
			pattern.lane(Part.Fm1).add(new Note(index * 48, 48, 45, 110, sine));
			if (index > 0) strikes.push(index * 48);
		}

		for (index in 8...16) {
			pattern.lane(Part.Fm1).add(new Note(index * 48, 40, 45, 110, sine));
			if (index > 8) gapped.push(index * 48);
		}

		placed(song, pattern);

		final off = rendered(song, false, Part.Fm1);
		final on = rendered(song, true, Part.Fm1);
		final level = steady(off, song.tempo.samplesAt(12), 1200);

		Sys.println("      fades written: " + faded(song, false) + " off, " + faded(song, true) + " on");

		compared("an FM key on over a held note", off, on, [for (tick in strikes) song.tempo.samplesAt(tick)],
			null, level);
		compared("an FM key on over a release", off, on, [for (tick in gapped) song.tempo.samplesAt(tick)],
			null, level);
	}

	/**
		A slow attack keyed on over a held note swells from where the last one left the level,
		and letting it go first would be heard as a gap, so the switch leaves it exactly alone.
	**/
	static function swelled():Void {
		final song = made();
		final slow = sineOn(song, "slow", 14);
		final pattern = song.add(new Pattern("legato", 96 * 4));

		for (index in 0...8) pattern.lane(Part.Fm1).add(new Note(index * 48, 48, 45 + (index % 2) * 2, 110, slow));
		placed(song, pattern);

		final off = rendered(song, false, Part.Fm1);
		final on = rendered(song, true, Part.Fm1);
		var apart = 0.0;

		for (index in 0...off.length) {
			final gap = Math.abs(off[index] - on[index]);
			if (gap > apart) apart = gap;
		}

		says("a slow attack keeps its legato swell", apart == 0,
			"rendered with the switch on it sits " + (apart == 0 ? "exactly" : "up to " + apart + " away from")
			+ " where it sits with it off");
	}

	/**
		A square at 110 Hz on and off every half beat, and noise the same way. The squares reach
		the output through a resampler of their own, so their delay is found from their own first
		key on, where the first edge is heard half way up.
	**/
	static function squares():Void {
		for (part in [Part.Psg1, Part.Noise]) {
			final song = made();
			final held = song.instrumentAt(part.index());
			if (held != null && held.envelope != null) held.envelope.steps.push(0);

			final pattern = song.add(new Pattern("squares", 96 * 8));
			final ons:Array<Int> = [];
			final offs:Array<Int> = [];

			for (index in 0...8) {
				pattern.lane(part).add(new Note(index * 96, 48, 45, 127, part.index()));
				if (index > 0) ons.push(song.tempo.samplesAt(index * 96));
				offs.push(song.tempo.samplesAt(index * 96 + 48));
			}

			placed(song, pattern);

			final off = rendered(song, false, part);
			final high = highPassed(off);
			final writes = late;
			var top = 0.0;
			for (index in 0...2000) if (Math.abs(off[index]) > top) top = Math.abs(off[index]);
			late = 0;
			while (late < 2000 && Math.abs(off[late]) < top / 2) late++;

			final level = steady(off, song.tempo.samplesAt(12), 1200);
			final floor = clicks(high, [for (edge in offs) edge - 4000], level);
			final on = clicks(high, ons, level);
			final gone = clicks(high, offs, level);

			floor.sort(Reflect.compare);
			on.sort(Reflect.compare);
			gone.sort(Reflect.compare);

			Sys.println("      " + part.name() + " with the switch off, heard " + late + " samples behind the writes, through"
				+ " the high pass against the note: key on " + round(on[3]) + " dB, key off " + round(gone[3])
				+ " dB, over a floor of " + round(floor[3]));
			late = writes;
		}
	}

	/**
		What is written does not depend on how the song is cut into spans: the render thread takes
		short ones, an export long ones, and a fade or a return to the middle has to land in the
		same place either way.
	**/
	static function spans():Void {
		final song = made();
		final sine = sineOn(song, "sine", 31);
		final tone = new Sample("tone", 8000, 60);
		final bytes = new Vector<Int>(2400);
		for (index in 0...bytes.length) bytes[index] = 128 + Math.round(90 * Math.sin(2 * Math.PI * 300 * index / 8000));
		tone.hold(bytes);
		song.sample(tone);

		final hit = new Instrument("hit", Part.Dac);
		hit.sample = 0;
		song.instrument(hit);

		final struck = song.instruments.length - 1;

		final pattern = song.add(new Pattern("both", 96 * 8));

		for (index in 0...24) {
			pattern.lane(Part.Fm1).add(new Note(index * 29, 29, 45 + index % 5, 110, sine));
			pattern.lane(Part.Dac).add(new Note(index * 31 + 3, 17 + index % 3 * 7, 60, 127, struck));
		}

		placed(song, pattern);
		song.declick = true;

		final span = song.tempo.samplesAt(96 * 8) + 4000;
		final whole = new Stream(1 << 18);
		new Sequencer(song, null, 1 << 17).emit(whole, 0, span);

		var first = -2;
		var worst = "";

		for (block in [7, 64, 333, 1024]) {
			final pieces = new Stream(1 << 18);
			final sequencer = new Sequencer(song, null, 1 << 17);
			var at = 0;

			while (at < span) {
				final until = at + block < span ? at + block : span;
				sequencer.emit(pieces, at, until);
				at = until;
			}

			final differs = alike(whole, pieces);
			if (differs != -2 && first == -2) {
				first = differs;
				worst = block + " sample spans part at write " + differs + " of " + whole.count;
			}
		}

		says("spans of any length write the same", first == -2,
			first == -2 ? whole.count + " writes, the same in spans of 7, 64, 333 and 1024 samples as in one" : worst);
	}

	/**
		The switch is part of the song: saved and read back, and off for a project written before it
		existed.
	**/
	static function saved():Void {
		final song = made();
		song.declick = false;
		final back = Project.read(Project.text(song));

		song.declick = true;
		final again = Project.read(Project.text(song));

		final older = Project.read(StringTools.replace(Project.text(song), '"declick"', '"unknown"'));

		says("the switch is saved with the song", !back.declick && again.declick && !older.declick,
			"off reads back " + back.declick + ", on reads back " + again.declick + ", and a project without it reads "
			+ older.declick);
		says("a new song declicks", new Song().declick, "a song made from nothing starts with it " + new Song().declick);
	}

	/**
		@return A song with one instrument per part on the rack, and nothing else.
	**/
	static function made():Song {
		final song = new Song("declick", 96, 120);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			song.instrument(new Instrument(part.name().toLowerCase(), part));
			song.rack[index] = index;
		}

		return song;
	}

	/**
		@return The index of a new instrument on FM1 that is one sine at 110 Hz on the fourth
			operator, attacking at `attack` and releasing at 6.
	**/
	static function sineOn(song:Song, name:String, attack:Int):Int {
		final sine = new Instrument(name, Part.Fm1);
		final patch = sine.patch;

		patch.algorithm = 7;
		patch.feedback = 0;

		for (slot in 0...4) {
			patch.totalLevel[slot] = slot == 3 ? 16 : 127;
			patch.attack[slot] = attack;
			patch.decay[slot] = 0;
			patch.sustain[slot] = 0;
			patch.sustainLevel[slot] = 0;
			patch.release[slot] = 6;
			patch.multiple[slot] = 1;
			patch.detune[slot] = 0;
		}

		song.instrument(sine);
		return song.instruments.length - 1;
	}

	static function placed(song:Song, pattern:Pattern):Void {
		song.track(new Track("one")).add(new Clip(song.patterns.length - 1, 0, pattern.length));
	}

	/**
		@return The part rendered alone through the Mega Drive's output stage, as one channel, with
			the switch as given.
	**/
	static function rendered(song:Song, declick:Bool, part:Part):Vector<Float> {
		song.declick = declick;

		final mixing = new Mixing();
		mixing.kind = Mixing.WAV;
		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0.2;
		mixing.normalise = false;
		mixing.dither = false;
		mixing.console = mdd.play.Render.MODEL_TWO;

		final mix = Mixdown.made();
		mix.onlyPart = part.index();
		mix.runs(song, mixing);

		final out = new Vector<Float>(mix.frames);
		for (index in 0...mix.frames) out[index] = (mix.samples[index * 2] + mix.samples[index * 2 + 1]) / 2;
		return out;
	}

	/**
		@return The signal's level from `at` for `length` samples, as a root mean square.
	**/
	static function steady(signal:Vector<Float>, at:Int, length:Int):Float {
		var sum = 0.0;
		for (index in at...at + length) sum += signal[index] * signal[index];
		return Math.sqrt(sum / length);
	}

	/**
		Measures the clicks at every edge with the switch off and on. Where a hit has two edges
		that may click, `second` holds the other one and the louder of the pair is taken. The
		switch has to bring an edge standing at least 3 dB clear of the floor to within 1 dB of it.
	**/
	static function compared(name:String, off:Vector<Float>, on:Vector<Float>, edges:Array<Int>,
			second:Null<Array<Int>>, level:Float):Void {
		final high = highPassed(off);
		final low = highPassed(on);
		final was = louder(clicks(high, edges, level), second == null ? null : clicks(high, second, level));
		final now = louder(clicks(low, edges, level), second == null ? null : clicks(low, second, level));
		final floor = clicks(high, [for (edge in edges) edge - 4000], level);
		final leading = clicks(low, edges, level, -BEFORE - LEADING, LEADING);
		final middle = Math.floor(edges.length / 2);

		was.sort(Reflect.compare);
		now.sort(Reflect.compare);
		floor.sort(Reflect.compare);
		leading.sort(Reflect.compare);

		says(name, was[middle] >= floor[middle] + 3 && now[middle] <= floor[middle] + 1
			&& leading[leading.length - 1] <= floor[middle] + 1,
			"through the high pass at the edge, against the note: " + round(was[middle]) + " dB off, "
			+ round(now[middle]) + " dB on, over a floor of " + round(floor[middle]) + "; the 4 ms before it at most "
			+ round(leading[leading.length - 1]) + " dB on (medians of " + edges.length + "; loudest "
			+ round(was[was.length - 1]) + " and " + round(now[now.length - 1]) + ")");
	}

	/**
		@return Each of `one`, or the louder of it and the same place in `two` where there is one.
	**/
	static function louder(one:Array<Float>, two:Null<Array<Float>>):Array<Float> {
		if (two == null) return one;
		return [for (index in 0...one.length) one[index] > two[index] ? one[index] : two[index]];
	}

	/**
		@return At each edge, where it is heard, the level through the high pass from `from` samples
			after it for `length` samples, in decibels against `level`.
	**/
	static function clicks(high:Vector<Float>, edges:Array<Int>, level:Float, from:Int = -BEFORE,
			length:Int = BEFORE + AFTER):Array<Float> {
		return [
			for (edge in edges) {
				var sum = 0.0;
				for (index in edge + late + from...edge + late + from + length) sum += high[index] * high[index];
				20 * Math.log(Math.sqrt(sum / length) / level + 1e-12) / Math.log(10);
			}
		];
	}

	/**
		@return The signal through a fourth order high pass at 1.5 kHz: two second order sections.
	**/
	static function highPassed(signal:Vector<Float>):Vector<Float> {
		return section(section(signal));
	}

	static function section(signal:Vector<Float>):Vector<Float> {
		final omega = 2 * Math.PI * 1500 / 44100;
		final alpha = Math.sin(omega) / (2 * Math.sqrt(0.5));
		final cosine = Math.cos(omega);
		final norm = 1 + alpha;
		final b0 = (1 + cosine) / 2 / norm;
		final b1 = -(1 + cosine) / norm;
		final a1 = -2 * cosine / norm;
		final a2 = (1 - alpha) / norm;

		final out = new Vector<Float>(signal.length);
		var x1 = 0.0;
		var x2 = 0.0;
		var y1 = 0.0;
		var y2 = 0.0;

		for (index in 0...signal.length) {
			final x = signal[index];
			final y = b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2;
			x2 = x1;
			x1 = x;
			y2 = y1;
			y1 = y;
			out[index] = y;
		}

		return out;
	}

	/**
		@return How many release rate writes of 15 the song's stream holds with the switch as given.
	**/
	static function faded(song:Song, declick:Bool):Int {
		song.declick = declick;

		final stream = new Stream(1 << 16);
		new Sequencer(song).spanned(stream, 0, song.tempo.samplesAt(song.ends()) + 4000);

		var many = 0;
		var index = 0;

		while (index + 1 < stream.count) {
			if (stream.kindAt(index) == Stream.YM && stream.portAt(index) % 2 == 0 && stream.valueAt(index) >= 0x80
				&& stream.valueAt(index) < 0x90 && (stream.valueAt(index + 1) & 0x0F) == 0x0F) many++;
			index += 2;
		}

		return many;
	}

	static function alike(one:Stream, two:Stream):Int {
		final many = one.count < two.count ? one.count : two.count;

		for (index in 0...many) {
			if (one.tickAt(index) != two.tickAt(index) || one.kindAt(index) != two.kindAt(index)
				|| one.portAt(index) != two.portAt(index) || one.valueAt(index) != two.valueAt(index)) return index;
		}

		return one.count == two.count ? -2 : many;
	}

	static function round(value:Float):Float {
		return Math.round(value * 10) / 10;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 46) + said + (ok ? "" : "   FAILED"));
	}
}
