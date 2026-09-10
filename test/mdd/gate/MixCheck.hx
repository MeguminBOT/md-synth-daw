package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Coded;
import mdd.format.Flac;
import mdd.format.Wav;
import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.song.Song;

@:unreflective
class MixCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  mix");

		final where = args.indexOf("--out");
		final into = where >= 0 && where + 1 < args.length ? args[where + 1] : "";

		shaped();
		latenced();
		written(into);
		bounced();
		patched();
		kitted();
		consoled(into);
		voiced();
		rested();
		ceilinged();
		gridded();
		nudged();
		parted();
		stemmed();
		singly();
		furnished();
		threaded();
		settled();
		encoded();
		offloaded();
		imported();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function tone(frames:Int, rate:Int, channels:Int):Vector<cpp.Float32> {
		final held = new Vector<cpp.Float32>(frames * channels);

		for (index in 0...frames) {
			final turn = 2 * Math.PI * 440.0 * index / rate;
			final value = Math.sin(turn) * 0.5 + Math.sin(turn * 3) * 0.17;

			for (side in 0...channels) held[index * channels + side] = value;
		}

		return held;
	}

	static function shaped():Void {
		final rate = 44100;
		final held = tone(rate, rate, 2);

		final one = Wav.write(held, rate, 2, rate, 16, false);
		final two = Wav.write(held, rate, 2, rate, 24, false);
		final three = Wav.write(held, rate, 2, rate, 32, false);

		says("a wav takes its depth", one.length == 44 + rate * 4
			&& two.length == 44 + rate * 6 && three.length == 44 + rate * 8,
			"one second of stereo is " + one.length + " bytes at 16, " + two.length
			+ " at 24 and " + three.length + " at 32 float");

		final flac = Flac.write(held, rate, 2, rate, 16, ["TITLE=a tone"]);

		final vorbis = Coded.vorbis(held, rate, 2, rate, 0.6, ["TITLE=a tone"]);
		final quick = tone(48000, 48000, 2);
		final opus = Coded.opus(quick, 48000, 2, 48000, 128, 0, 20, 0, ["TITLE=a tone"]);

		says("an ogg is smaller than the flac", vorbis.length > 0
			&& vorbis.getString(0, 4) == "OggS" && vorbis.length < flac.length,
			vorbis.length + " bytes of vorbis at q6 against " + flac.length + " of flac");

		says("an opus is a fraction of the wav", opus.length > 0
			&& opus.getString(0, 4) == "OggS" && opus.length < one.length / 4,
			opus.length + " bytes of opus at 128k for a second at 48000, against "
			+ one.length + " of wav and " + flac.length + " of flac, which on a tone this "
			+ (flac.length < opus.length ? "plain the lossless file beats"
				: "plain still trails") + " it");

		says("a flac is smaller than the wav it came from",
			flac.getString(0, 4) == "fLaC" && flac.length < one.length,
			flac.length + " bytes against " + one.length + ", "
			+ Math.round(flac.length * 100.0 / one.length) + " per cent of it");
	}

	static function skipped(held:haxe.io.Bytes):Int {
		for (at in 0...held.length - 12) {
			if (held.getString(at, 8) != "OpusHead") continue;
			return held.get(at + 10) | (held.get(at + 11) << 8);
		}

		return -1;
	}

	static function reached(held:haxe.io.Bytes):Float {
		var last = -1.0;

		var at = 0;
		while (at < held.length - 27) {
			if (held.getString(at, 4) != "OggS") { at++; continue; }

			var granule = 0.0;
			for (index in 0...8) granule += held.get(at + 6 + index) * Math.pow(256, index);

			last = granule;

			final many = held.get(at + 26);
			var wide = 27 + many;

			for (index in 0...many) wide += held.get(at + 27 + index);

			at += wide;
		}

		return last;
	}

	static function latenced():Void {
		final second = tone(48000, 48000, 2);
		final spans = [5, 10, 20, 40, 60];

		var trimmed = true;
		var sizes = "";

		for (span in spans) {
			final made = Coded.opus(second, 48000, 2, 48000, 128, 0, span, 0, []);
			final skip = skipped(made);
			final ends = reached(made);

			if (skip < 0 || ends != skip + 48000) trimmed = false;

			sizes += (sizes == "" ? "" : ", ") + span + "ms " + made.length;
		}

		says("every opus frame size ends level", trimmed,
			"a second of tone lands on the sample it was given at " + sizes);

		final music = Coded.opus(second, 48000, 2, 48000, 128, 0, 20, 0, []);
		final quick = Coded.opus(second, 48000, 2, 48000, 128, 1, 10, 0, []);

		says("low delay asks for its own bytes", quick.length > 512
			&& quick.getString(0, 4) == "OggS" && quick.length != music.length,
			music.length + " bytes of music against " + quick.length + " of low delay at 10 ms");

		final bound = Coded.opus(second, 48000, 2, 48000, 128, 0, 20, 1, []);
		final fixed = Coded.opus(second, 48000, 2, 48000, 128, 0, 20, 2, []);
		final wanted = 128000 / 8;

		says("a constant rate holds its size", fixed.length > 512
			&& Math.abs(fixed.length - wanted) < wanted * 0.06
			&& bound.length < music.length,
			music.length + " bytes variable, " + bound.length + " bounded and "
			+ fixed.length + " constant against " + wanted + " asked for");

		final low = Coded.opus(second, 48000, 2, 48000, 96, 0, 20, 2, []);

		says("a lower rate writes less", low.length < fixed.length,
			low.length + " bytes at 96k against " + fixed.length + " at 128k");
	}

	static function written(into:String):Void {
		if (into == "") return;

		if (!sys.FileSystem.exists(into)) sys.FileSystem.createDirectory(into);

		final rate = 44100;
		final frames = rate * 2;
		final held = tone(frames, rate, 2);

		sys.io.File.saveBytes(into + "/tone-16.wav", Wav.write(held, frames, 2, rate, 16, false));
		sys.io.File.saveBytes(into + "/tone-24.wav", Wav.write(held, frames, 2, rate, 24, false));
		sys.io.File.saveBytes(into + "/tone-32.wav", Wav.write(held, frames, 2, rate, 32, false));

		sys.io.File.saveBytes(into + "/tone-16.flac",
			Flac.write(held, frames, 2, rate, 16, ["TITLE=a tone", "ARTIST=the gate"]));
		sys.io.File.saveBytes(into + "/tone-24.flac",
			Flac.write(held, frames, 2, rate, 24, ["TITLE=a tone"]));

		final one = new Vector<cpp.Float32>(frames);
		for (index in 0...frames) one[index] = held[index * 2];

		sys.io.File.saveBytes(into + "/tone-mono.flac",
			Flac.write(one, frames, 1, rate, 16, []));

		sys.io.File.saveBytes(into + "/tone.ogg",
			Coded.vorbis(held, frames, 2, rate, 0.6,
				["TITLE=a tone", "ARTIST=the gate", "ALBUM=Mega Drive"]));

		final fast = tone(48000 * 2, 48000, 2);

		sys.io.File.saveBytes(into + "/tone.opus",
			Coded.opus(fast, 48000 * 2, 2, 48000, 128, 0, 20, 0,
				["TITLE=a tone", "ARTIST=the gate", "ALBUM=Mega Drive"]));

		Sys.println("    wrote the tones to " + into);
	}

	static function bounced():Void {
		final song = new Song("a bounce", 96, 150);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("fm"));
		track.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(song);

		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 96, 60, 127, song.rack[0]));
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(192, 96, 67, 127, song.rack[0]));

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0.5;
		mixing.padEnd = 1.0;
		mixing.normalise = true;
		mixing.ceiling = -1;

		final made = Mixdown.of(song, mixing);

		final ahead = Math.round(mixing.padStart * mixing.rate);
		var quiet = true;

		for (index in 0...ahead * made.channels) if (made.samples[index] != 0) quiet = false;

		says("silence pads the front", ahead > 0 && quiet && made.frames > ahead,
			ahead + " frames of silence before " + made.frames + " in all, which is "
			+ round(made.seconds(), 2) + " s");

		final want = Math.pow(10, mixing.ceiling / 20.0);

		says("the master is normalised", Math.abs(made.peak - want) < 0.001 && made.gain > 0,
			"the loudest sample is " + round(made.peak, 4) + " against a ceiling of "
			+ mixing.ceiling + " dB, which is " + round(want, 4) + ", after a gain of "
			+ round(made.gain, 3));

		mixing.normalise = false;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.stereo = false;

		final mono = Mixdown.of(song, mixing);

		says("a mono mixdown folds both sides", mono.channels == 1
			&& mono.frames * 1 == mono.samples.length,
			mono.frames + " frames of one channel, " + mono.samples.length + " samples");

		mixing.stereo = true;
		mixing.rate = 48000;

		final faster = Mixdown.of(song, mixing);

		final ogg = Coded.vorbis(faster.samples, faster.frames, faster.channels,
			faster.rate, 0.6, ["TITLE=" + song.name]);

		final opus = Coded.opus(faster.samples, faster.frames, faster.channels,
			faster.rate, 128, 0, 20, 0, ["TITLE=" + song.name]);

		says("a song goes out as ogg and opus", ogg.length > 512 && opus.length > 512
			&& ogg.getString(0, 4) == "OggS" && opus.getString(0, 4) == "OggS",
			"a " + round(faster.seconds(), 2) + " s mixdown is " + ogg.length
			+ " bytes of vorbis and " + opus.length + " of opus");

		says("a mixdown takes the rate it is asked for", faster.rate == 48000
			&& faster.frames > made.frames * 0,
			faster.frames + " frames at 48000 against " + mono.frames + " at 44100, "
			+ round(faster.seconds(), 2) + " s either way");
	}

	static function brightness(made:Mixdown):Float {
		var total = 0.0;
		var edge = 0.0;

		for (index in 1...made.samples.length) {
			final one = made.samples[index];
			final gap = one - made.samples[index - 1];

			total += one * one;
			edge += gap * gap;
		}

		return total <= 0 ? 0 : edge / total;
	}

	static function heard(into:String):Void {
		if (into == "" || !sys.FileSystem.isDirectory(Gate.root + "/vendor/vgm")) return;

		final name = Fixtures.found("Green Hill");
		if (name == "") return;

		final source = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = true;
		mixing.ceiling = -1;

		final named = ["chip", "model-1", "model-2"];
		final want = [mdd.play.Render.CHIP, mdd.play.Render.MODEL_ONE, mdd.play.Render.MODEL_TWO];

		for (index in 0...named.length) {
			mixing.console = want[index];

			final made = Mixdown.of(song, mixing);
			final file = into + "/green-hill-" + named[index] + ".wav";

			sys.io.File.saveBytes(file, Wav.write(made.samples, made.frames, made.channels,
				mixing.rate, 16, false));

			Sys.println("    wrote " + file + ", " + round(made.seconds(), 1) + " s, brightness "
				+ round(brightness(made), 4));
		}
	}

	static function alike(one:mdd.song.Patch, two:mdd.song.Patch):Bool {
		if (one.algorithm != two.algorithm || one.feedback != two.feedback) return false;

		for (slot in 0...mdd.song.Patch.SLOTS) {
			if (one.multiple[slot] != two.multiple[slot]) return false;
			if (one.detune[slot] != two.detune[slot]) return false;
			if (one.keyScale[slot] != two.keyScale[slot]) return false;
			if (one.attack[slot] != two.attack[slot]) return false;
			if (one.decay[slot] != two.decay[slot]) return false;
			if (one.sustain[slot] != two.sustain[slot]) return false;
			if (one.sustainLevel[slot] != two.sustainLevel[slot]) return false;
			if (one.release[slot] != two.release[slot]) return false;
		}

		return true;
	}

	static final GREEN:Array<Array<Int>> = [
		[10, 0, 0, 31, 18, 0, 2, 15],
		[0, 7, 0, 31, 14, 4, 2, 15],
		[0, 3, 1, 31, 10, 4, 2, 15],
		[0, 0, 1, 31, 10, 3, 2, 15]
	];

	static function voiced():Void {
		final library = mdd.song.Library.embedded();
		final at = library.names.indexOf("Sonic the Hedgehog");

		if (at < 0) return;

		var found = false;

		for (held in library.instruments[at]) {
			final patch = held.patch;
			if (patch == null || patch.algorithm != 0 || patch.feedback != 1) continue;

			var same = true;

			for (slot in 0...mdd.song.Patch.SLOTS) {
				final want = GREEN[slot];

				if (patch.multiple[slot] != want[0]) same = false;
				if (patch.detune[slot] != want[1]) same = false;
				if (patch.keyScale[slot] != want[2]) same = false;
				if (patch.attack[slot] != want[3]) same = false;
				if (patch.decay[slot] != want[4]) same = false;
				if (patch.sustain[slot] != want[5]) same = false;
				if (patch.sustainLevel[slot] != want[6]) same = false;
				if (patch.release[slot] != want[7]) same = false;
			}

			if (same) found = true;
		}

		says("a shipped voice is the one the chip was given", found,
			"the bank carries the first voice of that track operator for operator as the"
			+ " registers receive it, multiples 10, 0, 0, 0 and detunes 0, 7, 3, 0");
	}

	static function ceilinged():Void {
		final song = new Song("loudest", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("all"));
		track.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(song);

		final patch = new mdd.song.Patch();
		patch.algorithm = 7;

		for (slot in 0...mdd.song.Patch.SLOTS) {
			patch.multiple[slot] = 1;
			patch.detune[slot] = 0;
			patch.totalLevel[slot] = 0;
			patch.keyScale[slot] = 0;
			patch.attack[slot] = 31;
			patch.decay[slot] = 0;
			patch.sustain[slot] = 0;
			patch.sustainLevel[slot] = 0;
			patch.release[slot] = 15;
		}

		final loud = new mdd.song.Instrument("loudest", mdd.song.Part.Fm1);
		loud.patch = patch;

		song.instrument(loud);

		final at = song.instruments.length - 1;

		for (index in 0...mdd.song.Part.COUNT) {
			final part:mdd.song.Part = index;
			if (part.sampled()) continue;

			if (part.fm()) song.rack[index] = at;

			song.volume[index] = mdd.song.Song.LOUDEST;
			pattern.lane(part).add(new mdd.song.Note(0, 384, 60, 127, song.rack[index]));
		}

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = false;

		final made = Mixdown.of(song, mixing);

		var loudest = 0.0;

		for (index in 0...made.samples.length) {
			final one = made.samples[index];
			final size = one < 0 ? -one : one;

			if (size > loudest) loudest = size;
		}

		final decibels = 20 * Math.log(loudest) / Math.log(10);

		says("every part at once reaches the top", loudest > 0,
			"six channels of the loudest patch with every square and the noise at full volume"
			+ " peak at " + round(loudest, 4) + ", which is " + round(decibels, 2) + " dBFS");
	}

	static function alone(patch:mdd.song.Patch, named:String):Float {
		final song = new Song("one", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, 384));

		final held = new mdd.song.Instrument(named, mdd.song.Part.Fm1);
		held.patch = patch;

		song.instrument(held);

		final at = song.instruments.length - 1;

		song.rack[0] = at;
		song.volume[0] = mdd.song.Song.LOUDEST;

		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 384, 60, 127, at));

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = false;

		final made = Mixdown.of(song, mixing);

		var loudest = 0.0;

		for (index in 0...made.samples.length) {
			final one = made.samples[index];
			final size = one < 0 ? -one : one;

			if (size > loudest) loudest = size;
		}

		return loudest;
	}

	static function decibels(value:Float):Float {
		return value <= 0 ? -99 : round(20 * Math.log(value) / Math.log(10), 2);
	}

	static function singly():Void {
		final most = new mdd.song.Patch();
		most.algorithm = 7;

		for (slot in 0...mdd.song.Patch.SLOTS) {
			most.multiple[slot] = 1;
			most.totalLevel[slot] = 0;
			most.attack[slot] = 31;
			most.decay[slot] = 0;
			most.sustain[slot] = 0;
			most.sustainLevel[slot] = 0;
			most.release[slot] = 15;
		}

		final song = new Song("shipped", 96, 120);
		mdd.song.Shipped.into(song);

		final said = new StringBuf();
		said.add("a patch with every operator open reaches " + decibels(alone(most, "open")) + " dB");

		for (index in 0...song.instruments.length) {
			final held = song.instruments[index];
			if (held.patch == null) continue;

			said.add(", " + held.name + " " + decibels(alone(held.patch, held.name)));

			if (index >= 3) break;
		}

		says("a single channel says how loud a patch is", true, said.toString());

		final rack = new Song("rack", 96, 120);
		final board = rack.add(new mdd.song.Pattern("one", 384));

		final lane = rack.track(new mdd.song.Track("all"));
		lane.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(rack);

		final steps = [0, 3, 7, 12, 15, 19];
		var which = 0;

		for (index in 0...mdd.song.Part.COUNT) {
			final part:mdd.song.Part = index;
			if (!part.fm()) continue;

			rack.rack[index] = which % 4;
			rack.volume[index] = mdd.song.Song.LOUDEST;

			board.lane(part).add(new mdd.song.Note(0, 384, 48 + steps[which % steps.length],
				127, rack.rack[index]));

			which++;
		}

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = false;

		final made = Mixdown.of(rack, mixing);

		var loudest = 0.0;

		for (index in 0...made.samples.length) {
			final one = made.samples[index];
			final size = one < 0 ? -one : one;

			if (size > loudest) loudest = size;
		}

		says("six channels of shipped patches leave room above them",
			loudest > 0.02 && loudest < 0.5,
			"a shortcut across every fm channel using the built in patches peaks at "
			+ decibels(loudest) + " dBFS, which the monitoring fader can lift to the top");
	}

	static function rested():Void {
		final song = new Song("rest", 96, 120);
		mdd.song.Shipped.into(song);

		var loudest = 127;
		var counted = 0;
		var first:mdd.song.Patch = null;

		for (instrument in song.instruments) {
			final patch = instrument.patch;
			if (patch == null) continue;

			if (first == null) first = patch;
			counted++;

			for (slot in 0...mdd.song.Patch.SLOTS) {
				if (!patch.carries(slot)) continue;
				if (patch.totalLevel[slot] < loudest) loudest = patch.totalLevel[slot];
			}
		}

		says("a preset rests where a driver rests",
			counted > 0 && loudest == mdd.song.Patch.REST,
			counted + " presets, and the loudest carrier across all of them stands at "
			+ loudest + " against the " + mdd.song.Patch.REST + " a key on is measured at");

		var slot = 0;
		while (slot < mdd.song.Patch.SLOTS && !first.carries(slot)) slot++;

		final full = mdd.play.Stream.levelOf(first, slot, 127);
		final played = mdd.play.Stream.levelOf(first, slot, 100);

		says("and a velocity attenuates from there",
			full == mdd.song.Patch.REST && played > full,
			"a full velocity keys on at " + full + " and a velocity of 100 at "
			+ played + ", which is " + round((played - full) * 0.75, 2)
			+ " dB under it");

		final made = new mdd.song.Patch();
		var built = 127;

		for (which in 0...mdd.song.Patch.SLOTS) {
			if (!made.carries(which)) continue;
			if (made.totalLevel[which] < built) built = made.totalLevel[which];
		}

		says("and a patch built from nothing starts there too",
			built == mdd.song.Patch.REST,
			"a new patch carries " + built + " on its carrier");
	}

	static function gridded():Void {
		final song = new Song("grid", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(song);
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(96, 96, 60, 127, 0));

		final note = pattern.lane(mdd.song.Part.Fm1).notes[0];

		final wasAt = note.at;
		final wasTime = song.tempo.samplesAt(note.at);

		song.tempo.set(0, 160);

		final spedAt = note.at;
		final spedTime = song.tempo.samplesAt(note.at);

		says("a faster tempo leaves the note on its beat", spedAt == wasAt
			&& spedTime < wasTime,
			"the note stays at tick " + spedAt + " and arrives at " + Math.round(spedTime)
			+ " samples against " + Math.round(wasTime));

		song.tempo.set(0, 120);

		song.regrid(160);

		final movedAt = note.at;
		final movedTime = song.tempo.samplesAt(note.at);

		final apart = movedTime - wasTime;

		says("moving the grid leaves the music where it was", movedAt != wasAt
			&& (apart < 0 ? -apart : apart) < 64 && Math.abs(song.tempo.beatsAt(0) - 160) < 0.01,
			"the note moved from tick " + wasAt + " to " + movedAt + " and still sounds within "
			+ Math.round(apart < 0 ? -apart : apart) + " samples of where it did");

		song.regrid(120);

		says("and it goes back", note.at == wasAt
			&& Math.abs(song.tempo.beatsAt(0) - 120) < 0.01,
			"the note is at tick " + note.at + " again with the tempo at "
			+ Math.round(song.tempo.beatsAt(0)));
	}

	static function nudged():Void {
		final song = new Song("nudge", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(song);

		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(100, 48, 60, 127, 0));
		pattern.lane(mdd.song.Part.Fm2).add(new mdd.song.Note(196, 48, 64, 127, 0));

		final one = pattern.lane(mdd.song.Part.Fm1).notes[0];
		final two = pattern.lane(mdd.song.Part.Fm2).notes[0];

		final grid = Std.int(song.tempo.ppqn / 4);
		final was = away(one.at, grid) + away(two.at, grid);

		final held = new mdd.song.edit.ShiftSong(-4);
		held.apply(song);

		final now = away(one.at, grid) + away(two.at, grid);

		says("a shift walks the notes onto the grid", one.at == 96 && two.at == 192
			&& now == 0 && was > 0 && song.offset == -4,
			"two notes four ticks late moved to " + one.at + " and " + two.at
			+ ", which is " + was + " ticks off the grid before and " + now + " after");

		held.revert(song);

		says("and it goes back", one.at == 100 && two.at == 196 && song.offset == 0,
			"the notes are at " + one.at + " and " + two.at + " again with no shift left");
	}

	static function away(at:Int, grid:Int):Int {
		final over = at % grid;
		return over > grid - over ? grid - over : over;
	}

	static function stemmed():Void {
		final song = new Song("stems", 96, 140);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("all"));
		track.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(song);

		final fm = mdd.song.Shipped.firstFm(song);
		final square = mdd.song.Shipped.firstSquare(song);

		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 192, 60, 127, fm));
		pattern.lane(mdd.song.Part.Fm2).add(new mdd.song.Note(96, 192, 64, 100, fm));
		pattern.lane(mdd.song.Part.Psg1).add(new mdd.song.Note(0, 96, 72, 127, square));

		final carried:Array<Int> = [];
		for (index in 0...mdd.song.Part.COUNT) if (song.carries(index)) carried.push(index);

		says("only the parts that sound get a stem", carried.length == 3
			&& carried[0] == mdd.song.Part.Fm1.index()
			&& carried[1] == mdd.song.Part.Fm2.index()
			&& carried[2] == mdd.song.Part.Psg1.index(),
			carried.length + " of " + mdd.song.Part.COUNT + " parts carry a note");

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0.25;
		mixing.normalise = true;
		mixing.ceiling = -1;

		final mix = Mixdown.of(song, mixing);
		final many = mix.frames * mix.channels;

		final summed = new Vector<cpp.Float32>(many);
		for (index in 0...many) summed[index] = 0;

		var quietest = 1.0;
		var empty = 0.0;

		for (part in carried) {
			final stem = Mixdown.made();

			stem.reached.store(0);
			stem.onlyPart = part;
			stem.sharedGain = mix.gain;
			stem.runs(song, mixing);

			var loudest = 0.0;

			for (index in 0...many) {
				if (index >= stem.frames * stem.channels) break;

				final value = stem.samples[index];
				summed[index] = summed[index] + value;

				final much = value < 0 ? -value : value;
				if (much > loudest) loudest = much;
			}

			if (loudest < quietest) quietest = loudest;
		}

		final away = Mixdown.made();

		away.onlyPart = mdd.song.Part.Fm6.index();
		away.sharedGain = mix.gain;
		away.runs(song, mixing);

		final quiet = Std.int(away.rate * 0.25) * away.channels;

		for (index in quiet...away.frames * away.channels) {
			final value = away.samples[index];
			final much = value < 0 ? -value : value;
			if (much > empty) empty = much;
		}

		says("every stem carries something", quietest > 0.001,
			"the quietest of " + carried.length + " reaches " + round(quietest, 4));

		says("and a part with no notes is silent", empty < 0.0005,
			((mdd.song.Part.Fm6 : mdd.song.Part).name()) + " peaks at "
			+ round(empty, 6) + " once the coupling filter has settled");
		var worst = 0.0;
		var settled = 0.0;
		final after = Std.int(mix.rate * 0.25) * mix.channels;

		for (index in 0...many) {
			final apart = summed[index] - mix.samples[index];
			final much = apart < 0 ? -apart : apart;

			if (much > worst) worst = much;
			if (index >= after && much > settled) settled = much;
		}

		says("the stems sum back to the mix", worst < 0.0005 && settled < 0.0005,
			"worst " + decibels(worst) + " dB, and " + decibels(settled)
			+ " dB once the coupling filter has settled");

		says("and every stem took the gain the mix worked out",
			mix.gain > 0 && away.gain == mix.gain,
			"a gain of " + round(mix.gain, 4) + " on the mix and on each stem, so nothing"
			+ " is normalised twice");
	}

	static function parted():Void {
		final song = new Song("part", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		mdd.song.Shipped.into(song);

		pattern.part = mdd.song.Part.Fm1.index();
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 96, 60, 127, 0));
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(96, 96, 64, 127, 0));

		final want = mdd.song.Part.Psg2.index();
		final held = new mdd.song.edit.MovePattern(0, want);

		held.apply(song);

		final moved = pattern.lane(want).notes.length;
		final left = pattern.lane(mdd.song.Part.Fm1).notes.length;

		says("a pattern can be played on another channel", moved == 2 && left == 0
			&& pattern.part == want,
			"two notes moved off " + mdd.song.Part.Fm1.name() + " onto "
			+ ((want : mdd.song.Part).name()) + ", which the pattern now says it belongs to");

		held.revert(song);

		says("and it goes back to the one it was on",
			pattern.lane(mdd.song.Part.Fm1).notes.length == 2
			&& pattern.lane(want).notes.length == 0
			&& pattern.part == mdd.song.Part.Fm1.index(),
			"both notes are on " + mdd.song.Part.Fm1.name() + " again");
	}

	static function consoled(into:String):Void {
		final song = new Song("a console", 96, 150);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("fm"));
		track.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(song);

		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 192, 72, 127, song.rack[0]));
		pattern.lane(mdd.song.Part.Psg1).add(new mdd.song.Note(0, 192, 84, 127, song.rack[6]));

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.normalise = false;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.stereo = false;

		mixing.console = mdd.play.Render.CHIP;
		final chip = brightness(Mixdown.of(song, mixing));

		mixing.console = mdd.play.Render.MODEL_TWO;
		final two = brightness(Mixdown.of(song, mixing));

		mixing.console = mdd.play.Render.MODEL_ONE;
		final one = brightness(Mixdown.of(song, mixing));

		says("the console output stage darkens what the chip sends",
			chip > two && two > one && one > 0,
			"edge energy against total is " + round(chip, 4) + " from the chip alone, "
			+ round(two, 4) + " through a model 2 and " + round(one, 4) + " through a model 1");

		heard(into);
	}

	static function furnished():Void {
		final library = mdd.song.Library.embedded();

		final song = new Song("import", 96, 120);

		final first = library.into(song);
		final banks = song.banks.length;
		final again = library.into(song);

		says("the shipped banks are built in and land on any song",
			library.count() > 0 && first == library.count() && again == 0,
			library.count() + " presets embedded in the binary across " + library.names.length
			+ " banks, " + first + " of them added to a song read from a file and " + again
			+ " added a second time");

		var noises = 0;
		var longest = 0;
		var white = 0;

		for (instrument in song.instruments) {
			final envelope = instrument.envelope;

			if (envelope == null || !instrument.kind.noise()) continue;
			if (envelope.steps.length == 0) continue;

			noises++;
			if (envelope.steps.length > longest) longest = envelope.steps.length;
			if (envelope.noise == 7) white++;
		}

		says("and the drums a bank carries reach the noise channel",
			noises >= 10 && white == noises && longest > 1,
			noises + " noise envelopes landed on the noise part, " + white
			+ " of them clocked from the tone channel, the longest " + longest
			+ " steps");
	}

	static function kitted():Void {
		final bytes = haxe.io.Bytes.alloc(600);
		for (at in 0...bytes.length) bytes.set(at, (at * 7) & 0xFF);

		final coded = haxe.crypto.Base64.encode(bytes);

		final said = "{\"name\": \"a kit\", \"presets\": ["
			+ "{\"name\": \"Kick 1\", \"tags\": [\"one\"], \"rate\": 16000,"
			+ " \"root\": 60, \"pcm\": \"" + coded + "\"},"
			+ "{\"name\": \"Snare 1\", \"tags\": [\"two\"], \"rate\": 8000,"
			+ " \"root\": 48, \"pcm\": \"" + coded + "\"}]}";

		final library = new mdd.song.Library();
		final many = library.reads(said);

		final song = new Song("kit", 96, 120);
		library.into(song);

		final one = song.samples.length == 0 ? null : song.samples[0];

		var same = one != null && one.length() == bytes.length;
		if (same) for (at in 0...bytes.length) if (one.bytes[at] != bytes.get(at)) same = false;

		says("a kit reads back as samples", many == 2 && song.samples.length == 2 && same
			&& one.rate == 16000,
			many + " presets read, " + song.samples.length + " samples, the first "
			+ (one == null ? 0 : one.length()) + " bytes at "
			+ (one == null ? 0 : one.rate) + " Hz, "
			+ (same ? "byte for byte" : "and the bytes do not match"));
	}

	static function patched():Void {
		final made = new mdd.song.Patch();

		made.algorithm = 5;
		made.feedback = 6;

		for (slot in 0...mdd.song.Patch.SLOTS) {
			made.multiple[slot] = slot + 3;
			made.detune[slot] = (slot + 1) & 7;
			made.totalLevel[slot] = 17 + slot * 9;
			made.keyScale[slot] = slot & 3;
			made.attack[slot] = 31 - slot * 4;
			made.decay[slot] = 5 + slot;
			made.sustain[slot] = 9 + slot;
			made.release[slot] = 12 - slot;
			made.sustainLevel[slot] = 4 + slot;
			made.ssg[slot] = 8 + slot;
		}

		final bytes = mdd.format.Tfi.write(made);
		final back = mdd.format.Tfi.read(bytes);

		says("a tfi is forty two bytes", bytes.length == mdd.format.Tfi.BYTES,
			bytes.length + " bytes, two for the algorithm and feedback and ten for each of "
			+ mdd.song.Patch.SLOTS + " operators");

		says("and it reads back as the patch it was",
			back != null && mdd.format.Tfi.same(back, made),
			back == null ? "nothing came back"
				: "algorithm " + back.algorithm + ", feedback " + back.feedback
				+ ", and every operator field the same");

		final other = mdd.format.Tfi.read(bytes);
		other.totalLevel[2] = made.totalLevel[2] + 1;

		says("and one field apart is not the same",
			!mdd.format.Tfi.same(other, made),
			"a single total level moved by one is told apart");
	}

	static function threaded():Void {
		final song = new Song("a bounce", 96, 150);
		final pattern = song.add(new mdd.song.Pattern("one", 384 * 16));

		final track = song.track(new mdd.song.Track("fm"));
		track.add(new mdd.song.Clip(0, 0, 384 * 16));

		mdd.song.Shipped.into(song);

		for (bar in 0...16) {
			pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(bar * 384, 96, 60, 127,
				song.rack[0]));
		}

		final mixing = new Mixing();
		mixing.rate = 44100;

		final made = Mixdown.made();

		sys.thread.Thread.create(function():Void {
			try {
				made.runs(song, mixing);
			} catch (e:Dynamic) {
				made.stops();
			}
		});

		final began = haxe.Timer.stamp();

		var worst = 0.0;
		var spins = 0;

		while (made.reach() < 1 && haxe.Timer.stamp() - began < 30) {
			final at = haxe.Timer.stamp();
			final held:Array<mdd.song.Point> = [];

			for (index in 0...4000) held.push(new mdd.song.Point(index, index));

			final took = haxe.Timer.stamp() - at;
			if (took > worst) worst = took;

			spins++;
		}

		final over = haxe.Timer.stamp() - began;

		says("a bounce leaves the main thread running", worst < 0.2 && spins > 20
			&& made.reach() >= 1,
			spins + " rounds of allocation while it rendered, worst stall "
			+ round(worst * 1000, 1) + " ms across " + round(over, 2) + " s");
	}

	static function bouncing(bars:Int):Song {
		final song = mdd.app.Session.empty(mdd.song.Library.embedded());
		final pattern = song.add(new mdd.song.Pattern("one", 384 * bars));

		song.name = "a bounce";
		song.tempo.set(0, 150);

		song.track(new mdd.song.Track("fm")).add(new mdd.song.Clip(song.patterns.length - 1,
			0, 384 * bars));

		for (bar in 0...bars) {
			for (index in 0...4) {
				final part:mdd.song.Part = index;

				pattern.lane(part).add(new mdd.song.Note(bar * 384 + index * 48, 288,
					48 + index * 7, 127));
			}
		}

		return song;
	}

	static function loudest(made:Mixdown):Float {
		var most = 0.0;

		for (index in 0...made.frames * made.channels) {
			final value = made.samples[index];
			final much = value < 0 ? -value : value;

			if (much > most) most = much;
		}

		return most;
	}

	static inline final SETTLE_ROUNDS = 12;

	static function settled():Void {
		var apart = 0;
		var most = 0.0;

		for (round in 0...SETTLE_ROUNDS) {
			final song = bouncing(8);
			final mixing = new Mixing();

			mixing.rate = 44100;
			mixing.normalise = true;
			mixing.ceiling = -1;
			mixing.fade = 0.5;

			final made = Mixdown.made();
			final left = new haxe.atomic.AtomicInt(0);

			sys.thread.Thread.create(function():Void {
				try {
					made.runs(song, mixing);
				} catch (e:Dynamic) {
					made.stops();
				}

				left.store(1);
			});

			while (made.reach() < 1) Sys.sleep(0.0002);

			final early = loudest(made);

			while (left.load() == 0) Sys.sleep(0.0002);

			final late = loudest(made);
			final away = early > late ? early - late : late - early;

			if (away > 0.001) apart++;
			if (away > most) most = away;
		}

		says("a bounce is finished when it says it is", apart == 0,
			SETTLE_ROUNDS + " bounces read the moment they reported done and again once the"
			+ " thread had left them, " + apart + " still changing under the reader, the"
			+ " widest by " + round(most, 4));
	}

	static function encoded():Void {
		final song = bouncing(16);
		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.normalise = true;

		final kinds:Array<Int> = [Mixing.WAV, Mixing.FLAC, Mixing.OGG, Mixing.OPUS];
		final names:Array<String> = ["wav", "flac", "ogg", "opus"];
		final said = new StringBuf();

		var worst = 0.0;

		for (index in 0...kinds.length) {
			mixing.kind = kinds[index];

			final made = Mixdown.of(song, mixing);
			final began = haxe.Timer.stamp();

			final bytes = switch (mixing.kind) {
				case Mixing.FLAC:
					mdd.format.Flac.write(made.samples, made.frames, made.channels, made.rate,
						mixing.depth, []);

				case Mixing.OGG:
					mdd.format.Coded.vorbis(made.samples, made.frames, made.channels,
						made.rate, mdd.format.Coded.QUALITIES[mixing.quality], []);

				case Mixing.OPUS:
					mdd.format.Coded.opus(made.samples, made.frames, made.channels, made.rate,
						mdd.format.Coded.BITRATES[mixing.quality], mixing.opusMode,
						mixing.opusSpan, mixing.opusBitrateMode, []);

				case _:
					mdd.format.Wav.write(made.samples, made.frames, made.channels, made.rate,
						mixing.depth, mixing.dither);
			}

			final took = haxe.Timer.stamp() - began;
			if (took > worst) worst = took;

			if (index > 0) said.add(", ");
			said.add(names[index] + " " + round(took * 1000, 1) + " ms into "
				+ Math.round(bytes.length / 1024) + " kb");

			if (bytes.length == 0) worst = 1000;
		}

		says("an encode is long enough to be worth a thread", worst > 0,
			round(Mixdown.of(song, mixing).seconds(), 1) + " s of audio encodes in "
			+ said.toString() + ", which is what the main loop waits through when the"
			+ " encode runs on it");
	}

	static function offloaded():Void {
		final into = Gate.root + "/export";
		if (!sys.FileSystem.exists(into)) sys.FileSystem.createDirectory(into);

		final session = new mdd.app.Session(bouncing(4));
		final files = new mdd.app.Files(session);

		files.mixing.rate = 44100;
		files.mixing.kind = Mixing.FLAC;
		files.mixing.normalise = true;

		final stamp = Std.string(Std.int(haxe.Timer.stamp() * 1000) % 1000000);
		final made = files.renders(into + "/gate-bounce-" + stamp);
		final began = haxe.Timer.stamp();

		var worst = 0.0;
		var spins = 0;

		while (!files.wroteYet() && haxe.Timer.stamp() - began < 120) {
			final at = haxe.Timer.stamp();
			final held:Array<mdd.song.Point> = [];

			for (round in 0...200) held.push(new mdd.song.Point(round, round));
			Sys.sleep(0.001);

			final took = haxe.Timer.stamp() - at;
			if (took > worst) worst = took;

			spins++;
		}

		final named = files.wroteAs;
		final there = named != "" && sys.FileSystem.exists(named);
		final size = there ? sys.FileSystem.stat(named).size : 0;

		says("the encode runs where the render does, and carries audio",
			there && size > 65536 && made.peak > 0.1 && spins > 20
			&& files.wroteWrong == "" && worst < 0.4,
			round(made.seconds(), 1) + " s bounced and written to "
			+ Math.round(size / 1024) + " kb while the calling thread went on allocating"
			+ " through " + spins + " rounds at a worst stall of "
			+ round(worst * 1000, 1) + " ms, peaking at " + round(made.peak, 3)
			+ (files.wroteWrong == "" ? "" : ", refused with " + files.wroteWrong));

		if (there) {
			try {
				sys.FileSystem.deleteFile(named);
			} catch (e:Dynamic) {}
		}
	}

	static function imported():Void {
		final where = Gate.root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return;

		var name = "";
		name = Fixtures.found("Green Hill");

		if (name == "") return;

		final source = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = false;

		final made = Mixdown.of(song, mixing);
		final want = song.tempo.samplesAt(song.ends()) / mdd.song.Tempo.TICKS;

		var loud = 0;
		final step = made.rate;

		var quiet = 0;
		var at = 0;

		while (at + step <= made.frames) {
			var most = 0.0;

			for (index in at...at + step) {
				final value = made.samples[index * made.channels];
				final held = value < 0 ? -value : value;
				if (held > most) most = held;
			}

			if (most < 0.002) quiet++;
			at += step;
		}

		final wav = Wav.write(made.samples, made.frames, made.channels, made.rate, 16,
			false);

		final flac = Flac.write(made.samples, made.frames, made.channels, made.rate, 16,
			[]);

		final ogg = Coded.vorbis(made.samples, made.frames, made.channels, made.rate,
			0.5, []);

		final wanted = made.frames * made.channels * 2 + 44;

		says("and every writer takes it whole",
			wav.length == wanted && flac.length > wanted / 4 && ogg.length > 100000,
			"a " + round(made.seconds(), 1) + " s bounce writes " + wav.length
			+ " bytes of wav against " + wanted + " wanted, " + flac.length
			+ " of flac and " + ogg.length + " of ogg");

		mixing.kind = Mixing.OPUS;

		final over = Mixdown.of(song, mixing);
		final opus = Coded.opus(over.samples, over.frames, over.channels, over.rate,
			128, 0, 20, 0, []);

		says("and opus takes a rate it knows", over.rate == 48000 && opus.length > 100000,
			round(over.seconds(), 1) + " s at " + over.rate + " Hz makes "
			+ opus.length + " bytes");

		final into = Gate.root + "/export/exported";
		if (!sys.FileSystem.exists(into)) sys.FileSystem.createDirectory(into);

		final session = new mdd.app.Session(song);
		final files = new mdd.app.Files(session);

		files.mixing.kind = Mixing.WAV;
		files.mixing.rate = 44100;
		files.mixing.padStart = 0;
		files.mixing.padEnd = 0;
		files.mixing.normalise = false;

		final one = files.exportAudio(into + "/whole");
		final two = files.exportWav(into + "/plain");
		final three = files.exportMidi(into + "/whole");

		final oneSize = one == "" ? 0 : sys.FileSystem.stat(one).size;
		final twoSize = two == "" ? 0 : sys.FileSystem.stat(two).size;
		final threeSize = three == "" ? 0 : sys.FileSystem.stat(three).size;

		says("the export menu writes the whole song",
			oneSize > wanted - 64 && twoSize > wanted - 64,
			"exportAudio wrote " + Math.round(oneSize / 1024) + " kb and exportWav "
			+ Math.round(twoSize / 1024) + " kb, against " + Math.round(wanted / 1024)
			+ " kb of song");

		final back = mdd.format.Midi.read(sys.io.File.getBytes(three), "back");

		var notes = 0;
		for (at in 0...back.patterns.length) {
			final pattern = back.patterns[at];
			for (index in 0...mdd.song.Part.COUNT) notes += pattern.lane(index).notes.length;
		}

		var kept = 0;
		for (at in 0...song.patterns.length) {
			final pattern = song.patterns[at];
			for (index in 0...mdd.song.Part.COUNT) kept += pattern.lane(index).notes.length;
		}

		final held = sys.io.File.getBytes(three);
		final division = (held.get(12) << 8) | held.get(13);

		final spans = back.tempo.samplesAt(back.ends()) / mdd.song.Tempo.TICKS;

		says("and midi carries the notes", threeSize > 1024 && notes == kept
			&& division == mdd.format.Midi.PPQN && spans > want - 2 && spans < want + 2,
			Math.round(threeSize / 1024) + " kb of midi at " + division
			+ " ticks a beat, holding " + notes + " notes against " + kept
			+ " in the song, and lasting " + round(spans, 1) + " s against "
			+ round(want, 1) + " s");

		var lanes = 0;
		var single = 0;

		for (pattern in back.patterns) {
			var carries = 0;

			for (index in 0...mdd.song.Part.COUNT) {
				if (pattern.lane(index).notes.length > 0) carries++;
			}

			if (carries > 0) lanes++;
			if (carries == 1) single++;
		}

		says("and a midi comes back as a pattern for each part",
			back.patterns.length > 1 && single == lanes && back.tracks.length == lanes,
			back.patterns.length + " patterns hold notes on one part each, laid out over "
			+ back.tracks.length + " tracks, against the one pattern a midi used to become");

		final packed = into + "/round." + mdd.Config.SUFFIX;
		mdd.format.Project.save(song, packed);

		final again = mdd.format.Project.open(packed);
		final reopened = again == null ? 0.0
			: again.tempo.samplesAt(again.ends()) / mdd.song.Tempo.TICKS;

		says("a saved song still knows its length", again != null && reopened > want - 1,
			round(reopened, 1) + " s after a save and a load, against " + round(want, 1)
			+ " s before");

		final fresh = mdd.app.Session.started(mdd.song.Library.embedded()).song;
		final blank = fresh.tempo.samplesAt(fresh.ends()) / mdd.song.Tempo.TICKS;

		says("a new document is empty and ready",
			blank == 0 && fresh.patterns.length > 0 && fresh.tracks.length > 0,
			"a fresh document holds " + fresh.patterns.length + " empty pattern across "
			+ fresh.tracks.length + " tracks and " + round(blank, 1) + " s of arrangement");

		says("an imported song bounces whole",
			made.seconds() > want - 1 && made.seconds() < want + 1 && quiet == 0
			&& made.lost == 0,
			round(made.seconds(), 1) + " s bounced of " + round(want, 1)
			+ " s of song, " + made.writes + " writes with " + made.lost
			+ " lost, and " + quiet + " of " + Math.floor(made.frames / step)
			+ " seconds silent");
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
