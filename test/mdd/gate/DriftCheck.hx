package mdd.gate;

import haxe.ds.Vector;
import mdd.play.Render;
import mdd.play.Stream;
import mdd.song.Tempo;

@:unreflective
class DriftCheck {
	static inline final SECONDS = 30;
	static inline final FRAME = 735;
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

		for (index in 0...args.length) {
			if (StringTools.startsWith(args[index], "-")) continue;
			if (index > 0 && StringTools.startsWith(args[index - 1], "-")) continue;

			want = args[index];
		}

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

		final whole = played(song, song.tempo.samplesAt(song.ends()));

		trace = args.indexOf("--trace") >= 0;
		watch = seconds(args, "--channel", 0);

		squared(source, whole, seconds(args, "--from", 0), seconds(args, "--to", 60));

		keyed(source, whole, seconds(args, "--from", 0), seconds(args, "--to", 60));
		moved(source, whole, seconds(args, "--from", 0), seconds(args, "--to", 60), 0);
		moved(source, whole, seconds(args, "--from", 0), seconds(args, "--to", 60), 1);

		if (args.indexOf("--lanes") >= 0) {
			laned(song, seconds(args, "--from", 0), seconds(args, "--to", 60),
				seconds(args, "--channel", 3));
		}

		hissed(source, whole, seconds(args, "--from", 0), seconds(args, "--to", 45));

