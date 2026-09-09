package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Xgm;
import mdd.play.Render;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.Song;
import mdd.song.Tempo;

@:unreflective
class XgmCheck {
	static inline final SECONDS = 30;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  xgm");

		final where = Gate.root + "/vendor/vgm";

		if (!sys.FileSystem.isDirectory(where)) {
			Sys.println("    not run: no vgm beside the build to make a song from");
			return Gate.SKIPPED;
		}

		final name = Fixtures.found("Green Hill");

		if (name == "") {
			Sys.println("    no Green Hill in the corpus");
			return 1;
		}

		final source = new Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final span = Tempo.TICKS * SECONDS;
		final made = new Stream(1 << 22);
		final sequencer = new Sequencer(song, null, Sequencer.CHUNK * 2);

		sequencer.spanned(made, 0, span);

		final wrote = Xgm.write(song, made, 0, span, song.tempo.rate);
		final bytes = wrote.written;

		shaped(bytes);

		final back = new Stream(1 << 22);
		final read = Xgm.read(bytes, back);

		named(read, bytes);
		agreed(made, back, span);
		sounded(back, song, name);
		drawn();

		final into = args.indexOf("--wav");
		if (into >= 0 && into + 1 < args.length) heard(back, args[into + 1]);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function shaped(bytes:haxe.io.Bytes):Void {
		final block = bytes.getUInt16(0x0100) * Xgm.ALIGN;
		final music = bytes.getInt32(0x0104 + block);

		var slots = 0;
		var covered = true;

		for (index in 0...Xgm.SLOTS) {
			final at = Xgm.TABLE + index * 4;
			if (bytes.getUInt16(at) == 0xFFFF) continue;

			slots++;

			final start = bytes.getUInt16(at) * Xgm.ALIGN;
			final many = bytes.getUInt16(at + 2) * Xgm.ALIGN;

			if (start + many > block || many == 0) covered = false;
		}

		final ends = 0x0108 + block + music;
		final tagged = (bytes.get(0x0103) & 2) != 0;

		says("a song writes an xgm file", bytes.getString(0, 4) == Xgm.MARK
			&& bytes.get(0x0102) == 1 && covered && ends <= bytes.length,
			bytes.length + " bytes: " + slots + " samples in " + block
			+ " bytes of pcm, " + music + " bytes of music, version "
			+ bytes.get(0x0102) + ", " + (covered ? "every" : "not every")
			+ " sample inside the block");

		says("and every sample is aligned", covered && slots > 0,
			slots + " samples, address and length both a multiple of " + Xgm.ALIGN);

		says("and the music ends where it says", bytes.get(ends - 1) == Xgm.END,
			"the last byte of the music is " + StringTools.hex(bytes.get(ends - 1), 2)
			+ ", which is the end command");

		says("and its tags follow the music", tagged
			&& bytes.getString(ends, 4) == "Gd3 "
			&& ends + 12 + bytes.getInt32(ends + 8) == bytes.length,
			(bytes.length - ends) + " bytes of tags after the music, "
			+ (tagged ? "with" : "without") + " the flag that says they are there");
	}

	static function hits(bytes:haxe.io.Bytes):Int {
		final back = new Stream(1 << 18);
		return Xgm.read(bytes, back).struck;
	}

	static function drawn():Void {
		final song = mdd.app.Session.started(mdd.song.Library.embedded()).song;
		final pattern = song.patterns[0];
		final lane = pattern.lane(mdd.song.Part.Dac);

		for (step in 0...4) lane.add(new mdd.song.Note(step * 96, 48, 60));

		for (track in song.tracks) track.clips.resize(0);
		song.tracks[0].clips.push(new mdd.song.Clip(0, 0, pattern.length));

		final span = song.tempo.samplesAt(pattern.length);
		final made = new Stream(1 << 20);

		new Sequencer(song).spanned(made, 0, span);

		final wrote = Xgm.write(song, made, 0, span, song.tempo.rate);

		says("a converter note that names no instrument still exports",
			wrote.samples == 1 && wrote.struck == 4 && hits(wrote.written) == 4,
			"4 notes drawn on the converter with no instrument named export as "
			+ wrote.struck + " hits from " + wrote.samples + " samples, and "
			+ hits(wrote.written) + " come back out of the file");

		song.muted[mdd.song.Part.Dac.index()] = true;

		final quiet = Xgm.write(song, made, 0, span, song.tempo.rate);

		says("and a muted converter exports none of them",
			quiet.samples == 0 && quiet.struck == 0,
			"the same song with the converter muted writes " + quiet.struck
			+ " hits and " + quiet.samples + " samples");

		song.muted[mdd.song.Part.Dac.index()] = false;
		song.name = "a drawn song";
		song.author = "the gate";

		final tagged = Xgm.write(song, made, 0, span, song.tempo.rate);
		final again = new Stream(1 << 18);
		final read = Xgm.read(tagged.written, again);

		says("and the song's name and author survive the round trip",
			read.title == song.name && read.author == song.author,
			"the file says '" + read.title + "' by '" + read.author + "'");
	}

