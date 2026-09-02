package mdd.gate;

import haxe.ds.Vector;
import mdd.play.Stream;
import mdd.song.Tempo;

@:unreflective
class DriftCheck {
	static inline final SECONDS = 30;
	static inline final GAP = 2205;

	static final CLASSES:Array<Int> = [0x22, 0x27, 0x28, 0x2A, 0x2B, 0x30, 0x40, 0x50, 0x60,
		0x70, 0x80, 0x90, 0xA0, 0xA8, 0xB0, 0xB4];

	static final NAMES:Array<String> = ["LFO", "TIMER", "KEY", "DAC DATA", "DAC ON", "DT MUL",
		"TL", "KS AR", "AM D1R", "D2R", "D1L RR", "SSG", "FREQ", "FM3 FREQ", "FB ALG", "SIDES"];

	public static function run(args:Array<String>):Int {
		final where = Gate.root + "/vendor/vgm";

		if (!sys.FileSystem.isDirectory(where)) {
			Sys.println("  drift: no vgm beside the build");
			return 1;
		}

		var want = "Green Hill";
		for (arg in args) if (!StringTools.startsWith(arg, "-")) want = arg;

		var name = "";
		for (held in sys.FileSystem.readDirectory(where)) {
			if (held.indexOf(want) < 0) continue;
			name = held;
		}

		if (name == "") {
			Sys.println("  drift: nothing here is called '" + want + "'");
			return 1;
		}

		Sys.println("  drift");
		Sys.println("    " + name + ", " + SECONDS + " s");

		final source = new Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;
		final made = played(song, Tempo.TICKS * SECONDS);

		classes(source, made);
		converter(source, made);
		kitted(song);
		paced(source);
		return 0;
	}

	static function played(song:mdd.song.Song, span:Int):Stream {
		final made = new Stream(1 << 22);
		final transport = new mdd.play.Transport(song, 1 << 18);

		transport.play();

		var done = 0;

		while (done < span) {
			transport.advance(mdd.play.Render.BLOCK, 44100);
			final held = transport.stream;

			for (index in 0...held.count) {
				made.raw(held.tickAt(index), held.kindAt(index), held.portAt(index),
					held.valueAt(index));
			}

			done += Std.int(mdd.play.Render.BLOCK * (Tempo.TICKS / 44100.0));
			if (made.count > made.capacity - 4096) break;
		}

		return made;
	}

	static function group(address:Int):Int {
		if (address < 0x30) {
			for (index in 0...CLASSES.length) if (CLASSES[index] == address) return index;
			return -1;
		}

		if (address >= 0xA8 && address <= 0xAE) return CLASSES.indexOf(0xA8);
		if (address >= 0xB4) return CLASSES.indexOf(0xB4);
		if (address >= 0xB0) return CLASSES.indexOf(0xB0);
		if (address >= 0xA0) return CLASSES.indexOf(0xA0);

		return CLASSES.indexOf(address & 0xF0);
	}

