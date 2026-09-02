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
		written(into);
		bounced();

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
		final opus = Coded.opus(held, 48000, 2, 48000, 128, ["TITLE=a tone"]);

		says("an ogg is smaller than the flac", vorbis.length > 0
			&& vorbis.getString(0, 4) == "OggS" && vorbis.length < flac.length,
			vorbis.length + " bytes of vorbis at q6 against " + flac.length + " of flac");

		says("an opus is smaller still", opus.length > 0
			&& opus.getString(0, 4) == "OggS" && opus.length < flac.length,
			opus.length + " bytes of opus at 128k for a second at 48000");

		says("a flac is smaller than the wav it came from",
			flac.getString(0, 4) == "fLaC" && flac.length < one.length,
			flac.length + " bytes against " + one.length + ", "
			+ Math.round(flac.length * 100.0 / one.length) + " per cent of it");
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
			Coded.opus(fast, 48000 * 2, 2, 48000, 128,
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
			faster.rate, 128, ["TITLE=" + song.name]);

		says("a song goes out as ogg and opus", ogg.length > 512 && opus.length > 512
			&& ogg.getString(0, 4) == "OggS" && opus.getString(0, 4) == "OggS",
			"a " + round(faster.seconds(), 2) + " s mixdown is " + ogg.length
			+ " bytes of vorbis and " + opus.length + " of opus");

		says("a mixdown takes the rate it is asked for", faster.rate == 48000
			&& faster.frames > made.frames * 0,
			faster.frames + " frames at 48000 against " + mono.frames + " at 44100, "
			+ round(faster.seconds(), 2) + " s either way");
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