	static function named(read:Xgm, bytes:haxe.io.Bytes):Void {
		says("and it reads back as itself", read.version == 1 && read.unknown == 0,
			read.frames + " frames, " + read.commands + " commands, " + read.samples
			+ " samples of " + read.sampleBytes + " bytes, " + read.struck
			+ " pcm hits, " + read.rate + " Hz, " + read.unknown
			+ " commands it does not know");
	}

	static function agreed(made:Stream, back:Stream, span:Int):Void {
		final one = new Vector<Int>(512);
		final two = new Vector<Int>(512);

		for (index in 0...512) {
			one[index] = -1;
			two[index] = -1;
		}

		poured(made, one, span);
		poured(back, two, span);

		var apart = 0;
		var counted = 0;
		var worst = "";

		for (half in 0...2) {
			for (address in 0x22...0xB7) {
				if (address >= 0x2A && address <= 0x2B) continue;

				final at = (half << 8) | address;
				if (one[at] < 0 && two[at] < 0) continue;

				counted++;
				if (one[at] == two[at]) continue;

				apart++;
				if (worst == "") {
					worst = "half " + half + " register " + StringTools.hex(address, 2)
						+ " is " + one[at] + " and comes back " + two[at];
				}
			}
		}

		says("and the registers come back", apart == 0,
			counted + " registers the song writes, all of them the same after the round trip"
			+ (worst == "" ? "" : ", except " + worst));
	}

	static function poured(stream:Stream, shadow:Vector<Int>, until:Int):Void {
		var half = 0;
		var address = -1;

		for (index in 0...stream.count) {
			if (stream.tickAt(index) > until) break;
			if (stream.kindAt(index) != Stream.YM) continue;

			final port = stream.portAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = stream.valueAt(index);
				continue;
			}

			if (address >= 0) shadow[(half << 8) | address] = stream.valueAt(index);
		}
	}

	static function sounded(back:Stream, song:Song, name:String):Void {
		final render = new Render(44100, Render.BLOCK);
		final frames = 44100 * 8;

		var done = 0;
		var peak = 0.0;
		var total = 0.0;

		while (done < frames) {
			final at = Std.int(done * (Tempo.TICKS / 44100.0));
			final many = render.serve(back, at, Render.BLOCK, 0);

			if (many <= 0) break;

			for (index in 0...many) {
				final value = render.block[index * 2];
				final much = value < 0 ? -value : value;

				if (much > peak) peak = much;
				total += value * value;
			}

			done += many;
		}

		says("and an xgm makes a sound", peak > 0.01 && done > 0,
			round(done / 44100.0, 1) + " s rendered from what came back, loudest sample "
			+ round(peak, 4) + " and " + round(Math.sqrt(total / (done < 1 ? 1 : done)), 4)
			+ " of full scale held");

		final made = mdd.format.Transcription.of(back, 60, name);

		var dac = 0;
		var fm = 0;

		for (pattern in made.song.patterns) {
			dac += pattern.lane(mdd.song.Part.Dac).notes.length;
			for (index in 0...6) fm += pattern.lane(index).notes.length;
		}

		says("and an xgm becomes a song", made.notes > 0 && fm > 0,
			made.notes + " notes across " + made.song.patterns.length + " patterns: "
			+ fm + " on the fm parts and " + dac + " on the converter");
	}

	static function heard(back:Stream, where:String):Void {
		final seconds = 45;
		final frames = 44100 * seconds;

		final render = new Render(44100, Render.BLOCK);
		final held = new Vector<cpp.Float32>(frames * 2);

		var done = 0;

		while (done < frames) {
			final at = Std.int(done * (Tempo.TICKS / 44100.0));
			final many = render.serve(back, at, Render.BLOCK, 0);

			if (many <= 0) break;

			var take = many;
			if (done + take > frames) take = frames - done;

			for (index in 0...take * 2) held[done * 2 + index] = render.block[index];
			done += take;
		}

		sys.io.File.saveBytes(where, mdd.format.Wav.write(held, done, 2, 44100));
		Sys.println("    wrote " + round(done / 44100.0, 1) + " s to " + where);
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "      FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}
}