	static function counted(stream:Stream, until:Int):Vector<Int> {
		final many = new Vector<Int>(CLASSES.length);
		for (index in 0...many.length) many[index] = 0;

		final shadow = new Vector<Int>(512);
		for (index in 0...shadow.length) shadow[index] = -1;

		var half = 0;
		var address = -1;

		for (index in 0...stream.count) {
			if (stream.tickAt(index) > until) break;
			if (stream.kindAt(index) != Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (address < 0) continue;

			final at = (half << 8) | address;
			final moved = shadow[at] != value;
			shadow[at] = value;

			if (!moved && address != 0x28 && address != 0x2A) continue;

			final which = group(address);
			if (which >= 0) many[which]++;
		}

		return many;
	}

	static function classes(source:Stream, made:Stream):Void {
		final until = Tempo.TICKS * SECONDS;

		final one = counted(source, until);
		final two = counted(made, until);

		Sys.println("");
		Sys.println("    writes that change a register, the file against the song");
		Sys.println("");

		for (index in 0...CLASSES.length) {
			if (one[index] == 0 && two[index] == 0) continue;

			final away = two[index] - one[index];

			Sys.println("      " + StringTools.rpad(NAMES[index], " ", 10)
				+ StringTools.lpad("" + one[index], " ", 8)
				+ StringTools.lpad("" + two[index], " ", 8)
				+ StringTools.lpad((away > 0 ? "+" : "") + away, " ", 9)
				+ (one[index] > 0 && two[index] == 0 ? "   the song never writes these" : ""));
		}
	}

	static function starts(stream:Stream, until:Int):Array<Int> {
		final found:Array<Int> = [];

		var half = 0;
		var address = -1;
		var last = -GAP * 2;

		for (index in 0...stream.count) {
			final at = stream.tickAt(index);
			if (at > until) break;
			if (stream.kindAt(index) != Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (half != 0 || address != 0x2A) continue;

			if (at - last > GAP) found.push(at);
			last = at;
		}

		return found;
	}

	static function converter(source:Stream, made:Stream):Void {
		final until = Tempo.TICKS * SECONDS;

		final one = starts(source, until);
		final two = starts(made, until);

		Sys.println("");
		Sys.println("    the converter, " + one.length + " hits in the file against "
			+ two.length + " in the song");
		Sys.println("");

		final many = one.length < two.length ? one.length : two.length;

		var worst = 0;
		var total = 0.0;
		var late = 0;

		for (index in 0...many) {
			final away = two[index] - one[index];
			final much = away < 0 ? -away : away;

			total += much;
			if (much > worst) worst = much;
			if (away > 0) late++;
		}

		for (index in 0...(many < 16 ? many : 16)) {
			final away = two[index] - one[index];

			Sys.println("      hit " + StringTools.lpad("" + (index + 1), " ", 3)
				+ StringTools.lpad(said(one[index]), " ", 12)
				+ StringTools.lpad(said(two[index]), " ", 12)
				+ StringTools.lpad((away > 0 ? "+" : "") + Math.round(away * 1000.0
					/ Tempo.TICKS) + " ms", " ", 12));
		}

		if (many == 0) return;

		Sys.println("");
		Sys.println("      worst " + Math.round(worst * 1000.0 / Tempo.TICKS)
			+ " ms, mean " + Math.round(total / many * 1000.0 / Tempo.TICKS) + " ms, "
			+ late + " of " + many + " late");
	}

	static function kitted(song:mdd.song.Song):Void {
		var bytes = 0;
		for (sample in song.samples) bytes += sample.length();

		Sys.println("");
		Sys.println("    the converter made " + song.samples.length + " samples of " + bytes
			+ " bytes");
		Sys.println("");

		final seen:Array<Int> = [];
		var reused = 0;
		var many = 0;

		for (pattern in song.patterns) {
			final lane = pattern.lane(mdd.song.Part.Dac);

			for (note in lane.notes) {
				many++;

				if (seen.indexOf(note.instrument) >= 0) reused++;
				else seen.push(note.instrument);

				if (many > 24) continue;

				final sample = held(song, note.instrument);

				Sys.println("      hit " + StringTools.lpad("" + many, " ", 3)
					+ StringTools.lpad(said(song.tempo.samplesAt(note.at)), " ", 12)
					+ "  instrument " + StringTools.lpad("" + note.instrument, " ", 4)
					+ StringTools.lpad(sample == null ? "none" : sample.length() + " bytes",
						" ", 14)
					+ StringTools.lpad(sample == null ? "" : sample.rate + " Hz", " ", 10));
			}
		}

		Sys.println("");
		Sys.println("      " + many + " hits, " + seen.length + " of them naming a sample of"
			+ " their own and " + reused + " reusing one");
	}

	static function paced(source:Stream):Void {
		final until = Tempo.TICKS * SECONDS;
		final when:Array<Int> = [];

		var half = 0;
		var address = -1;

		for (index in 0...source.count) {
			final at = source.tickAt(index);
			if (at > until) break;
			if (source.kindAt(index) != Stream.YM) continue;

			final port = source.portAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = source.valueAt(index);
				continue;
			}

			if (half == 0 && address == 0x2A) when.push(at);
		}

		Sys.println("");
		Sys.println("    how the file paces its converter writes");
		Sys.println("");

		var head = 0;
		var shown = 0;

		while (head < when.length && shown < 12) {
			var tail = head;
			while (tail + 1 < when.length && when[tail + 1] - when[tail] <= GAP) tail++;

			final many = tail - head + 1;
			final span = when[tail] - when[head] + 1;

			final gaps:Array<Int> = [];
			for (index in head...tail) gaps.push(when[index + 1] - when[index]);
			gaps.sort(function(a:Int, b:Int):Int return a - b);

			final middle = gaps.length == 0 ? 0 : gaps[gaps.length >> 1];
			final widest = gaps.length == 0 ? 0 : gaps[gaps.length - 1];

			Sys.println("      run " + StringTools.lpad("" + (shown + 1), " ", 3)
				+ StringTools.lpad(said(when[head]), " ", 11)
				+ StringTools.lpad("" + many, " ", 8) + " bytes"
				+ StringTools.lpad("" + Math.round(span * 1000.0 / Tempo.TICKS), " ", 7) + " ms"
				+ "   mean " + StringTools.lpad("" + Math.round(many * Tempo.TICKS
					/ (span < 1 ? 1 : span)), " ", 6) + " Hz"
				+ "   median gap " + StringTools.lpad("" + middle, " ", 3)
				+ " so " + StringTools.lpad("" + (middle < 1 ? 0
					: Math.round(Tempo.TICKS / middle)), " ", 6) + " Hz"
				+ "   widest gap " + StringTools.lpad("" + widest, " ", 6)
				+ "   over 16/64/256/1024 " + wider(gaps, 16) + "/" + wider(gaps, 64)
				+ "/" + wider(gaps, 256) + "/" + wider(gaps, 1024));

			shown++;
			head = tail + 1;
		}
	}

	static function wider(gaps:Array<Int>, than:Int):Int {
		var many = 0;
		for (gap in gaps) if (gap > than) many++;

		return many;
	}

	static function held(song:mdd.song.Song, named:Int):Null<mdd.song.Sample> {
		final instrument = song.instrumentAt(named);
		if (instrument == null) return null;

		return song.sampleAt(instrument.sample);
	}

	static function said(at:Int):String {
		return "" + (Math.round(at * 1000.0 / Tempo.TICKS) / 1000.0) + " s";
	}
}
