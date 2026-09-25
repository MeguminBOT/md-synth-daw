package mdd.gate;

import mdd.app.Session;
import mdd.play.Render;
import mdd.play.Transport;
import mdd.song.Clip;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Song;

@:unreflective

/**
	Mutes a part while it sounds, through the same transport and render the application plays
	through, and listens for it to stop.

	Each case is a new piece with notes on one part only, so everything the render gives back after
	the mute is that part. A second is let go by for the release to finish, and the two seconds after
	it have to be silent. The cases cover a held note, a held note paced by the driver, a run of
	short notes, and a part muted, unmuted and muted again, on an FM part, a square part and the
	noise part.
**/
class MuteCheck {
	static inline final RATE = 44100;

	/**
		The loudest a sample may be once a muted part has had time to release.
	**/
	static inline final QUIET = 0.002;

	/**
		The quietest the part may be before the mute, which is what says the case sounded at all.
	**/
	static inline final HEARD = 0.01;

	/**
		The note is taken away by muting the track it is on.
	**/
	static inline final TRACK = 0;

	/**
		The note is taken away by deleting it from its pattern.
	**/
	static inline final NOTE = 1;

	/**
		The note is taken away by deleting every clip that plays it.
	**/
	static inline final CLIP = 2;

	/**
		The note is taken away by soloing another track.
	**/
	static inline final SOLO = 3;

	static final HOWS:Array<String> = ["the track muted", "the note deleted", "the clips deleted",
		"another soloed"];

	static var failed:Int = 0;
	static var ran:Int = 0;

	/**
		@param args The gate's arguments, unused.
		@return Nought where every case fell silent.
	**/
	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  mute");

		for (part in [Part.Fm1, Part.Psg1, Part.Noise]) {
			listened(part, "a held note", false, false, false);
			listened(part, "a held note through the driver", true, false, false);
			listened(part, "a run of short notes", false, true, false);
			listened(part, "muted, unmuted and muted again", false, false, true);

			for (how in [TRACK, NOTE, CLIP, SOLO]) {
				removed(part, how, false);
				removed(part, how, true);
			}
		}

		overridden();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		Plays one case and says whether the part stopped.

		@param part The part the notes are on.
		@param named What the case is called.
		@param driving Whether the driver paces the stream.
		@param short Whether the notes are eighths rather than one held note a bar.
		@param twice Whether the part is muted, unmuted and muted again.
	**/
	static function listened(part:Part, named:String, driving:Bool, short:Bool, twice:Bool):Void {
		final song = written(part, short);
		song.driving = driving;

		final transport = new Transport(song, 1 << 18);
		final render = new Render(RATE, Render.BLOCK);

		render.transport = transport;
		transport.play();

		final before = poured(transport, render, 0.5);
		var back = before;

		muted(transport, song, part, true);

		if (twice) {
			poured(transport, render, 0.5);
			muted(transport, song, part, false);
			back = poured(transport, render, 1.0);
			muted(transport, song, part, true);
		}

		poured(transport, render, 1.0);
		final after = poured(transport, render, 2.0);

		says(part.name() + ", " + named, before > HEARD && back > HEARD && after < QUIET,
			"peaks at " + round(before) + (twice ? ", " + round(back) + " once unmuted" : "")
			+ " and " + round(after) + " in the two seconds after the mute settles");
	}

	/**
		Plays a held note and takes it away some other way than the mixer, the way the playlist
		and the piano roll can while the song plays, and says whether the part stopped.

		@param part The part the note is on.
		@param how `TRACK`, `NOTE` or `CLIP`.
		@param driving Whether the driver paces the stream.
	**/
	static function removed(part:Part, how:Int, driving:Bool):Void {
		final song = written(part, false);
		song.driving = driving;

		final transport = new Transport(song, 1 << 18);
		final render = new Render(RATE, Render.BLOCK);

		render.transport = transport;
		transport.play();

		final before = poured(transport, render, 0.5);

		transport.holds();

		switch (how) {
			case TRACK: song.tracks[0].muted = true;
			case SOLO: song.tracks[1].soloed = true;
			case NOTE: song.patternAt(0).lane(part).notes.resize(0);
			case _: song.tracks[0].clips.resize(0);
		}

		transport.frees();

		poured(transport, render, 1.0);
		final after = poured(transport, render, 2.0);

		says(part.name() + ", " + HOWS[how] + (driving ? " through the driver" : ""),
			before > HEARD && after < QUIET,
			"peaks at " + round(before) + " and " + round(after)
			+ " in the two seconds after it settles");
	}

	/**
		A soloed track is heard whatever its own mute says, the way a soloed part is.
	**/
	static function overridden():Void {
		final song = written(Part.Fm1, false);

		song.tracks[0].muted = true;
		song.tracks[0].soloed = true;

		final transport = new Transport(song, 1 << 18);
		final render = new Render(RATE, Render.BLOCK);

		render.transport = transport;
		transport.play();

		final loud = poured(transport, render, 0.5);

		says("a soloed track sounds through its mute", loud > HEARD,
			"peaks at " + round(loud) + " with the one track holding the note both muted and soloed");
	}

	/**
		@param part The part the notes are on.
		@param short Whether the notes are eighths rather than one held note a bar.
		@return A new piece of eight bars with notes on that part only.
	**/
	static function written(part:Part, short:Bool):Song {
		final song = Session.started(mdd.song.Library.embedded()).song;
		final pattern = song.patternAt(0);
		final bar = pattern.length;
		final pitch = part.fm() ? 60 : (part.noise() ? 60 : 72);

		if (short) {
			final step = Std.int(bar / 8);
			for (at in 0...8) pattern.lane(part).add(new Note(at * step, step - 8, pitch, 110));
		} else {
			pattern.lane(part).add(new Note(0, bar, pitch, 110));
		}

		for (at in 0...8) song.tracks[0].add(new Clip(0, at * bar, bar));

		return song;
	}

	/**
		Mutes or unmutes a part the way the mixer does, holding the lock the render thread takes.

		@param transport The transport playing the song.
		@param song The song.
		@param part Which part.
		@param quiet Whether it is muted.
	**/
	static function muted(transport:Transport, song:Song, part:Part, quiet:Bool):Void {
		transport.holds();
		song.muted[part.index()] = quiet;
		transport.frees();
	}

	/**
		Renders on and keeps the loudest sample.

		@param transport The transport playing the song.
		@param render The render it plays through.
		@param seconds How long to render for.
		@return The loudest sample, left or right.
	**/
	static function poured(transport:Transport, render:Render, seconds:Float):Float {
		final frames = Std.int(RATE * seconds);
		var done = 0;
		var most = 0.0;

		while (done < frames) {
			final at = transport.advance(Render.BLOCK, RATE);
			final many = render.serve(transport.stream, at, Render.BLOCK, transport.entering, true);
			if (many <= 0) break;

			for (i in 0...many * 2) {
				final value = render.block[i];
				final much = value < 0 ? -value : value;
				if (much > most) most = much;
			}

			done += many;
		}

		return most;
	}

	static function round(value:Float):Float {
		return Math.round(value * 10000) / 10000;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 46) + said + (ok ? "" : "   FAILED"));
	}
}
