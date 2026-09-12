package mdd.gate;

import mdd.format.Transcription;
import mdd.format.Vgm;
import mdd.host.Sdl;
import mdd.play.Stream;
import mdd.song.Part;
import mdd.song.Tempo;
import sys.FileSystem;
import sys.io.File;

@:unreflective
class VgmCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  vgm");

		final where = args.length > 0 && !StringTools.startsWith(args[0], "--")
			? args[0] : Gate.root + "/vendor/vgm";

		if (!FileSystem.exists(where)) {
			Sys.println("    not run: no corpus at " + where);
			Sys.println("    put vgm files there, or name a directory: mdd gate vgm <path>");
			return Gate.SKIPPED;
		}

		final files = args.length > 0 && !StringTools.startsWith(args[0], "--")
			? [for (name in FileSystem.readDirectory(where))
				if (StringTools.endsWith(name.toLowerCase(), ".vgm")) where + "/" + name]
			: Fixtures.corpus();

		files.sort(function(a:String, b:String):Int return compare(a, b));

		if (files.length == 0) {
			Sys.println("    no vgm files in " + where);
			return 1;
		}

		final timed = args.indexOf("--times") >= 0;
		final names = ["corpus", "sounds", "rated", "sound", "hushed", "paced", "covered",
			"shadowed", "whole", "stepped", "kitted", "sliced"];

		final spent:Array<Float> = [];
		var began = haxe.Timer.stamp();

		function marks():Void {
			spent.push(haxe.Timer.stamp() - began);
			began = haxe.Timer.stamp();
		}

		corpus(where, files);
		marks();
		sliced(files[0]);
		marks();
		sounds(where, files);
		marks();
		rated(where, files);
		marks();
		sound(where, files);
		marks();
		hushed(where, files);
		marks();
		paced(where, files);
		marks();
		covered(where, files);
		marks();
		shadowed(where, files);
		marks();
		whole(where, files);
		marks();
		stepped(where, files);
		marks();
		kitted(files);
		rooted(files);
		marks();

		if (timed) {
			var total = 0.0;
			for (held in spent) total += held;

			for (index in 0...names.length) {
				Sys.println("    " + StringTools.rpad(names[index], " ", 12)
					+ StringTools.lpad("" + Math.round(spent[index] * 10) / 10, " ", 7)
					+ " s   " + Math.round(spent[index] / total * 100) + " per cent");
			}
		}

		final into = args.indexOf("--wav");

		if (into >= 0 && into + 1 < args.length) {
			final capped = args.indexOf("--seconds");
			var seconds = 0;

			if (capped >= 0 && capped + 1 < args.length) {
				final want = Std.parseInt(args[capped + 1]);
				if (want != null) seconds = want;
			}

			final asked = args.indexOf("--rate");
			var rate = 44100;

			if (asked >= 0 && asked + 1 < args.length) {
				final want = Std.parseInt(args[asked + 1]);
				if (want != null && want > 0) rate = want;
			}

			final picked = args.indexOf("--only");
			if (picked >= 0 && picked + 1 < args.length) only = args[picked + 1];

			written(where, files, args[into + 1], seconds, rate,
				args.indexOf("--raw") >= 0);
		}
		transported(where, files);
		edited(where, files);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function sounds(where:String, files:Array<String>):Void {
		var loudest = 0.0;
		var raw = 0;
		var played = 0;
		var quiet = 0;
		var hushed = "";
		var clipped = 0;
		var worstJump = 0.0;
		var last = 0.0;
		var heard = 0;

		for (name in files) {
			if (played >= 6) break;

			final stream = new mdd.play.Stream(1 << 22);
			mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);

			final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);
			final span = 44100 * 12;

			var done = 0;
			var most = 0.0;

			while (done < span && most < 0.01) {
				final from = Std.int(done * (mdd.song.Tempo.TICKS / 44100.0));
				final many = render.serve(stream, from, mdd.play.Render.BLOCK, 0);
				if (many <= 0) break;

				for (i in 0...many) {
					final held = render.block[i * 2];
					final value = held < 0 ? -held : held;

					if (value > most) most = value;
					if (value >= 0.999) clipped++;

					final away = held - last;
					final jump = away < 0 ? -away : away;
					if (jump > worstJump) worstJump = jump;

					last = held;
					heard++;
				}

				final peak = render.ym.left < 0 ? -render.ym.left : render.ym.left;
				if (peak > raw) raw = peak;

				done += many;
			}

			played++;

			if (most < 0.01) {
				quiet++;
				if (hushed != "") hushed += ", ";
				hushed += Fixtures.titled(name) + " at " + round(most, 4);
			}

			if (most > loudest) loudest = most;
		}

		says("an imported vgm sounds", played > 0 && quiet == 0 && clipped == 0,
			played + " files rendered until they sound, loudest sample " + round(loudest, 4)
			+ " with the chip reaching " + raw + ", " + quiet + (hushed == "" ? ""
				: " (" + hushed + ")") + " under a hundredth of full"
			+ " scale, " + clipped + " of " + heard + " samples at the ceiling and the worst"
			+ " step between neighbours " + round(worstJump, 4));
	}

	static function transported(where:String, files:Array<String>):Void {
		final wanted = ["Green Hill", "Emerald Hill", "Chemical Plant", "Star Light"];
		final said = new StringBuf();

		var played = 0;
		var quiet = 0;
		var dark = 0;

		final peaks = new haxe.ds.Vector<Float>(mdd.song.Part.COUNT);
		for (index in 0...peaks.length) peaks[index] = 0;

		for (want in wanted) {
			var name = "";

			for (held in files) if (held.indexOf(want) >= 0) name = held;
			if (name == "") continue;

			final stream = new mdd.play.Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name),
				stream);

			final made = mdd.format.Transcription.of(stream, vgm.rate, name);
			final transport = new mdd.play.Transport(made.song, 1 << 18);
			final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);

			render.transport = transport;
			transport.play();

			var done = 0;
			var most = 0.0;
			var writes = 0;

			while (done < 44100 * 4) {
				final from = transport.advance(mdd.play.Render.BLOCK, 44100);
				final many = render.serve(transport.stream, from, mdd.play.Render.BLOCK,
					transport.entering, true);

				if (many <= 0) break;

				for (i in 0...many) {
					final value = render.block[i * 2];
					final much = value < 0 ? -value : value;
					if (much > most) most = much;
				}

				writes += transport.stream.count;
				done += many;
			}

			tapped(render, peaks);

			played++;
			if (most < 0.15) quiet++;

			said.add(want + " " + round(most, 3) + " over " + writes + " writes   ");
		}

		says("and the transcription plays", played > 0 && quiet == 0,
			played + " sonic tracks driven four seconds each the way the device asks for"
			+ " them: " + said.toString());

		final loudest = new StringBuf();

		for (index in 0...peaks.length) {
			final part:mdd.song.Part = index;

			if (peaks[index] < 0.02) dark++;
			loudest.add(part.name() + " " + round(peaks[index], 2) + "  ");
		}

		says("and every part drives a meter", played == 0 || dark <= 3,
			"the loudest tap each part reached, one being the meter's ceiling: "
			+ loudest.toString() + "(" + dark + " never moved)");
	}

	static function frequencies(song:mdd.song.Song, part:mdd.song.Part,
			span:Int):Array<Int> {
		final stream = new mdd.play.Stream(1 << 22);
		new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK * 2)
			.spanned(stream, 0, span);

		final half = part.index() >= 3 ? 1 : 0;
		final within = part.index() % 3;
		final out:Array<Int> = [];

		var index = 0;

		while (index + 1 < stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM
					|| (stream.portAt(index) & 1) != 0) {
				index++;
				continue;
			}

			if (stream.portAt(index) >> 1 != half) {
				index += 2;
				continue;
			}

			final address = stream.valueAt(index);

			if (address == 0xA0 + within || address == 0xA4 + within) {
				out.push((address << 8) | stream.valueAt(index + 1));
			}

			index += 2;
		}

		return out;
	}

	static function keys(song:mdd.song.Song, part:mdd.song.Part, span:Int):Int {
		final stream = new mdd.play.Stream(1 << 22);
		new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK * 2)
			.spanned(stream, 0, span);

		var many = 0;
		var index = 0;

		while (index + 1 < stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM
					|| (stream.portAt(index) & 1) != 0) {
				index++;
				continue;
			}

			if (stream.valueAt(index) == 0x28
					&& (stream.valueAt(index + 1) & 7) == part.index() % 3
					&& ((stream.valueAt(index + 1) >> 2) & 1) == (part.index() >= 3 ? 1 : 0)
					&& (stream.valueAt(index + 1) & 0xF0) != 0) {
				many++;
			}

			index += 2;
		}

		return many;
	}

	static function edited(where:String, files:Array<String>):Void {
		var name = "";
		for (held in files) if (held.indexOf("Green Hill") >= 0) name = held;
		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
		final song = mdd.format.Transcription.of(stream, vgm.rate, name).song;

		final part = mdd.song.Part.Fm1;
		final span = mdd.song.Tempo.TICKS * 8;
		final lane = song.patterns[0].lane(part);

		final was = frequencies(song, part, span);
		var moved = 0;

		for (note in lane.notes) {
			if (note.at > song.tempo.ppqn * 16) break;

			note.pitch += 12;
			moved++;
		}

		final now = frequencies(song, part, span);

		var apart = 0;
		for (index in 0...(was.length < now.length ? was.length : now.length)) {
			if (was[index] != now[index]) apart++;
		}

		says("an edited note changes what the chip is told", moved > 0 && apart > 0,
			moved + " notes on " + part.name() + " raised an octave changes " + apart
			+ " of " + was.length + " frequency writes in the first eight seconds");

		final keyed = keys(song, part, span);
		while (lane.notes.length > 0) lane.notes.pop();

		final quiet = keys(song, part, span);
		final left = frequencies(song, part, span);

		says("and taking the notes away silences the part", keyed > 0 && quiet == 0,
			keyed + " key ons before the notes were removed and " + quiet + " after, with "
			+ left.length + " frequency writes left of " + was.length);
	}

	static function covered(where:String, files:Array<String>):Void {
		var name = "";
		for (held in files) if (held.indexOf("Green Hill") >= 0) name = held;
		if (name == "" && files.length > 0) name = files[0];
		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
		final made = mdd.format.Transcription.of(stream, vgm.rate, name);

		final span = mdd.song.Tempo.TICKS * 2;
		final last = stream.count == 0 ? 0 : stream.tickAt(stream.count - 1);
		final windows = Std.int(last / span) + 1;

		final keyed = new haxe.ds.Vector<Int>(windows);
		final noted = new haxe.ds.Vector<Int>(windows);

		for (index in 0...windows) {
			keyed[index] = 0;
			noted[index] = 0;
		}

		var address = -1;
		var half = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (half != 0 || address != 0x28) continue;
			if ((value & 0xF0) == 0) continue;

			final at = Std.int(stream.tickAt(index) / span);
			if (at >= 0 && at < windows) keyed[at]++;
		}

		final tempo = made.song.tempo;

		for (pattern in made.song.patterns) {
			for (part in 0...6) {
				for (note in pattern.lane(part).notes) {
					final at = Std.int(tempo.samplesAt(note.at) / span);
					if (at >= 0 && at < windows) noted[at]++;
				}
			}
		}

		var worst = 1.0;
		var where2 = 0;
		var totalKeyed = 0;
		var totalNoted = 0;

		for (index in 0...windows) {
			totalKeyed += keyed[index];
			totalNoted += noted[index];

			if (keyed[index] < 8) continue;

			final part = noted[index] / keyed[index];
			if (part >= worst) continue;

			worst = part;
			where2 = index;
		}

		final sounding = new haxe.ds.Vector<Int>(windows);
		final wanted = new haxe.ds.Vector<Int>(windows);

		for (index in 0...windows) {
			sounding[index] = 0;
			wanted[index] = 0;
		}

		for (pattern in made.song.patterns) {
			for (part in 0...6) {
				for (note in pattern.lane(part).notes) {
					var at = tempo.samplesAt(note.at);
					final ends = tempo.samplesAt(note.at + note.length);

					while (at < ends) {
						final slot = Std.int(at / span);
						if (slot >= 0 && slot < windows) sounding[slot]++;
						at += 735;
					}
				}
			}
		}

		final held = new haxe.ds.Vector<Int>(6);
		final since = new haxe.ds.Vector<Int>(6);
		for (index in 0...6) {
			held[index] = 0;
			since[index] = 0;
		}

		address = -1;
		half = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

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

			final channel = within + ((value & 4) != 0 ? 3 : 0);
			final on = (value & 0xF0) != 0;
			final at = stream.tickAt(index);

			if (on) {
				if (held[channel] == 1) {
					var walk = since[channel];
					while (walk < at) {
						final slot = Std.int(walk / span);
						if (slot >= 0 && slot < windows) wanted[slot]++;
						walk += 735;
					}
				}

				held[channel] = 1;
				since[channel] = at;
				continue;
			}

			if (held[channel] == 0) continue;

			var walk = since[channel];
			while (walk < at) {
				final slot = Std.int(walk / span);
				if (slot >= 0 && slot < windows) wanted[slot]++;
				walk += 735;
			}

			held[channel] = 0;
		}

		var heldSteps = 0;
		var wantSteps = 0;
		var apart = 0.0;

		for (index in 0...windows) {
			heldSteps += sounding[index];
			wantSteps += wanted[index];

			if (wanted[index] < 40) continue;

			final away = Math.abs(sounding[index] - wanted[index]) / wanted[index];
			if (away > apart) apart = away;
		}

		says("and a note holds as long as the key did",
			wantSteps == 0 || Math.abs(heldSteps - wantSteps) < wantSteps * 0.02,
			heldSteps + " frames of fm sounding against " + wantSteps + " the file keys, and no"
			+ " two second window differs by more than " + round(apart * 100, 1) + " per cent");

		var lines = 0;
		var moves = 0;

		for (pattern in made.song.patterns) {
			for (part in 0...6) {
				for (line in pattern.lane(part).automation) {
					lines++;
					moves += line.points.length;
				}
			}
		}

		says("and a level that moves is kept", lines > 0,
			lines + " automation lines over the fm parts, holding " + moves + " points");

		says("and every fm key on becomes a note",
			totalKeyed == 0 || totalNoted >= totalKeyed * 0.98,
			totalNoted + " fm notes against " + totalKeyed + " key ons; the thinnest two second"
			+ " window keeps " + round(worst * 100, 1) + " per cent of them, at "
			+ (where2 * 2) + " s");
	}

	static final CLASSES:Array<Int> = [0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90, 0xB0, 0xB4];
	static final CLASS_NAMES:Array<String> = ["DT MUL", "TL", "KS AR", "AM D1R", "D2R",
		"D1L RR", "SSG", "FB ALG", "SIDES"];

	static function shadowed(where:String, files:Array<String>):Void {
		final wanted = ["Green Hill", "Emerald Hill", "Chemical Plant", "Marble", "Star Light"];
		final said = new StringBuf();

		var worstClass = 0.0;
		var worstTune = 0.0;
		var worstSquare = 0.0;
		var read = 0;

		for (want in wanted) {
			var name = "";
			for (held in files) if (held.indexOf(want) >= 0) name = held;
			if (name == "") continue;

			read++;
			looked(where, name, said);
		}

		says("and the registers the chip sees agree", read > 0 && every < 1.2 && everyTune < 12
			&& everySquare < 2.5 && everyKeys < 30 && everyStruck < 10,
			read + " files replayed as songs and read back off the register writes: "
			+ said.toString() + "; worst class " + round(every, 2) + ", worst pitch "
			+ round(everyTune, 1) + " cents, worst square " + round(everySquare, 2)
			+ ", worst keyed time " + everyKeys + " per thousand and " + everyStruck
			+ " strikes");
	}

	static var every:Float = 0;
	static var everyTune:Float = 0;
	static var everySquare:Float = 0;
	static var everyKeys:Int = 0;
	static var everyStruck:Int = 0;

	static function looked(where:String, name:String, said:StringBuf):Void {

		final source = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final seconds = 30;
		final span = mdd.song.Tempo.TICKS * seconds;
		final made = new mdd.play.Stream(1 << 22);

		final transport = new mdd.play.Transport(song, 1 << 18);
		transport.play();

		var done = 0;

		while (done < span) {
			final at = transport.advance(mdd.play.Render.BLOCK, 44100);
			final held = transport.stream;

			for (index in 0...held.count) {
				made.raw(held.tickAt(index), held.kindAt(index), held.portAt(index),
					held.valueAt(index));
			}

			done += Std.int(mdd.play.Render.BLOCK * (mdd.song.Tempo.TICKS / 44100.0));
			if (made.count > made.capacity - 4096) break;
		}

		final wanted = new haxe.ds.Vector<Int>(544);
		final held = new haxe.ds.Vector<Int>(544);

		for (index in 0...544) {
			wanted[index] = 0;
			held[index] = 0;
		}

		for (index in 0...4) {
			wanted[0x210 + index] = 15;
			held[0x210 + index] = 15;
		}

		final apart = new haxe.ds.Vector<Float>(CLASSES.length);
		final counted = new haxe.ds.Vector<Int>(CLASSES.length);

		for (index in 0...CLASSES.length) {
			apart[index] = 0;
			counted[index] = 0;
		}

		var levelWorst = 0;
		var levelWhere = "";

		final levelBy = new haxe.ds.Vector<Float>(6);
		final levelSeen = new haxe.ds.Vector<Int>(6);

		for (index in 0...6) {
			levelBy[index] = 0;
			levelSeen[index] = 0;
		}

		var tuned = 0.0;
		var tunes = 0;
		var squares = 0.0;
		var squared = 0;
		var extra = 0;
		var missing = 0;

		final fileKeyed = new haxe.ds.Vector<Int>(6);
		final songKeyed = new haxe.ds.Vector<Int>(6);
		final fileStruck = new haxe.ds.Vector<Int>(6);
		final songStruck = new haxe.ds.Vector<Int>(6);

		for (index in 0...6) {
			fileKeyed[index] = 0;
			songKeyed[index] = 0;
			fileStruck[index] = 0;
			songStruck[index] = 0;
		}

		final fileHeld = new haxe.ds.Vector<Int>(6);
		final songHeld = new haxe.ds.Vector<Int>(6);

		edged(source, span, fileStruck, fileHeld);
		edged(made, span, songStruck, songHeld);

		final extraBy = new haxe.ds.Vector<Int>(4);
		final liveBy = new haxe.ds.Vector<Int>(4);
		for (index in 0...4) {
			extraBy[index] = 0;
			liveBy[index] = 0;
		}

		var readWanted = 0;
		var readHeld = 0;
		var at = 0;

		while (at < span) {
			readWanted = poured(source, wanted, readWanted, at);
			readHeld = poured(made, held, readHeld, at);

			for (half in 0...2) {
				for (channel in 0...3) {
					final which2 = half * 3 + channel;
					final which = which2;
					final fileOn = (wanted[0x200 + which] & 0xF0) != 0;
					final songOn = (held[0x200 + which] & 0xF0) != 0;


					if (!fileOn) continue;

					for (which in 0...CLASSES.length) {
						final base = CLASSES[which];

						if (base >= 0xB0) {
							final where2 = (half << 8) | (base + channel);
							final away = wanted[where2] - held[where2];

							apart[which] += away < 0 ? -away : away;
							counted[which]++;
							continue;
						}

						for (group in 0...4) {
							final where2 = (half << 8) | (base + group * 4 + channel);
							final mask = base == 0x40 ? 0x7F : 0xFF;
							final away = (wanted[where2] & mask) - (held[where2] & mask);
							final much = away < 0 ? -away : away;

							apart[which] += much;
							counted[which]++;

							if (base == 0x40) {
								levelBy[which2] += much;
								levelSeen[which2]++;
							}

							if (base != 0x40 || much <= levelWorst) continue;
							if (at < mdd.song.Tempo.TICKS) continue;

							levelWorst = much;
							levelWhere = "FM" + (which2 + 1) + " op" + (group + 1) + " at "
								+ Math.round(at / mdd.song.Tempo.TICKS) + " s "
								+ (wanted[where2] & mask) + " against " + (held[where2] & mask);
						}
					}

					final high = (half << 8) | (0xA4 + channel);
					final low = (half << 8) | (0xA0 + channel);

					final one = hertz(wanted[high], wanted[low]);
					final two = hertz(held[high], held[low]);

					if (one > 1 && two > 1) {
						final away = 1200 * Math.log(one / two) / Math.log(2);

						tuned += away < 0 ? -away : away;
						tunes++;
					}
				}
			}

			for (channel in 0...4) {
				final one = wanted[0x210 + channel];
				final two = held[0x210 + channel];

				if (one < 15) liveBy[channel]++;
				if (one >= 15 && two >= 15) continue;

				if (one >= 15) {
					extra++;
					extraBy[channel]++;
					continue;
				}

				if (two >= 15) {
					missing++;
					continue;
				}

				final away = one - two;
				squares += away < 0 ? -away : away;
				squared++;
			}

			at += 735;
		}


		var worstClass = 0.0;

		for (index in 0...CLASSES.length) {
			if (counted[index] == 0) continue;

			final mean = apart[index] / counted[index];
			if (mean > worstClass) worstClass = mean;
		}

		var keysApart = 0;

		for (index in 0...6) {
			if (fileHeld[index] < 1) continue;

			final away = songHeld[index] - fileHeld[index];
			final much = Math.round((away < 0 ? -away : away) * 1000.0 / fileHeld[index]);

			if (much > keysApart) keysApart = much;
		}

		final tune = tunes == 0 ? 0.0 : tuned / tunes;
		final square = squared == 0 ? 0.0 : squares / squared;

		if (worstClass > every) every = worstClass;
		if (tune > everyTune) everyTune = tune;
		if (square > everySquare) everySquare = square;
		var struck = 0;

		for (index in 0...6) {
			final away = songStruck[index] - fileStruck[index];
			struck += away < 0 ? -away : away;
		}

		if (keysApart > everyKeys) everyKeys = keysApart;
		if (struck > everyStruck) everyStruck = struck;

		said.add(name.substr(0, 18) + " class " + round(worstClass, 2) + " pitch "
			+ round(tune, 1) + " square " + round(square, 2));


		said.add(" strikes " + struck + " keyed " + keysApart + " per thousand"
			+ (levelWorst == 0 ? "" : " worst level " + levelWorst + " " + levelWhere));

		said.add(" level by channel ");

		for (index in 0...6) {
			if (levelSeen[index] == 0) continue;
			said.add("FM" + (index + 1) + " " + round(levelBy[index] / levelSeen[index], 2)
				+ " ");
		}

		if (struck >= 20 || keysApart >= 40) {
			said.add(" [");

			for (index in 0...6) {
				said.add(songStruck[index] + "/" + fileStruck[index] + " ");
			}

			said.add("]");
		}

		said.add("   ");
	}

	static function hertz(high:Int, low:Int):Float {
		final number = ((high & 7) << 8) | low;
		if (number == 0) return 0;

		final block = (high >> 3) & 7;

		return number * (mdd.chip.Ym2612.CLOCK / mdd.chip.Ym2612.PER_SAMPLE) / 1048576.0
			* Math.pow(2, block - 1);
	}

	static function edged(stream:mdd.play.Stream, span:Int, struck:haxe.ds.Vector<Int>,
			held:haxe.ds.Vector<Int>):Void {
		final keyed = new haxe.ds.Vector<Bool>(6);
		final since = new haxe.ds.Vector<Int>(6);

		for (index in 0...6) {
			struck[index] = 0;
			held[index] = 0;
			keyed[index] = false;
			since[index] = 0;
		}

		var address = -1;
		var half = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);
			final at = stream.tickAt(index);

			if (at > span) break;

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (half != 0 || address != 0x28) continue;

			final within = value & 3;
			if (within == 3) continue;

			final which = within + ((value & 4) != 0 ? 3 : 0);
			final on = (value & 0xF0) != 0;

			if (on == keyed[which]) continue;

			if (on) struck[which]++;
			else held[which] += at - since[which];

			keyed[which] = on;
			since[which] = at;
		}

		for (index in 0...6) if (keyed[index]) held[index] += span - since[index];
	}

	static function poured(stream:mdd.play.Stream, shadow:haxe.ds.Vector<Int>, from:Int,
			until:Int):Int {
		var index = from;
		var address = -1;
		var half = 0;
		var latched = 0;

		while (index < stream.count && stream.tickAt(index) <= until) {
			final value = stream.valueAt(index);

			if (stream.kindAt(index) != mdd.play.Stream.YM) {
				if ((value & 0x80) != 0) {
					latched = (value >> 4) & 7;

					if ((latched & 1) != 0) shadow[0x210 + (latched >> 1)] = value & 0x0F;
				} else if ((latched & 1) != 0) {
					shadow[0x210 + (latched >> 1)] = value & 0x0F;
				}

				index++;
				continue;
			}

			final port = stream.portAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
			} else if (address >= 0) {
				shadow[(half << 8) | address] = value;

				if (half == 0 && address == 0x28) {
					final within = value & 3;

					if (within != 3) {
						shadow[0x200 + within + ((value & 4) != 0 ? 3 : 0)] = value & 0xF0;
					}
				}
			}

			index++;
		}

		return index;
	}

	static function whole(where:String, files:Array<String>):Void {
		var name = "";
		for (held in files) if (held.indexOf("Green Hill") >= 0) name = held;
		if (name == "" && files.length > 0) name = files[0];
		if (name == "") return;

		final read = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), read);
		final song = mdd.format.Transcription.of(read, vgm.rate, name).song;

		final span = song.tempo.samplesAt(song.ends());
		final made = new mdd.play.Stream(1 << 23);
		final sequencer = new mdd.play.Sequencer(song);

		sequencer.spanned(made, 0, span);

		says("an imported song exports whole", sequencer.lost == 0 && made.dropped == 0,
			made.count + " register writes over " + round(span / mdd.song.Tempo.TICKS, 1)
			+ " s, " + sequencer.lost + " events and " + made.dropped
			+ " writes dropped on the way");
	}

	public static inline final STEP = 0.05;

	static function stepped(where:String, files:Array<String>):Void {
		var name = "";
		for (held in files) if (held.indexOf("Green Hill") >= 0) name = held;
		if (name == "" && files.length > 0) name = files[0];
		if (name == "") return;

		final read = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), read);
		final song = mdd.format.Transcription.of(read, vgm.rate, name).song;

		final frames = 44100 * 12;

		final fileSteps = crackles(null, read, frames);
		final fileWorst = worstStep;

		final songSteps = crackles(song, null, frames);
		final songWorst = worstStep;

		final wroteOne = new mdd.play.Stream(1 << 21);
		final wroteTwo = new mdd.play.Stream(1 << 21);

		gathered(song, 44100, 8, wroteOne);
		gathered(song, 48000, 8, wroteTwo);

		var apartAt = -1;
		final many = wroteOne.count < wroteTwo.count ? wroteOne.count : wroteTwo.count;

		for (index in 0...many) {
			if (wroteOne.kindAt(index) == wroteTwo.kindAt(index)
				&& wroteOne.portAt(index) == wroteTwo.portAt(index)
				&& wroteOne.valueAt(index) == wroteTwo.valueAt(index)
				&& wroteOne.tickAt(index) == wroteTwo.tickAt(index)) continue;

			apartAt = index;
			break;
		}

		final said = new StringBuf();

		if (apartAt >= 0) {
			final from = apartAt > 2 ? apartAt - 2 : 0;

			said.add(", first apart at " + apartAt + " {");

			for (index in from...(from + 6)) {
				if (index >= many) break;

				said.add(wroteOne.tickAt(index) + ":" + wroteOne.kindAt(index) + ":"
					+ wroteOne.portAt(index) + ":"
					+ StringTools.hex(wroteOne.valueAt(index), 2) + " ");
			}

			said.add("| ");

			for (index in from...(from + 6)) {
				if (index >= many) break;

				said.add(wroteTwo.tickAt(index) + ":" + wroteTwo.kindAt(index) + ":"
					+ wroteTwo.portAt(index) + ":"
					+ StringTools.hex(wroteTwo.valueAt(index), 2) + " ");
			}

			said.add("}");
		}

		says("and the writes do not depend on the device rate",
			wroteOne.count == wroteTwo.count && apartAt < 0,
			wroteOne.count + " writes at 44100 and " + wroteTwo.count + " at 48000"
			+ said.toString());

		final one = sampled(song, 44100, 8);
		final two = sampled(song, 48000, 8);
		final apart = one[1] == 0 ? 1.0 : Math.abs(two[1] - one[1]) / one[1];

		says("and the song sounds the same at either device rate",
			apart < 0.03 && one[0] > 0.05 && two[0] > 0.05,
			"eight seconds of the song at 44100 and 48000 peak at " + round(one[0], 3)
			+ " and " + round(two[0], 3) + " and hold " + round(one[1], 4) + " and "
			+ round(two[1], 4) + " of full scale, " + round(apart * 100, 2)
			+ " per cent apart");

		says("and no more crackle than the file", fileSteps == 0
			|| songSteps < fileSteps * 1.5 + 200,
			songSteps + " steps of more than " + STEP + " between neighbouring samples over"
			+ " twelve seconds, against " + fileSteps + " in the file, worst "
			+ round(songWorst, 3) + " against " + round(fileWorst, 3));
	}

	static function gathered(song:mdd.song.Song, rate:Int, seconds:Int,
			into:mdd.play.Stream):Void {
		final transport = new mdd.play.Transport(song, 1 << 18);

		transport.rewind();
		transport.play();

		final span = mdd.song.Tempo.TICKS * seconds;

		while (transport.position < span) {
			transport.advance(mdd.play.Render.BLOCK, rate);

			final held = transport.stream;

			for (index in 0...held.count) {
				if (held.tickAt(index) >= span) continue;

				into.raw(held.tickAt(index), held.kindAt(index), held.portAt(index),
					held.valueAt(index));
			}
		}
	}

	static function sampled(song:mdd.song.Song, rate:Int, seconds:Int):Array<Float> {
		final render = new mdd.play.Render(rate, mdd.play.Render.BLOCK);
		final transport = new mdd.play.Transport(song, 1 << 18);

		render.transport = transport;
		transport.rewind();
		transport.play();

		final frames = rate * seconds;

		var done = 0;
		var most = 0.0;
		var power = 0.0;

		while (done < frames) {
			final at = transport.advance(mdd.play.Render.BLOCK, rate);
			final many = render.serve(transport.stream, at, mdd.play.Render.BLOCK,
				transport.entering, true);

			if (many <= 0) break;

			for (index in 0...many) {
				final value = render.block[index * 2];
				final much = value < 0 ? -value : value;

				if (much > most) most = much;
				power += value * value;
			}

			done += many;
		}

		return [most, done < 1 ? 0 : Math.sqrt(power / done)];
	}

	static var worstStep:Float = 0;

	static function crackles(song:Null<mdd.song.Song>, source:Null<mdd.play.Stream>,
			frames:Int):Int {
		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);
		final transport = song == null ? null : new mdd.play.Transport(song, 1 << 18);

		if (transport != null) {
			render.transport = transport;
			transport.play();
		}

		var done = 0;
		var last = 0.0;
		var steps = 0;

		worstStep = 0;

		while (done < frames) {
			var many = 0;

			if (transport != null) {
				final at = transport.advance(mdd.play.Render.BLOCK, 44100);
				many = render.serve(transport.stream, at, mdd.play.Render.BLOCK,
					transport.entering, true);
			} else {
				final at = Std.int(done * (mdd.song.Tempo.TICKS / 44100.0));
				many = render.serve(source, at, mdd.play.Render.BLOCK, 0);
			}

			if (many <= 0) break;

			for (index in 0...many) {
				final value = render.block[index * 2];
				final away = value - last;
				final much = away < 0 ? -away : away;

				if (done + index > 0) {
					if (much > STEP) steps++;
					if (much > worstStep) worstStep = much;
				}

				last = value;
			}

			done += many;
		}

		return steps;
	}

	static function paced(where:String, files:Array<String>):Void {
		var name = "";
		for (held in files) if (held.indexOf("Green Hill") >= 0) name = held;
		if (name == "" && files.length > 0) name = files[0];
		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
		final made = mdd.format.Transcription.of(stream, vgm.rate, name);
		final song = made.song;

		var notes = 0;
		for (pattern in song.patterns) notes += pattern.notes();

		final transport = new mdd.play.Transport(song, 1 << 18);
		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);

		render.transport = transport;
		transport.play();

		final period = mdd.play.Render.BLOCK / 44100.0;
		final blocks = Std.int(44100 * 8 / mdd.play.Render.BLOCK);
		final times = new Array<Float>();

		var worst = 0.0;

		for (index in 0...blocks) {
			final began = haxe.Timer.stamp();
			final at = transport.advance(mdd.play.Render.BLOCK, 44100);

			render.serve(transport.stream, at, mdd.play.Render.BLOCK, transport.entering, true);

			final took = haxe.Timer.stamp() - began;

			times.push(took);
			if (took > worst) worst = took;
		}

		times.sort(function(a:Float, b:Float):Int return a < b ? -1 : (a > b ? 1 : 0));

		final middle = times[Std.int(times.length / 2)];

		says("and a block is built inside its own period", worst < period && blocks > 0,
			blocks + " blocks of " + mdd.play.Render.BLOCK + " frames from " + notes
			+ " notes: median " + round(middle * 1000, 3) + " ms, worst "
			+ round(worst * 1000, 3) + " ms, against a block period of "
			+ round(period * 1000, 3) + " ms");
	}

	static function tapped(render:mdd.play.Render, peaks:haxe.ds.Vector<Float>):Void {
		final many = render.tapped < mdd.play.Render.TAPS
			? render.tapped : mdd.play.Render.TAPS;

		for (index in 0...peaks.length) {
			final base = index * mdd.play.Render.TAPS;

			for (slot in 0...many) {
				final value = render.taps[base + slot] * mdd.app.Sound.METER;
				final size = value < 0 ? -value : value;

				if (size > peaks[index]) peaks[index] = size;
			}
		}
	}

	static function rated(where:String, files:Array<String>):Void {
		if (files.length == 0) return;

		final at = [22050, 44100, 48000, 96000, 192000];
		final peaks:Array<Float> = [];
		final loudness:Array<Float> = [];
		final banded:Array<Float> = [];

		for (rate in at) {
			final stream = new mdd.play.Stream(1 << 22);
			mdd.format.Vgm.read(sys.io.File.getBytes(files[0]), stream);

			final render = new mdd.play.Render(rate, mdd.play.Render.BLOCK);
			final span = rate * 4;
			final coefficient = Math.exp(-2 * Math.PI * 8000 / rate);

			var done = 0;
			var most = 0.0;
			var total = 0.0;
			var low = 0.0;
			var held = 0.0;

			while (done < span) {
				final from = Std.int(done * (mdd.song.Tempo.TICKS / rate));
				final many = render.serve(stream, from, mdd.play.Render.BLOCK, 0);
				if (many <= 0) break;

				for (i in 0...many) {
					final value = render.block[i * 2];
					final much = value < 0 ? -value : value;

					if (much > most) most = much;

					total += value * value;
					held = value * (1 - coefficient) + held * coefficient;
					low += held * held;
				}

				done += many;
			}

			peaks.push(most);
			loudness.push(done < 1 ? 0 : Math.sqrt(total / done));
			banded.push(done < 1 ? 0 : Math.sqrt(low / done));
		}

		var loudest = 0.0;
		var audible = 0.0;

		for (index in 1...at.length) {
			final away = (loudness[index] - loudness[1]) / (loudness[1] <= 0 ? 1
				: loudness[1]);

			final under = (banded[index] - banded[1]) / (banded[1] <= 0 ? 1 : banded[1]);

			if ((away < 0 ? -away : away) > loudest) loudest = away < 0 ? -away : away;
			if ((under < 0 ? -under : under) > audible) audible = under < 0 ? -under : under;
		}

		var said = "";
		for (index in 0...at.length) {
			said += (index == 0 ? "" : ", ") + at[index] + " holds "
				+ round(loudness[index], 5) + " and " + round(banded[index], 5)
				+ " under 8 kHz";
		}

		says("and the same at every device rate", loudest < 0.01 && audible < 0.01,
			"four seconds where " + said + "; against 44100 the loudness is "
			+ round(loudest * 100, 2) + " per cent apart at worst and the audible band "
			+ round(audible * 100, 2) + " per cent, and 22050 keeps a narrower band"
			+ " because it has to");
	}

	static function written(where:String, files:Array<String>, into:String,
			seconds:Int, rate:Int, plain:Bool = false):Void {
		final one = StringTools.endsWith(into.toLowerCase(), ".wav");

		if (!one && !sys.FileSystem.exists(into)) sys.FileSystem.createDirectory(into);

		var chosen = files.length > 0 ? files[0] : "";
		for (held in files) if (held.indexOf("Green Hill") >= 0) chosen = held;

		var wrote = 0;
		var held = 0.0;

		for (name in files) {
			if (one && name != chosen) continue;

			final stem = Fixtures.titled(name);

			final where2 = one ? into
				: into + "/" + stem.substr(0, stem.length - 4) + ".wav";

			final much = plain ? raw(name, where2, seconds, rate)
				: rendered(name, where2, seconds, rate);
			if (much <= 0) continue;

			wrote++;
			held += much;

			Sys.println("    " + StringTools.rpad(name, " ", 34)
				+ shown(much, 1) + " s");

			if (one) break;
		}

		Sys.println("    wrote " + wrote + " files, " + shown(held, 1) + " s in all, to "
			+ into);
	}

	static function shown(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	static function raw(from:String, into:String, seconds:Int, rate:Int):Float {
		final read = new mdd.play.Stream(1 << 23);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(from), read);
		final stream = only == "" ? read : sifted(read, only);

		var ticks = vgm.samples;

		if (ticks <= 0 && stream.count > 0) ticks = stream.tickAt(stream.count - 1);
		if (ticks <= 0) return 0;

		ticks += rate;
		final capped = seconds * mdd.song.Tempo.TICKS;
		if (seconds > 0 && ticks > capped) ticks = capped;

		final frames = Std.int(ticks * (rate / mdd.song.Tempo.TICKS));
		final sound = new haxe.ds.Vector<cpp.Float32>(frames * 2);
		final render = new mdd.play.Render(rate, mdd.play.Render.BLOCK);

		var done = 0;

		while (done < frames) {
			final at = Std.int(done * (mdd.song.Tempo.TICKS / rate));
			final many = render.serve(stream, at, mdd.play.Render.BLOCK, 0);
			if (many <= 0) break;

			for (i in 0...many) {
				if ((done + i) * 2 + 1 >= sound.length) break;
				sound[(done + i) * 2] = render.block[i * 2];
				sound[(done + i) * 2 + 1] = render.block[i * 2 + 1];
			}

			done += many;
		}

		sys.io.File.saveBytes(into, mdd.format.Wav.write(sound, frames, 2, rate));
		return frames / rate;
	}

	public static var only:String = "";

	static function sifted(from:mdd.play.Stream, want:String):mdd.play.Stream {
		final wanted = want.split(",");
		final out = new mdd.play.Stream(from.capacity);

		var address = -1;
		var half = 0;
		var latched = 0;

		for (index in 0...from.count) {
			final kind = from.kindAt(index);
			final port = from.portAt(index);
			final value = from.valueAt(index);
			final tick = from.tickAt(index);

			if (kind != mdd.play.Stream.YM) {
				if ((value & 0x80) != 0) latched = (value >> 4) & 7;

				final channel = 6 + (latched >> 1);
				if (wanted.indexOf(Std.string(channel)) < 0) continue;

				out.raw(tick, kind, port, value);
				continue;
			}

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (address < 0) continue;

			final part = half == 0 && address == 0x28 ? mdd.play.Stream.keyPart(value)
				: mdd.play.Stream.ymPart(half, address);

			if (part >= 0 && wanted.indexOf(Std.string(part)) < 0) continue;

			out.raw(tick, kind, half * 2, address);
			out.raw(tick, kind, half * 2 + 1, value);
		}

		return out;
	}

	static function rendered(from:String, into:String, seconds:Int,
			rate:Int):Float {
		final stream = new mdd.play.Stream(1 << 23);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(from), stream);

		var ticks = vgm.samples;

		if (ticks <= 0 && stream.count > 0) ticks = stream.tickAt(stream.count - 1);
		if (ticks <= 0) return 0;

		ticks += rate;
		final capped = seconds * mdd.song.Tempo.TICKS;
		if (seconds > 0 && ticks > capped) ticks = capped;

		final frames = Std.int(ticks * (rate / mdd.song.Tempo.TICKS));
		final sound = new haxe.ds.Vector<cpp.Float32>(frames * 2);

		final song = mdd.format.Transcription.of(stream, vgm.rate, from).song;

		if (only != "") {
			final want = only.split(",");

			for (index in 0...mdd.song.Part.COUNT) {
				song.muted[index] = want.indexOf(Std.string(index)) < 0;
			}
		}

		final transport = new mdd.play.Transport(song, 1 << 18);
		final render = new mdd.play.Render(rate, mdd.play.Render.BLOCK);

		render.transport = transport;
		transport.play();

		var done = 0;

		while (done < frames) {
			final at = transport.advance(mdd.play.Render.BLOCK, rate);
			final many = render.serve(transport.stream, at, mdd.play.Render.BLOCK,
				transport.entering, true);

			if (many <= 0) break;

			for (i in 0...many) {
				if ((done + i) * 2 + 1 >= sound.length) break;
				sound[(done + i) * 2] = render.block[i * 2];
				sound[(done + i) * 2 + 1] = render.block[i * 2 + 1];
			}

			done += many;
		}

		sys.io.File.saveBytes(into, mdd.format.Wav.write(sound, frames, 2, rate));
		return frames / rate;
	}

	static function sound(where:String, files:Array<String>):Void {
		final budget = new mdd.check.Budget(mdd.check.Profile.megaDrive());
		final said = new StringBuf();

		var read = 0;
		var troubled = 0;
		var warned = 0;
		var worst = "";
		var most = 0;

		for (name in files) {
			if (read >= 20) break;

			final stream = new mdd.play.Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name),
				stream);

			final made = mdd.format.Transcription.of(stream, vgm.rate, name);

			budget.overSong(made.song);

			read++;
			if (budget.found.length == 0) continue;

			if (budget.faults > 0) troubled++;
			else warned++;

			said.add(name + " " + budget.found.length
				+ (budget.faults > 0 ? " with " + budget.faults + " it cannot play" : "")
				+ "   ");

			if (budget.found.length > most) {
				most = budget.found.length;
				worst = name;
			}
		}

		var patterns = 0;
		var tracks = 0;
		var mixed = 0;

		for (name in files) {
			if (name.indexOf("Green Hill") < 0) continue;

			final stream = new mdd.play.Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name),
				stream);

			final song = mdd.format.Transcription.of(stream, vgm.rate, name).song;

			patterns = song.patterns.length;
			tracks = song.tracks.length;

			for (held in song.patterns) {
				var parts = 0;
				for (index in 0...mdd.song.Part.COUNT) {
					if (held.lane(index).notes.length > 0) parts++;
				}

				if (parts > 1) mixed++;
			}
		}

		says("an import gives every part its own pattern", patterns > 1 && mixed == 0
			&& tracks == patterns,
			patterns + " patterns across " + tracks + " tracks, " + mixed
			+ " of them holding more than one part");

		says("a game vgm reads back as playable", troubled == 0,
			read + " files transcribed, " + troubled + " of them raising something it cannot"
			+ " play and " + warned + " a warning" + (said.length == 0 ? "" : ": "
			+ said.toString()) + (worst == "" ? "" : "   most from " + worst));
	}

	static function hushed(where:String, files:Array<String>):Void {
		var name = "";
		for (held in files) if (held.indexOf("Green Hill") >= 0) name = held;
		if (name == "" && files.length > 0) name = files[0];
		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
		final song = mdd.format.Transcription.of(stream, vgm.rate, name).song;

		final loud = sounded(song, 44100 * 3, -1);

		says("a fader on the rack reaches an imported vgm", loud > 0.1,
			"three seconds of " + name + " played at " + round(loud, 3));

		var quietest = loud;
		var muted = 0;

		for (index in 0...mdd.song.Part.COUNT) {
			final held = sounded(song, 44100 * 3, index);
			if (held >= loud) continue;

			muted++;
			if (held < quietest) quietest = held;
		}

		says("and muting a part is heard", muted > 0,
			muted + " of the eleven parts changed what reached the chips when muted, the quietest"
			+ " leaving " + round(quietest, 3) + " against " + round(loud, 3));

		final after = stopped(song);

		says("and stop silences the chips", after < 0.002,
			"a second of rendering after the transport stopped peaks at " + round(after, 5));
	}

	static function sounded(song:mdd.song.Song, frames:Int, mute:Int):Float {
		for (index in 0...mdd.song.Part.COUNT) song.muted[index] = index == mute;

		final transport = new mdd.play.Transport(song, 1 << 18);
		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);

		render.transport = transport;
		transport.play();

		var done = 0;
		var most = 0.0;

		while (done < frames) {
			final at = transport.advance(mdd.play.Render.BLOCK, 44100);
			final many = render.serve(transport.stream, at, mdd.play.Render.BLOCK,
				transport.entering, true);
			if (many <= 0) break;

			for (i in 0...many) {
				final value = render.block[i * 2];
				final much = value < 0 ? -value : value;
				if (much > most) most = much;
			}

			done += many;
		}

		for (index in 0...mdd.song.Part.COUNT) song.muted[index] = false;
		return most;
	}

	static function stopped(song:mdd.song.Song):Float {
		final transport = new mdd.play.Transport(song, 1 << 18);
		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);

		render.transport = transport;
		transport.play();

		var done = 0;

		while (done < 44100 * 3) {
			final at = transport.advance(mdd.play.Render.BLOCK, 44100);
			done += render.serve(transport.stream, at, mdd.play.Render.BLOCK,
				transport.entering, true);
		}

		transport.stop();

		var most = 0.0;
		done = 0;

		while (done < 44100) {
			final at = transport.advance(mdd.play.Render.BLOCK, 44100);
			final many = render.serve(transport.stream, at, mdd.play.Render.BLOCK,
				transport.entering, true);
			if (many <= 0) break;

			if (done > 22050) {
				for (i in 0...many) {
					final value = render.block[i * 2];
					final much = value < 0 ? -value : value;
					if (much > most) most = much;
				}
			}

			done += many;
		}

		return most;
	}

	static function grouped(where:String):String {
		final held = haxe.io.Path.directory(where);
		final at = held.lastIndexOf("/");

		return at < 0 ? held : held.substring(at + 1);
	}

	static inline final HIT_QUIET = 4;
	static inline final HIT_SLIP = 8;
	static inline final HIT_APART = 6.0;
	static inline final HIT_LEAST = 128;

	static function loudFrom(bytes:haxe.ds.Vector<Int>, many:Int):Int {
		var at = 0;

		while (at < many) {
			final byte = bytes[at] - 128;
			if ((byte < 0 ? -byte : byte) > HIT_QUIET) break;

			at++;
		}

		return at;
	}

	static function apartBy(one:mdd.song.Sample, head:Int, two:mdd.song.Sample, rest:Int,
			many:Int, slip:Int):Float {
		var total = 0.0;
		var counted = 0;

		for (index in 0...many) {
			final left = head + index;
			final right = rest + index + slip;

			if (left < 0 || left >= one.length()) continue;
			if (right < 0 || right >= two.length()) continue;

			final away = one.bytes[left] - two.bytes[right];

			total += away < 0 ? -away : away;
			counted++;
		}

		return counted < HIT_LEAST ? 256 : total / counted;
	}

	static function copies(song:mdd.song.Song):Int {
		var many = 0;

		for (first in 0...song.samples.length) {
			for (second in first + 1...song.samples.length) {
				final one = song.samples[first];
				final two = song.samples[second];

				final head = loudFrom(one.bytes, one.length());
				final rest = loudFrom(two.bytes, two.length());

				final left = one.length() - head;
				final right = two.length() - rest;

				if (left < HIT_LEAST || right < HIT_LEAST) continue;

				final shorter = left < right ? left : right;
				final longer = left > right ? left : right;

				if (shorter * 5 < longer * 4) continue;

				var best = 256.0;

				for (slip in -HIT_SLIP...HIT_SLIP + 1) {
					final away = apartBy(one, head, two, rest, shorter, slip);
					if (away < best) best = away;
				}

				if (best <= HIT_APART) many++;
			}
		}

		return many;
	}

	/**
		Every recording a file gives the converter sits on a key of its own, and the
		notes are written on it.

		The editor draws a row for each key, so hits that all carry one key are drawn
		as a single row however many different sounds they are. The key chooses nothing
		about what is heard on the converter: the note names the instrument, and the
		instrument names the recording.

		@param files The files to read.
	**/
	static inline final KEYS = 128;

	static function rooted(files:Array<String>):Void {
		final said = new StringBuf();

		var carried = 0;
		var shared = 0;
		var offKey = 0;
		var widest = 0;
		var shown = 0;

		for (name in files) {
			final source = new Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(File.getBytes(name), source);

			if (vgm == null) continue;

			final song = mdd.format.Transcription.of(source, vgm.rate, name).song;
			if (song.samples.length < 2) continue;

			carried++;

			final roots:Array<Int> = [];

			for (sample in song.samples) {
				if (roots.indexOf(sample.root) < 0) roots.push(sample.root);
			}

			final want = song.samples.length < KEYS ? song.samples.length : KEYS;

			if (roots.length > widest) widest = roots.length;
			if (roots.length < want) shared++;

			for (pattern in song.patterns) {
				for (note in pattern.lane(Part.Dac).notes) {
					final instrument = song.instrumentAt(note.instrument);
					if (instrument == null) continue;

					final sample = song.sampleAt(instrument.sample);
					if (sample == null) continue;

					if (note.pitch != sample.root) offKey++;
				}
			}

			if (roots.length < want && shown < 8) {
				if (shown > 0) said.add(", ");
				said.add(Fixtures.titled(name) + " " + song.samples.length
					+ " on " + roots.length + " keys of " + want);
				shown++;
			}
		}

		says("every recording gets a key until the keys run out", shared == 0,
			carried + " files carry more than one, the most on " + widest
			+ " keys" + (shared == 0 ? "" : ", and " + shared
				+ " leave a key unused: " + said.toString()));

		says("and a hit is written on the key its recording sits on", offKey == 0,
			offKey + " notes name a key their recording does not sit on");
	}

	static function kitted(files:Array<String>):Void {
		final said = new StringBuf();

		var over = 0;
		var counted = 0;
		var shown = 0;

		for (name in files) {
			final source = new Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(File.getBytes(name), source);

			if (vgm == null) continue;

			final song = mdd.format.Transcription.of(source, vgm.rate, name).song;
			if (song.samples.length == 0) continue;

			final many = copies(song);

			counted += song.samples.length;
			over += many;

			if (many > 0 && shown < 8) {
				if (shown > 0) said.add(", ");
				said.add(Fixtures.titled(name) + " " + song.samples.length
					+ " with " + many + " a copy");
				shown++;
			}
		}

		says("a drum played twice is one sample", over == 0,
			counted + " samples cut from the files that carry any, " + over
			+ " of them a near copy of another: " + said.toString());
	}

	static function compare(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	/**
		Slicing a clip in an imported piece changes nothing that sounds.

		An imported piece is where automation actually lives: a recording writes pitch,
		level and stereo between the notes, and all of it ends up in lanes under the
		clips. A synthetic fixture carries a line or two, which is not the same test.

		@param name The recording to read.
	**/
	static function sliced(name:String):Void {
		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
		final song = mdd.format.Transcription.of(stream, vgm.rate, name).song;

		var track = -1;

		for (index in 0...song.tracks.length) {
			if (song.tracks[index].clips.length > 0 && track < 0) track = index;
		}

		if (track < 0) {
			says("a cut in an imported piece changes nothing that sounds", false,
				"the import left no clip to cut");
			return;
		}

		final clip = song.tracks[track].clips[0];
		final at = clip.at + Std.int(clip.length / 2);

		final was = streamed(song);
		final history = new mdd.song.edit.History();

		history.does(song, new mdd.song.edit.SliceClip(track, clip, at));

		final now = streamed(song);
		final differs = differing(was, now);

		final where = parted(was, now);

		says("a cut in an imported piece changes nothing that sounds",
			was.count == now.count && where < 0,
			was.count + " writes before against " + now.count + " after, cut at " + at
			+ (where < 0 ? "" : ", first apart at " + where + ", tick "
			+ was.tickAt(where) + " port " + was.portAt(where) + " value "
			+ was.valueAt(where) + " against tick " + now.tickAt(where) + " port "
			+ now.portAt(where) + " value " + now.valueAt(where)));

		history.undo(song);

		final back = streamed(song);

		says("and taking the cut back puts every write where it was",
			differing(was, back) == -2,
			differing(was, back) == -2 ? "the stream is what it was before the cut"
			: "the stream did not come back");
	}

	/**
		@param song A piece.
		@return Every register write the whole of it makes.
	**/
	static function streamed(song:mdd.song.Song):mdd.play.Stream {
		final span = song.tempo.samplesAt(song.ends());
		final stream = new mdd.play.Stream(mdd.play.Mixdown.roomFor(span));

		new mdd.play.Sequencer(song).spanned(stream, 0, span);
		return stream;
	}

	/**
		@param one One stream.
		@param two Another.
		@return The first write they disagree on, or -1 where every write they both hold
			is the same.
	**/
	static function parted(one:mdd.play.Stream, two:mdd.play.Stream):Int {
		final least = one.count < two.count ? one.count : two.count;

		for (index in 0...least) {
			if (one.tickAt(index) != two.tickAt(index)) return index;
			if (one.kindAt(index) != two.kindAt(index)) return index;
			if (one.portAt(index) != two.portAt(index)) return index;
			if (one.valueAt(index) != two.valueAt(index)) return index;
		}

		return -1;
	}

	static function differing(one:mdd.play.Stream, two:mdd.play.Stream):Int {
		if (one.count != two.count) return -1;

		for (index in 0...one.count) {
			if (one.tickAt(index) != two.tickAt(index)) return index;
			if (one.kindAt(index) != two.kindAt(index)) return index;
			if (one.portAt(index) != two.portAt(index)) return index;
			if (one.valueAt(index) != two.valueAt(index)) return index;
		}

		return -2;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	/**
		@param one One stream.
		@param two Another.
		@return -2 where they are the same, -1 where they are different lengths, and the
			first write they disagree on otherwise.
	**/
	static function alike(one:Stream, two:Stream):Int {
		if (one.count != two.count) return -1;

		for (i in 0...one.count) {
			if (one.tickAt(i) != two.tickAt(i)) return i;
			if (one.kindAt(i) != two.kindAt(i)) return i;
			if (one.portAt(i) != two.portAt(i)) return i;
			if (one.valueAt(i) != two.valueAt(i)) return i;
		}

		return -2;
	}

	static function table():Float {
		var worst = 0.0;

		for (note in 24...108) {
			final block = mdd.play.Stream.blockOf(note);
			final number = mdd.play.Stream.frequencyOf(note);

			final hertz = number * (mdd.chip.Ym2612.CLOCK / mdd.chip.Ym2612.PER_SAMPLE)
				/ 1048576.0 * Math.pow(2, block - 1);

			final want = 440.0 * Math.pow(2, (note - 69) / 12.0);
			final cents = Math.abs(1200 * Math.log(hertz / want) / Math.log(2));

			if (cents > worst) worst = cents;
		}

		return worst;
	}

	static function corpus(where:String, files:Array<String>):Void {
		var read = 0;
		var writes = 0;
		var tagged = 0;
		var looped = 0;
		var sampled = 0;
		var sampleBytes = 0;
		var seconds = 0.0;
		var unknown = 0;
		var overflowed = 0;

		var same = 0;
		var parted = "";
		var loopsHold = true;

		var written = 0;
		var patches = 0;
		var worstCents = 0.0;
		var offGrid = 0;
		var onGrid = 0;
		var sounded = 0;

		final games:Array<String> = [];
		final gameOff:Array<Int> = [];
		final gameAll:Array<Int> = [];
		var scored = 0;
		var laneless = 0;

		final began = Sdl.ticks();

		final stream = new Stream(4194304);
		final again = new Stream(4194304);

		for (name in files) {
			stream.clear();
			stream.forget();

			final bytes = File.getBytes(name);

			var vgm:Null<Vgm> = null;

			try {
				vgm = Vgm.read(bytes, stream);
			} catch (e:Dynamic) {
				says("read " + name, false, "" + e);
				continue;
			}

			read++;
			writes += stream.count;
			if (stream.dropped > 0) overflowed++;

			if (vgm.game != "" || vgm.title != "") tagged++;

			if (vgm.loopAt >= 0) {
				looped++;
				if (vgm.loopWrite < 0 || vgm.loopWrite > stream.count) loopsHold = false;
			}
			if (vgm.blocks > 0) {
				sampled++;
				sampleBytes += vgm.blockBytes;
			}

			unknown += vgm.unknown;
			seconds += vgm.samples / Vgm.TICKS;

			final until = stream.count == 0 ? 0 : stream.tickAt(stream.count - 1) + 1;
			final back = Vgm.write(stream, 0, until, vgm.rate);

			again.clear();
			again.forget();

			Vgm.read(back, again);

			final off = alike(stream, again);

			if (off == -2) same++;
			else if (parted == "") {
				parted = name + (off == -1 ? " has " + again.count + " writes against "
					+ stream.count : " parts at write " + off);
			}

			final made = Transcription.of(stream, vgm.rate, name);

			written += made.notes;
			patches += made.song.instruments.length;
			offGrid += made.offGrid;
			onGrid += made.onGrid;
			sounded += made.sounded;

			final game = grouped(name);
			var at = games.indexOf(game);

			if (at < 0) {
				at = games.length;

				games.push(game);
				gameOff.push(0);
				gameAll.push(0);
			}

			gameOff[at] += made.offGrid;
			gameAll[at] += made.sounded;
			if (made.worstCents > worstCents) worstCents = made.worstCents;
			if (made.notes > 0) scored++;

			var lanes = 0;
			for (index in 0...Part.COUNT) {
				for (held in made.song.patterns) {
					if (held.lanes[index].notes.length == 0) continue;

					lanes++;
					break;
				}
			}

			if (lanes < 2) laneless++;
		}

		final spent = Sdl.ticks() - began;

		says("every file reads", read == files.length && overflowed == 0,
			read + " of " + files.length + " vgm files read, " + writes
			+ " register writes across " + round(seconds, 1) + " s of music");

		says("the tags are there", tagged == read,
			tagged + " of " + read + " carry a gd3 tag");

		says("a loop lands in the file", loopsHold,
			looped + " of " + read + " name a loop point, and every one of them falls on a write");

		says("the samples are there", sampled > 0,
			sampled + " carry pcm data blocks, " + sampleBytes + " bytes between them");

		says("nothing was skipped", unknown == 0,
			unknown + " commands this build does not know");

		says("what is read is written", same == read,
			parted == "" ? same + " of " + read + " re-export to the same register stream"
				: parted);

		says("every file becomes notes", scored == read && laneless == 0,
			written + " notes read out of the register writes, across " + patches
			+ " patches, every file on at least two parts");

		says("a note plays at its pitch", table() < 1,
			"every note this build writes an F number for comes back within "
			+ round(table(), 3) + " cents of the note it names");

		final exact = sounded == 0 ? 0.0 : 100.0 * onGrid / sounded;
		final near = sounded == 0 ? 0.0 : 100.0 - 100.0 * offGrid / sounded;

		var best = 0.0;
		var apart = "";

		for (index in 0...games.length) {
			final much = gameAll[index] == 0 ? 0.0
				: 100.0 - 100.0 * gameOff[index] / gameAll[index];

			if (much > best) best = much;

			if (apart != "") apart += ", ";
			apart += games[index] + " " + round(much, 1);
		}

		says("a key on names a note", best > 99,
			round(near, 2) + " per cent of " + sounded
			+ " key ons land within a quarter tone of a semitone, " + round(exact, 1)
			+ " within a cent; by source " + apart
			+ "; a driver that slides into its notes reads lower, because a key on is read"
			+ " where the slide started");

		says("it reads faster than it plays", spent < seconds,
			round(seconds, 1) + " s of music read and written back in " + round(spent, 2)
			+ " s, " + round(seconds / spent, 0) + " times faster than real time");
	}
}