		classes(source, made);
		converter(source, made);
		kitted(song);
		paced(source);
		return 0;
	}

	static function seconds(args:Array<String>, want:String, fallback:Int):Int {
		final at = args.indexOf(want);
		if (at < 0 || at + 1 >= args.length) return fallback;

		final held = Std.parseInt(args[at + 1]);
		return held == null ? fallback : held;
	}

	static function squares(stream:Stream, at:Int, until:Int, period:Vector<Int>,
			level:Vector<Int>, latched:Vector<Int>):Int {
		var index = at;

		while (index < stream.count && stream.tickAt(index) <= until) {
			if (stream.kindAt(index) != Stream.PSG) {
				index++;
				continue;
			}

			final value = stream.valueAt(index);
			index++;

			if ((value & 0x80) != 0) {
				latched[0] = (value >> 4) & 7;

				final channel = latched[0] >> 1;

				if ((latched[0] & 1) != 0) level[channel] = value & 0x0F;
				else period[channel] = (period[channel] & 0x3F0) | (value & 0x0F);

				continue;
			}

			final channel = latched[0] >> 1;

			if ((latched[0] & 1) != 0) level[channel] = value & 0x0F;
			else period[channel] = (period[channel] & 0x0F) | ((value & 0x3F) << 4);
		}

		return index;
	}

	static var trace:Bool = false;
	static var watch:Int = 0;

	static function stepped(stream:Stream, from:Int, to:Int, channel:Int,
			levels:Bool):Array<Int> {
		final found:Array<Int> = [];
		final period = new Vector<Int>(4);
		final level = new Vector<Int>(4);
		final latched = new Vector<Int>(1);

		for (index in 0...4) {
			period[index] = -1;
			level[index] = 15;
		}

		latched[0] = 0;

		var at = 0;
		var was = levels ? 15 : -1;

		while (at < stream.count) {
			final tick = stream.tickAt(at);
			if (tick > to) break;

			at = squares(stream, at, tick, period, level, latched);

			final now = levels ? level[channel] : period[channel];

			if (now != was) {
				was = now;

				if (tick >= from) {
					found.push(tick);
					found.push(now);
				}
			}
		}

		return found;
	}

	static function squared(source:Stream, made:Stream, from:Int, to:Int):Void {
		Sys.println("");
		Sys.println("    every square change, the file against the song, from " + from
			+ " s to " + to + " s");
		Sys.println("");

		for (channel in 0...4) {
			paired(source, made, from * Tempo.TICKS, to * Tempo.TICKS, channel, true);
			paired(source, made, from * Tempo.TICKS, to * Tempo.TICKS, channel, false);
		}
	}

	static function paired(source:Stream, made:Stream, from:Int, to:Int, channel:Int,
			levels:Bool):Void {
		final one = stepped(source, from, to, channel, levels);
		final two = stepped(made, from, to, channel, levels);

		if (one.length == 0 && two.length == 0) return;

		final missed = tracked(one, two);
		final many = one.length >> 1;

		Sys.println("      " + StringTools.rpad(channel == 3 ? "NOISE"
			: "PSG" + (channel + 1), " ", 7)
			+ StringTools.rpad(levels ? "level" : "period", " ", 8)
			+ StringTools.lpad("" + many, " ", 6) + " in the file, "
			+ StringTools.lpad("" + (two.length >> 1), " ", 6) + " in the song, "
			+ StringTools.lpad("" + missed, " ", 5) + " of " + weighed
			+ " the song does not reach, "
			+ (weighed < 1 ? 0 : Math.round(missed * 100.0 / weighed)) + " per cent");
	}

	static function struck(stream:Stream, from:Int, to:Int, channel:Int):Array<Int> {
		final found:Array<Int> = [];

		var half = 0;
		var address = -1;
		var was = false;

		for (index in 0...stream.count) {
			final tick = stream.tickAt(index);
			if (tick > to) break;
			if (stream.kindAt(index) != Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (half != 0 || address != 0x28) continue;

			final within = value & 3;
			if (within == 3) continue;

			if (within + ((value & 4) != 0 ? 3 : 0) != channel) continue;

			final on = (value & 0xF0) != 0;
			if (on == was) continue;

			was = on;

			if (tick < from) continue;

			found.push(tick);
			found.push(on ? 1 : 0);
		}

		return found;
	}

	static function keyed(source:Stream, made:Stream, from:Int, to:Int):Void {
		Sys.println("");
		Sys.println("    every fm key edge, the file against the song, from " + from
			+ " s to " + to + " s");
		Sys.println("");

		for (channel in 0...6) {
			final one = struck(source, from * Tempo.TICKS, to * Tempo.TICKS, channel);
			final two = struck(made, from * Tempo.TICKS, to * Tempo.TICKS, channel);

			if (one.length == 0 && two.length == 0) continue;

			final many = (one.length < two.length ? one.length : two.length) >> 1;

			var wrong = 0;
			var worst = 0;
			var total = 0.0;
			var said = "";

			for (index in 0...many) {
				if (one[index * 2 + 1] != two[index * 2 + 1]) {
					wrong++;

					if (said == "") {
						said = "   first at " + round(one[index * 2] / Tempo.TICKS, 2)
							+ " s the file goes " + (one[index * 2 + 1] == 1 ? "on" : "off")
							+ " and the song goes "
							+ (two[index * 2 + 1] == 1 ? "on" : "off");
					}

					continue;
				}

				final away = two[index * 2] - one[index * 2];
				final much = away < 0 ? -away : away;

				total += much;
				if (much > worst) worst = much;
			}

			Sys.println("      " + StringTools.rpad("FM" + (channel + 1), " ", 8)
				+ StringTools.lpad("" + (one.length >> 1), " ", 6) + " in the file, "
				+ StringTools.lpad("" + (two.length >> 1), " ", 6) + " in the song, "
				+ StringTools.lpad("" + wrong, " ", 5) + " the wrong way, worst "
				+ StringTools.lpad("" + Math.round(worst * 1000.0 / Tempo.TICKS), " ", 5)
				+ " ms out, mean "
				+ round(many < 1 ? 0 : total / many * 1000.0 / Tempo.TICKS, 1) + " ms" + said);
		}
	}

	static function changes(stream:Stream, from:Int, to:Int, channel:Int,
			kind:Int):Array<Int> {
		final found:Array<Int> = [];
		final shadow = new Vector<Int>(4);

		for (index in 0...4) shadow[index] = -1;

		final wanted = channel >= 3 ? 1 : 0;
		final within = channel % 3;

		var half = 0;
		var address = -1;
		var was = -1;

		for (index in 0...stream.count) {
			final tick = stream.tickAt(index);
			if (tick > to) break;
			if (stream.kindAt(index) != Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (half != wanted) continue;

			if (kind == 0) {
				if (address < 0x40 || address > 0x4F) continue;
				if ((address & 3) != within) continue;

				shadow[(address - 0x40) >> 2] = value & 0x7F;
			} else {
				if (address == 0xA4 + within) shadow[0] = value & 0x3F;
				else if (address == 0xA0 + within) shadow[1] = value & 0xFF;
				else continue;
			}

			var now = 0;

			if (kind == 0) {
				var ready = true;
				for (slot in 0...4) if (shadow[slot] < 0) ready = false;
				if (!ready) continue;

				for (slot in 0...4) now = now * 128 + shadow[slot];
			} else {
				if (shadow[0] < 0 || shadow[1] < 0 || address != 0xA0 + within) continue;
				now = (shadow[0] << 8) | shadow[1];
			}

			if (now == was) continue;
			was = now;

			if (tick < from) continue;

			found.push(tick);
			found.push(now);
		}

		return found;
	}

	static function moved(source:Stream, made:Stream, from:Int, to:Int, kind:Int):Void {
		Sys.println("");
		Sys.println("    every " + (kind == 0 ? "level" : "pitch") + " change on an fm channel,"
			+ " the file against the song, from " + from + " s to " + to + " s");
		Sys.println("");

		for (channel in 0...6) {
			final one = changes(source, from * Tempo.TICKS, to * Tempo.TICKS, channel, kind);
			final two = changes(made, from * Tempo.TICKS, to * Tempo.TICKS, channel, kind);

			if (one.length == 0 && two.length == 0) continue;

			final apart = settled(one, two, from * Tempo.TICKS, to * Tempo.TICKS, kind);

			Sys.println("      " + StringTools.rpad("FM" + (channel + 1), " ", 8)
				+ StringTools.lpad("" + (one.length >> 1), " ", 6) + " in the file, "
				+ StringTools.lpad("" + (two.length >> 1), " ", 6) + " in the song, "
				+ StringTools.lpad("" + apart, " ", 6) + " of " + weighed
				+ " frames apart, "
				+ (weighed < 1 ? 0 : Math.round(apart * 100.0 / weighed))
				+ " per cent, worst " + worst + first);
		}
	}

	static inline final SLACK = 220;

	static var first:String = "";

	static var weighed:Int = 0;

	static function tracked(one:Array<Int>, two:Array<Int>):Int {
		var missed = 0;
		var at = 0;

		first = "";
		weighed = 0;

		final began = two.length == 0 ? 0 : two[0];

		for (index in 0...(one.length >> 1)) {
			if (one[index * 2] < began) continue;

			weighed++;

			final tick = one[index * 2] + SLACK;
			final want = one[index * 2 + 1];

			while (at + 2 < two.length && two[at + 2] <= tick) at += 2;

			final held = two.length == 0 ? -1 : two[at + 1];
			if (held == want) continue;

			missed++;

			if (missed > 4) continue;

			first += "
           at " + round(one[index * 2] / Tempo.TICKS, 2)
				+ " s the file is " + spelt(want) + " and the song is " + spelt(held);
		}

		return missed;
	}

	static function spelt(value:Int):String {
		if (value < 0) return "nothing";
		if (value < 16384) return "" + value;

		var held = value;
		final out:Array<Int> = [];

		for (index in 0...4) {
			out.unshift(held % 128);
			held = Std.int(held / 128);
		}

		return out.join("/");
	}

	static function laned(song:mdd.song.Song, from:Int, to:Int, channel:Int):Void {
		Sys.println("");
		Sys.println("    the lanes on part " + channel + " between " + from + " s and "
			+ to + " s");

		for (pattern in song.patterns) {
			final lane = pattern.lane(channel);
			if (lane.notes.length == 0 && lane.automation.length == 0) continue;

			for (note in lane.notes) {
				final at = song.tempo.samplesAt(note.at) / Tempo.TICKS;
				if (at < from || at > to) continue;

				Sys.println("      note   " + round(at, 3) + " s   pitch " + note.pitch
					+ "   length " + note.length + "   instrument " + note.instrument
					+ (note.tied ? "   tied" : ""));
			}

			for (line in lane.automation) {
				var shown = 0;

				for (point in line.points) {
					final at = song.tempo.samplesAt(point.at) / Tempo.TICKS;
					if (at < from || at > to || shown > 16) continue;

					shown++;

					Sys.println("      line   " + round(at, 3) + " s   target "
						+ line.target + " slot " + line.slot + "   value " + point.value);
				}
			}
		}
	}

	static function stripped(from:Stream, dac:Bool):Stream {
		final out = new Stream(from.capacity);

		var half = 0;
		var address = -1;

		for (index in 0...from.count) {
			if (from.kindAt(index) != Stream.YM) {
				out.raw(from.tickAt(index), from.kindAt(index), from.portAt(index),
					from.valueAt(index));
				continue;
			}

			final port = from.portAt(index);
			final value = from.valueAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;

				if (!dac && half == 0 && (address == 0x2A || address == 0x2B)) continue;
			} else if (!dac && half == 0 && (address == 0x2A || address == 0x2B)) {
				continue;
			}

			out.raw(from.tickAt(index), Stream.YM, port, value);
		}

		return out;
	}

	static function loudness(stream:Stream, from:Int, to:Int):Float {
		final render = new Render(44100, Render.BLOCK);
		final frames = (to - from) * 44100;

		var done = 0;
		var total = 0.0;

		while (done < frames) {
			final at = from * Tempo.TICKS + Std.int(done * (Tempo.TICKS / 44100.0));
			final many = render.serve(stream, at, Render.BLOCK, 0);

			if (many <= 0) break;

			for (index in 0...many) {
				final value = render.block[index * 2];
				total += value * value;
			}

			done += many;
		}

		return done < 1 ? 0 : Math.sqrt(total / done);
	}

	static function hissed(source:Stream, made:Stream, from:Int, to:Int):Void {
		Sys.println("");
		Sys.println("    what each part of the mix holds, " + from + " s to " + to + " s");
		Sys.println("");

		final oneWhole = loudness(source, from, to);
		final twoWhole = loudness(made, from, to);

		final oneDry = loudness(stripped(source, false), from, to);
		final twoDry = loudness(stripped(made, false), from, to);

		Sys.println("      everything      file " + round(oneWhole, 4) + "   song "
			+ round(twoWhole, 4));
		Sys.println("      no converter    file " + round(oneDry, 4) + "   song "
			+ round(twoDry, 4));
	}

	static var worst:Int = 0;

	static function settled(one:Array<Int>, two:Array<Int>, from:Int, to:Int,
			kind:Int):Int {
		var oneAt = 0;
		var twoAt = 0;
		var apart = 0;

		weighed = 0;
		worst = 0;
		first = "";

		if (one.length == 0 || two.length == 0) return 0;

		var tick = from;

		while (tick < to) {
			while (oneAt + 2 < one.length && one[oneAt + 2] <= tick) oneAt += 2;
			while (twoAt + 2 < two.length && two[twoAt + 2] <= tick) twoAt += 2;

			tick += FRAME;

			if (one[oneAt] > tick || two[twoAt] > tick) continue;

			weighed++;

			final held = one[oneAt + 1];
			final made = two[twoAt + 1];

			if (held == made) continue;

			apart++;

			final much = kind == 0 ? widest(held, made) : 1;
			if (much > worst) worst = much;

			if (apart > 4) continue;

			first += "
           at " + round(tick / Tempo.TICKS, 2) + " s the file is "
				+ spelt(held) + " and the song is " + spelt(made);
		}

		return apart;
	}

	static function widest(one:Int, two:Int):Int {
		var most = 0;
		var left = one;
		var right = two;

		for (index in 0...4) {
			final away = (left % 128) - (right % 128);
			final much = away < 0 ? -away : away;

			if (much > most) most = much;

			left = Std.int(left / 128);
			right = Std.int(right / 128);
		}

		return most;
	}

	static function apart(channel:Int, one:Int, two:Int):String {
		if (channel == 3) return "noise mode";
		if (one < 1 || two < 1) return "one of them is silent";

		final cents = 1200 * Math.log(one / two) / Math.log(2);
		return round(cents, 1) + " cents";
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

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	static function said(at:Int):String {
		return "" + (Math.round(at * 1000.0 / Tempo.TICKS) / 1000.0) + " s";
	}
}
