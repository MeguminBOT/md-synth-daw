package mdd.gate;

import mdd.song.Automation;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Point;
import mdd.song.Song;

@:unreflective
class AutomationCheck {
	static inline final SPAN = 384;
	static inline final LOW = 10;
	static inline final HIGH = 90;

	static final NAMES:Array<String> = ["hold", "linear", "curve", "smooth", "stairs",
		"smooth stairs", "pulse", "wave", "half sine"];

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  automation");

		ends();
		middles();
		bent();
		repeated();
		played();
		clipped();
		sliced();
		resumed();
		covered();
		quieted();
		faded();
		carried();
		oscillated();
		driven();
		named();
		switched();
		kept();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		A preset lane switches the patch the next key on loads, from its first point on, even for
		a note that names an instrument of its own, which loading a preset into a part gives
		every note the part has. The rack plays before the first point.
	**/
	static function switched():Void {
		final song = new Song("switch", 96, 120);
		final first = wired(song, "first", 2, 1);
		final second = wired(song, "second", 5, 6);

		song.rack[Part.Fm1.index()] = first;

		final pattern = song.add(new Pattern("pattern 1", SPAN * 3));
		final lane = pattern.lane(Part.Fm1);

		lane.add(new mdd.song.Note(0, 48, 60, 100));
		lane.add(new mdd.song.Note(SPAN, 48, 62, 100, first));
		lane.add(new mdd.song.Note(SPAN * 2, 48, 64, 100));

		final line = new Automation(Automation.INSTRUMENT, 0);
		line.add(new Point(SPAN, second));
		line.add(new Point(SPAN * 2, first));
		lane.automation.push(line);

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, pattern.length));

		final span = song.tempo.samplesAt(pattern.length);
		final stream = new mdd.play.Stream(1 << 16);
		final sequencer = new mdd.play.Sequencer(song);
		final strikes:Array<Int> = [];

		sequencer.strikes = strikes;
		sequencer.spanned(stream, 0, span);

		final rack = (1 << 3) | 2;
		final preset = (6 << 3) | 5;
		final wanted = [rack, KEYED, preset, KEYED, rack, KEYED].join(" ");

		final played = patched(stream);

		says("a preset lane switches the patch", played.join(" ") == wanted,
			spoken(played) + ", which is the rack before the first point, the preset over a"
			+ " note naming the rack's own and the preset the next point holds, each written"
			+ " before the key on it belongs to. " + switching(stream)
			+ " register writes land on the tick of the switch, against the "
			+ mdd.play.Driver.PER_FRAME + " a driver has in a frame");

		final vgm = new mdd.play.Stream(1 << 16);
		mdd.format.Vgm.read(mdd.format.Vgm.write(stream, 0, span, song.tempo.rate), vgm);

		final logged = patched(vgm);

		says("and a VGM of it reads back the same", logged.join(" ") == wanted,
			spoken(logged) + " out of the file's own bytes");

		final xgm = new mdd.play.Stream(1 << 16);
		mdd.format.Xgm.read(mdd.format.Xgm.write(song, stream, strikes, 0, span,
			song.tempo.rate).written, xgm);

		final driven = patched(xgm);

		says("and so does an XGM", driven.join(" ") == wanted,
			spoken(driven) + " out of the file's own bytes, frame by frame");
	}

	/**
		Marks a key on among the values `patched` returns.
	**/
	static inline final KEYED = -1;

	/**
		@param stream A sequenced or read back stream.
		@return Every `$B0` value written to the first FM channel, with `KEYED` wherever that
			channel is keyed on, in the order the writes happen.
	**/
	static function patched(stream:mdd.play.Stream):Array<Int> {
		final out:Array<Int> = [];
		var address = -1;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

			final port = stream.portAt(index);

			if (port == 0) {
				address = stream.valueAt(index);
				continue;
			}

			if (port != 1) continue;

			final value = stream.valueAt(index);

			if (address == 0xB0) out.push(value);
			else if (address == 0x28 && (value & 7) == 0 && (value & 0xF0) != 0) out.push(KEYED);
		}

		return out;
	}

	/**
		@param held What `patched` returned.
		@return It written out, with each key on named.
	**/
	static function spoken(held:Array<Int>):String {
		final out:Array<String> = [];
		for (value in held) out.push(value == KEYED ? "key on" : "$B0 " + value);

		return out.join(", ");
	}

	/**
		@param stream A sequenced stream.
		@return How many register writes happen on the tick of the first FM channel's second
			key on, which is where the preset switch lands.
	**/
	static function switching(stream:mdd.play.Stream):Int {
		final keys:Array<Int> = [];
		var address = -1;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

			final port = stream.portAt(index);

			if (port == 0) address = stream.valueAt(index);
			else if (port == 1 && address == 0x28 && stream.valueAt(index) == 0xF0) {
				keys.push(stream.tickAt(index));
			}
		}

		if (keys.length < 2) return 0;

		var many = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;
			if ((stream.portAt(index) & 1) != 0) continue;
			if (stream.tickAt(index) == keys[1]) many++;
		}

		return many;
	}

	/**
		Adds an FM instrument that differs from the others only in its wiring.

		@param song The song to add it to.
		@param name What to call it.
		@param algorithm Its algorithm.
		@param feedback Its feedback.
		@return Its index.
	**/
	static function wired(song:Song, name:String, algorithm:Int, feedback:Int):Int {
		final made = new mdd.song.Instrument(name, Part.Fm1);
		final patch = new mdd.song.Patch();

		patch.algorithm = algorithm;
		patch.feedback = feedback;
		made.patch = patch;

		song.instrument(made);
		return song.instruments.length - 1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}

	static function line(shape:Int, tension:Int = 0, steps:Int = 0):Automation {
		final held = new Automation(Automation.LEVEL, 0);
		final from = new Point(0, LOW);

		from.shape = shape;
		from.tension = tension;
		from.steps = steps;

		held.add(from);
		held.add(new Point(SPAN, HIGH));

		return held;
	}

	static function ends():Void {
		final said = new StringBuf();
		var right = 0;

		for (shape in 0...Automation.SHAPES) {
			final held = line(shape);
			final head = held.valueAt(0);
			final tail = held.valueAt(SPAN);

			if (head == LOW && tail == HIGH) right++;
			else said.add(NAMES[shape] + " " + head + ".." + tail + "  ");
		}

		says("every shape starts and ends where it is put", right == Automation.SHAPES,
			right + " of " + Automation.SHAPES + " shapes hold " + LOW + " at the first point"
			+ " and " + HIGH + " at the second"
			+ (said.toString() == "" ? "" : ", against " + said.toString()));
	}

	static function middles():Void {
		final half = Std.int(SPAN / 2);

		final held = line(Automation.HOLD).valueAt(half);
		final straight = line(Automation.LINEAR).valueAt(half);
		final smooth = line(Automation.SMOOTH).valueAt(half);
		final sine = line(Automation.HALF_SINE).valueAt(half);

		says("hold keeps its value until the next point", held == LOW,
			"a hold segment reads " + held + " half way from " + LOW + " to " + HIGH);

		says("linear is half way at half way", straight == 50,
			"a linear segment reads " + straight + " half way from " + LOW + " to " + HIGH);

		says("smooth and half sine are half way too", smooth == 50 && sine == 50,
			"smooth reads " + smooth + " and half sine " + sine
			+ ", and they differ elsewhere: at a quarter they are "
			+ line(Automation.SMOOTH).valueAt(Std.int(SPAN / 4)) + " and "
			+ line(Automation.HALF_SINE).valueAt(Std.int(SPAN / 4)));
	}

	static function bent():Void {
		final at = Std.int(SPAN / 2);

		final none = line(Automation.CURVE, 0).valueAt(at);
		final slow = line(Automation.CURVE, 100).valueAt(at);
		final fast = line(Automation.CURVE, -100).valueAt(at);

		says("tension bends a curve both ways", slow < none && fast > none,
			"half way along, tension -100 reads " + fast + ", none reads " + none
			+ " and tension 100 reads " + slow);

		var rises = true;
		var last = -1;

		for (step in 0...33) {
			final held = line(Automation.CURVE, 60).valueAt(Std.int(SPAN * step / 32));
			if (held < last) rises = false;

			last = held;
		}

		says("and a bent curve still only rises", rises,
			"33 samples of a curve at tension 60 never go back on themselves");
	}

	static function repeated():Void {
		final stairs = line(Automation.STAIRS, 0, 4);
		final levels:Array<Int> = [];

		for (step in 0...64) {
			final held = stairs.valueAt(Std.int(SPAN * step / 64));
			if (levels.indexOf(held) < 0) levels.push(held);
		}

		says("stairs takes as many levels as it is asked for", levels.length == 4,
			"a four step stairs takes " + levels.length + " levels across the segment: "
			+ levels.join(", "));

		final pulse = line(Automation.PULSE, 0, 3);
		var edges = 0;
		var was = pulse.valueAt(0);

		for (step in 1...256) {
			final held = pulse.valueAt(Std.int(SPAN * step / 256));
			if (held != was) edges++;

			was = held;
		}

		says("a pulse alternates as often as it is asked to", edges == 5,
			"a three cycle pulse changes " + edges + " times inside the segment");

		final wave = line(Automation.WAVE, 0, 2);
		final middle = Std.int((LOW + HIGH) / 2);

		var risen = 0;
		var under = wave.valueAt(0) < middle;

		for (step in 1...256) {
			final over = wave.valueAt(Std.int(SPAN * step / 256)) >= middle;

			if (over && under) risen++;
			under = !over;
		}

		says("and a wave rises once a cycle", risen == 2,
			"a two cycle wave passes the halfway value going up " + risen + " times");
	}

	static function sung(shape:Int, steps:Int):Array<Int> {
		final song = new Song("ramp", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));
		final lane = pattern.lane(Part.Psg1);

		lane.add(new mdd.song.Note(0, SPAN * 2, 60, 127));

		final held = new Automation(Automation.LEVEL, 0);
		final from = new Point(0, 0);

		from.shape = shape;
		from.steps = steps;

		held.add(from);
		held.add(new Point(SPAN, 12));
		lane.automation.push(held);

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, pattern.length));

		final stream = new mdd.play.Stream(1 << 16);
		final span = song.tempo.samplesAt(pattern.length);

		new mdd.play.Sequencer(song).spanned(stream, 0, span);

		return attenuations(stream);
	}

	static function played():Void {
		final held = sung(Automation.HOLD, 0);
		final straight = sung(Automation.LINEAR, 0);
		final stairs = sung(Automation.STAIRS, 4);

		says("a hold segment writes once and no more", held.length <= 2,
			"a held level writes the attenuation " + held.length + " times across "
			+ SPAN + " ticks");

		var rises = true;
		for (index in 1...straight.length) if (straight[index] < straight[index - 1]) rises = false;

		says("a linear segment ramps to its far value", straight.length >= 12
			&& rises && straight[straight.length - 1] == 12,
			"a linear level writes " + straight.length
			+ " attenuations, each quieter than the last, ending on "
			+ straight[straight.length - 1] + ", which is the offset the far point carries");

		says("and never writes the same value twice running", rises && every(straight),
			"no two of the " + straight.length + " writes carry the same value in a row");

		says("a stairs segment writes once a step", stairs.length >= 4
			&& stairs.length < straight.length,
			"a four step stairs writes " + stairs.length + " attenuations against "
			+ straight.length + " for the same span drawn linear");
	}

	static function every(held:Array<Int>):Bool {
		for (index in 1...held.length) if (held[index] == held[index - 1]) return false;
		return true;
	}

	static function drove(shape:Int):Array<Int> {
		final song = new Song("clip", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));

		pattern.lane(Part.Psg1).add(new mdd.song.Note(0, SPAN * 2, 60, 127));

		final notes = song.track(new mdd.song.Track("notes"));
		notes.add(new mdd.song.Clip(0, 0, pattern.length));

		final driving = song.track(new mdd.song.Track("driving"));
		final clip = mdd.song.Clip.drives(Part.Psg1, Automation.LEVEL, 0, 0, SPAN);
		final line = clip.line;

		if (line != null) {
			final from = new Point(0, 0);
			from.shape = shape;

			line.add(from);
			line.add(new Point(SPAN, 12));
		}

		driving.add(clip);

		final stream = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).spanned(stream, 0,
			song.tempo.samplesAt(pattern.length));

		return attenuations(stream);
	}

	static function clipped():Void {
		final held = drove(Automation.HOLD);
		final straight = drove(Automation.LINEAR);

		says("a clip on the playlist drives a part it does not hold",
			held.length >= 2 && held[held.length - 1] == 12,
			"an automation clip over a square on another track writes " + held.length
			+ " attenuations, ending on " + held[held.length - 1]
			+ ", which is the offset its far point carries");

		var rises = true;
		for (index in 1...straight.length) {
			if (straight[index] < straight[index - 1]) rises = false;
		}

		says("and a shape in it ramps the same way a lane does",
			straight.length > held.length && rises,
			"the same clip drawn linear writes " + straight.length
			+ " attenuations against " + held.length + " held, each quieter than the last");
	}

	/**
		@param stream What a span was sequenced into.
		@return Every attenuation written to the first square, in the order they were
			written.
	**/
	static function attenuations(stream:mdd.play.Stream):Array<Int> {
		final out:Array<Int> = [];
		var latched = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.PSG) continue;

			final value = stream.valueAt(index);
			if ((value & 0x80) == 0) continue;

			latched = (value >> 4) & 7;
			if ((latched & 1) == 0) continue;

			out.push(value & 0x0F);
		}

		return out;
	}

	/**
		A clip only writes the automation that falls inside it.

		A sliced clip reads its pattern from an offset, and what a clip collected was
		bounded by the span being sequenced rather than by the clip, so the half before
		the cut wrote the whole pattern's automation and the half after wrote it again.
		That reads as a level that jumps back at the join.
	**/
	static function sliced():Void {
		final whole = [for (value in levelled(false)) if (value < 15) value];
		final cut = [for (value in levelled(true)) if (value < 15) value];

		var back = 0;
		for (index in 1...cut.length) {
			if (cut[index] < cut[index - 1]) back++;
		}

		says("a sliced clip never writes a level it has already passed", back == 0,
			cut.length + " attenuations across the cut against " + whole.length
			 + " written whole, " + back + " of them going back on the one before");

		says("and the two halves end where the whole clip ended",
			cut.length > 0 && whole.length > 0
			&& cut[cut.length - 1] == whole[whole.length - 1],
			cut.length == 0 || whole.length == 0 ? "nothing was written"
			: "both finish at " + whole[whole.length - 1]);
	}

	/**
		One note runs under the whole lane, because a level lane only writes while a note sounds. A
		sliced clip releases the note it was playing and the next one strikes it again, which is
		what a cut means, so the silence written at each release is left out by the caller rather
		than read as automation going backwards.

		@param cut Whether the clip is sliced in two at the halfway point.
		@return Every attenuation a square is given across the piece.
	**/
	static function levelled(cut:Bool):Array<Int> {
		final song = new Song("sliced", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 4));

		final lane = pattern.lane(Part.Psg1);
		lane.add(new mdd.song.Note(0, SPAN * 4 - 24, 60, 127));

		final line = new Automation(Automation.LEVEL, 0);

		for (step in 0...5) {
			final point = new Point(step * SPAN, step * 3);

			point.shape = Automation.HOLD;
			line.add(point);
		}

		lane.automation.push(line);

		final track = song.track(new mdd.song.Track("one"));

		if (cut) {
			track.add(new mdd.song.Clip(0, 0, SPAN * 2));
			track.add(new mdd.song.Clip(0, SPAN * 2, SPAN * 2, 0, SPAN * 2));
		} else {
			track.add(new mdd.song.Clip(0, 0, pattern.length));
		}

		final stream = new mdd.play.Stream(1 << 16);

		new mdd.play.Sequencer(song).spanned(stream, 0,
			song.tempo.samplesAt(pattern.length));

		return attenuations(stream);
	}

	/**
		A clip that reads its pattern from part way through keys each note on with the stereo bits
		and the pitch offset its pattern holds where that note sits.

		A key on read both lanes at the note's distance from where its clip starts on the playlist,
		which is the same place only for a clip reading its pattern from the start. A pattern laid
		out a bar at a time played every bar after the first with the values of the first.
	**/
	static function resumed():Void {
		final whole = struck(false);
		final cut = struck(true);

		says("a cut clip keys on with its sides", cut[0] == whole[0] && whole[0] == 0x40,
			"the second bar's note sounds on $B4 = $" + StringTools.hex(cut[0], 2) + " cut and $"
			+ StringTools.hex(whole[0], 2) + " whole, where the lane holds $40 from there");

		final plain = mdd.play.Stream.wordOf(62);

		says("and with its pitch offset", cut[1] == whole[1] && whole[1] != plain,
			"frequency word $" + StringTools.hex(cut[1], 4) + " cut and $" + StringTools.hex(whole[1], 4)
			+ " whole, against $" + StringTools.hex(plain, 4) + " with no offset");
	}

	/**
		A note keys on with what the automation clips over it hold, the same as with a lane in its
		own pattern. A clip only wrote at its points, and every key on after that put the patch's
		own stereo byte and the plain pitch back, so a clip panning a channel hard right snapped
		back to the middle on the next note.
	**/
	static function covered():Void {
		final plain = under(false);
		final clipped = under(true);

		says("a key on keeps a clip's sides", clipped[0] == 0x40 && plain[0] != 0x40,
			"the second note sounds on $B4 = $" + StringTools.hex(clipped[0], 2)
			+ " under a clip holding $40, against $" + StringTools.hex(plain[0], 2) + " with none");

		says("and with its pitch offset", clipped[1] == plain[1] + 40,
			"frequency word $" + StringTools.hex(clipped[1], 4) + " under a clip holding 40, against $"
			+ StringTools.hex(plain[1], 4) + " with none");

		says("and a seek into it lands there", clipped[2] == 0x40,
			"a seek half way into the second note writes $B4 = $" + StringTools.hex(clipped[2], 2));
	}

	/**
		@param clipped Whether a clip on a track of its own holds FM1's sides and pitch offset.
		@return The stereo byte and the frequency word FM1 holds at its second key on, and the
			stereo byte a seek into the second note writes.
	**/
	static function under(clipped:Bool):Array<Int> {
		final song = new Song("covered", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));
		final lane = pattern.lane(Part.Fm1);

		lane.add(new mdd.song.Note(0, SPAN - 24, 62, 110));
		lane.add(new mdd.song.Note(SPAN, SPAN - 24, 62, 110));

		song.track(new mdd.song.Track("notes")).add(new mdd.song.Clip(0, 0, pattern.length));

		if (clipped) {
			final sides = mdd.song.Clip.drives(Part.Fm1, Automation.SIDES, 0, 0, SPAN * 2);
			final tune = mdd.song.Clip.drives(Part.Fm1, Automation.TUNE, 0, 0, SPAN * 2);

			if (sides.line != null) sides.line.add(new Point(0, 0x40));
			if (tune.line != null) tune.line.add(new Point(0, 40));

			song.track(new mdd.song.Track("sides")).add(sides);
			song.track(new mdd.song.Track("tune")).add(tune);
		}

		final stream = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).spanned(stream, 0, song.tempo.samplesAt(pattern.length));

		final second = song.tempo.samplesAt(SPAN);
		final out:Array<Int> = [-1, -1, -1];

		var address = 0;
		var held = -1;
		var high = 0;
		var low = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if ((port & 1) == 0) {
				address = ((port >> 1) << 8) | value;
				continue;
			}

			switch (address) {
				case 0xB4: held = value;
				case 0xA4: high = value;
				case 0xA0: low = value;
				case 0x28:
					if (value == 0xF0 && stream.tickAt(index) >= second) {
						out[0] = held;
						out[1] = (high << 8) | low;
					}
				case _:
			}
		}

		final seeked = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).prime(seeked, song.tempo.samplesAt(SPAN + 96));

		address = 0;

		for (index in 0...seeked.count) {
			if (seeked.kindAt(index) != mdd.play.Stream.YM) continue;

			final port = seeked.portAt(index);
			final value = seeked.valueAt(index);

			if ((port & 1) == 0) address = ((port >> 1) << 8) | value;
			else if (address == 0xB4) out[2] = value;
		}

		return out;
	}

	/**
		A square under a clip riding its level stops following its instrument's envelope, as it
		does under a level lane in its own pattern. The envelope went on stepping underneath the
		clip and wrote over the level the clip held a frame later.
	**/
	static function quieted():Void {
		final song = new Song("quieted", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));
		final decaying = new mdd.song.Instrument("decaying", Part.Psg1);

		if (decaying.envelope != null) for (step in 0...16) decaying.envelope.steps.push(step);
		song.instrument(decaying);

		pattern.lane(Part.Psg1).add(new mdd.song.Note(0, SPAN * 2, 60, 127, song.instruments.length - 1));
		song.track(new mdd.song.Track("notes")).add(new mdd.song.Clip(0, 0, pattern.length));

		final clip = mdd.song.Clip.drives(Part.Psg1, Automation.LEVEL, 0, 0, SPAN * 2);
		if (clip.line != null) clip.line.add(new Point(48, 5));
		song.track(new mdd.song.Track("level")).add(clip);

		final stream = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).spanned(stream, 0, song.tempo.samplesAt(SPAN + (SPAN >> 1)));

		final written = attenuations(stream);
		final last = written.length == 0 ? -1 : written[written.length - 1];

		says("a level clip stops the envelope", written.length <= 2 && last == 5,
			written.length + " attenuations over a bar and a half of a sixteen step decay, ending on " + last
			+ ", where the clip holds 5");
	}

	/**
		A fade in written from a note's start starts quiet. A level point exactly on a note start was
		passed over, so the note keyed on at its full level and dropped a frame later to where the
		fade began, which is heard as a click before every fade.
	**/
	static function faded():Void {
		final song = new Song("faded", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN));
		final start = SPAN >> 4;

		song.rack[Part.Fm1.index()] = wired(song, "plain", 0, 0);

		pattern.lane(Part.Fm1).add(new mdd.song.Note(start, SPAN - start - 24, 60, 127));
		pattern.lane(Part.Psg1).add(new mdd.song.Note(start, SPAN - start - 24, 60, 127));

		final carrier = new Automation(Automation.LEVEL, 3);
		final from = new Point(start, 26);
		from.shape = Automation.LINEAR;
		carrier.add(from);
		carrier.add(new Point(start + 192, 0));
		pattern.lane(Part.Fm1).automation.push(carrier);

		final square = new Automation(Automation.LEVEL, 0);
		final rising = new Point(start, 8);
		rising.shape = Automation.LINEAR;
		square.add(rising);
		square.add(new Point(start + 192, 0));
		pattern.lane(Part.Psg1).automation.push(square);

		song.track(new mdd.song.Track("one")).add(new mdd.song.Clip(0, 0, pattern.length));

		final stream = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).spanned(stream, 0, song.tempo.samplesAt(pattern.length));

		final keyed = song.tempo.samplesAt(start);
		final faded = song.tempo.samplesAt(start + 192);
		final base = mdd.play.Stream.levelOf(new mdd.song.Patch(), 3, 127);

		var address = 0;
		var level = -1;
		var atKey = -1;
		var louder = 0;
		var squareAtKey = -1;
		var squareLouder = 0;
		var latched = 0;
		var quiet = -1;

		for (index in 0...stream.count) {
			final tick = stream.tickAt(index);
			final value = stream.valueAt(index);

			if (stream.kindAt(index) == mdd.play.Stream.PSG) {
				if ((value & 0x80) == 0) continue;

				latched = (value >> 4) & 7;
				if (latched != 1) continue;

				final was = quiet;
				quiet = value & 0x0F;

				if (tick == keyed) squareAtKey = quiet;
				else if (tick > keyed && tick < faded && was >= 0 && quiet > was) squareLouder++;

				continue;
			}

			if ((stream.portAt(index) & 1) == 0) {
				address = value;
				continue;
			}

			if (address == 0x4C) {
				final was = level;
				level = value;
				if (tick > keyed && tick < faded && was >= 0 && level > was) louder++;
			} else if (address == 0x28 && value == 0xF0 && tick == keyed) {
				atKey = level;
			}
		}

		says("a fade in starts where it is written", atKey == base + 26 && louder == 0
			&& squareAtKey == 8 && squareLouder == 0,
			"FM1 keys on with its carrier at " + atKey + " against " + base + " full and "
			+ (base + 26) + " where the fade starts, " + louder + " steps back up; the square starts at "
			+ squareAtKey + " where the fade starts at 8, " + squareLouder + " steps back up");
	}

	/**
		The song's LFO is set as one undo step and reaches the chip while the song plays. It was
		only ever written at the start of playback or at a seek, and nothing in the editor could
		set it, so a preset's vibrato and tremolo depths did nothing in a song that had not been
		imported with the LFO already running.
	**/
	static function oscillated():Void {
		final song = new Song("oscillated", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));

		pattern.lane(Part.Fm1).add(new mdd.song.Note(0, SPAN * 2 - 24, 60, 127));
		song.track(new mdd.song.Track("one")).add(new mdd.song.Clip(0, 0, pattern.length));

		final sequencer = new mdd.play.Sequencer(song);
		final first = new mdd.play.Stream(1 << 16);
		sequencer.emit(first, 0, song.tempo.samplesAt(SPAN));

		final set = new mdd.song.edit.SetLfo(true, 3);
		set.apply(song);
		sequencer.edited = true;

		final second = new mdd.play.Stream(1 << 16);
		sequencer.emit(second, song.tempo.samplesAt(SPAN), song.tempo.samplesAt(SPAN * 2));

		final before = written(first, 0x22);
		final after = written(second, 0x22);

		set.revert(song);

		final hertz = mdd.chip.Ym2612.lfoHertz(3);

		says("the lfo is set while a song plays", before == 0 && after == 0x0B && !song.lfoOn
			&& song.lfoRate == 0 && Math.abs(hertz - 6.21) < 0.01,
			"$22 is written $" + StringTools.hex(before, 2) + " at the start and $" + StringTools.hex(after, 2)
			+ " in the span after switching it to rate 3, " + Math.round(hertz * 100) / 100
			+ " Hz as the chip runs it, and an undo leaves it off at rate " + song.lfoRate);
	}

	/**
		@param stream A register stream.
		@param wanted A register on the first half of the part.
		@return The last value written to it, or -1 for none.
	**/
	static function written(stream:mdd.play.Stream, wanted:Int):Int {
		var address = -1;
		var found = -1;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if (port == 0) address = value;
			else if (port == 1 && address == wanted) found = value;
		}

		return found;
	}

	/**
		A level lane holds from one note to the next, as a total level holds on the chip. Every key
		on loaded the preset's own level and the lane was only written where its points sat, so a
		lane turned down once played every later note at full level, and a filter swept across a run
		of notes clicked bright at each one. A square's lane written in a rest sounded the square
		again with nothing playing.
	**/
	static function carried():Void {
		final song = new Song("carried", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));

		song.rack[Part.Fm1.index()] = wired(song, "plain", 0, 0);

		pattern.lane(Part.Fm1).add(new mdd.song.Note(0, SPAN - 24, 60, 127));
		pattern.lane(Part.Fm1).add(new mdd.song.Note(SPAN, SPAN - 24, 62, 127));
		pattern.lane(Part.Psg1).add(new mdd.song.Note(0, SPAN - 48, 60, 127));
		pattern.lane(Part.Psg1).add(new mdd.song.Note(SPAN, SPAN - 48, 62, 127));

		final carrier = new Automation(Automation.LEVEL, 3);
		carrier.add(new Point(0, 20));
		pattern.lane(Part.Fm1).automation.push(carrier);

		final square = new Automation(Automation.LEVEL, 0);
		square.add(new Point(0, 4));
		square.add(new Point(SPAN - 24, 6));
		pattern.lane(Part.Psg1).automation.push(square);

		song.track(new mdd.song.Track("one")).add(new mdd.song.Clip(0, 0, pattern.length));

		final stream = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).spanned(stream, 0, song.tempo.samplesAt(pattern.length));

		final second = song.tempo.samplesAt(SPAN);
		final rest = song.tempo.samplesAt(SPAN - 48);
		final base = mdd.play.Stream.levelOf(new mdd.song.Patch(), 3, 127);

		var address = 0;
		var level = -1;
		var atKey = -1;
		var quiet = 15;
		var squareAtKey = -1;
		var sounded = 0;

		for (index in 0...stream.count) {
			final tick = stream.tickAt(index);
			final value = stream.valueAt(index);

			if (stream.kindAt(index) == mdd.play.Stream.PSG) {
				if ((value & 0x80) == 0 || ((value >> 4) & 7) != 1) continue;

				quiet = value & 0x0F;
				if (tick >= rest && tick < second && quiet < 15) sounded++;
				if (tick == second) squareAtKey = quiet;

				continue;
			}

			if ((stream.portAt(index) & 1) == 0) {
				address = value;
				continue;
			}

			if (address == 0x4C) level = value;
			else if (address == 0x28 && value == 0xF0 && tick == second) atKey = level;
		}

		final seeked = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).prime(seeked, song.tempo.samplesAt(SPAN + 96));

		address = 0;
		var primed = -1;

		for (index in 0...seeked.count) {
			if (seeked.kindAt(index) != mdd.play.Stream.YM) continue;

			final value = seeked.valueAt(index);

			if ((seeked.portAt(index) & 1) == 0) address = value;
			else if (address == 0x4C) primed = value;
		}

		says("a level lane holds across notes", atKey == base + 20 && primed == base + 20,
			"FM1's second note keys on with its carrier at " + atKey + " and a seek into it writes "
			+ primed + ", where the lane holds 20 under the preset's " + base + " from its only point,"
			+ " before the first note");

		says("and a square's holds without a rest", squareAtKey == 6 && sounded == 0,
			"the second square note starts at " + squareAtKey + ", where a point in the rest before it"
			+ " holds 6, and " + sounded + " writes sound the square in that rest");
	}

	/**
		@param cut Whether the clip reads only the pattern's second bar, from where that bar sits.
		@return The stereo byte and the frequency word FM1 holds at the last key on.
	**/
	static function struck(cut:Bool):Array<Int> {
		final song = new Song("resumed", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 2));
		final lane = pattern.lane(Part.Fm1);

		lane.add(new mdd.song.Note(0, SPAN - 24, 60, 110));
		lane.add(new mdd.song.Note(SPAN, SPAN - 24, 62, 110));

		final sides = new Automation(Automation.SIDES, 0);
		sides.add(new Point(0, 0x80));
		sides.add(new Point(SPAN, 0x40));
		lane.automation.push(sides);

		final tune = new Automation(Automation.TUNE, 0);
		tune.add(new Point(0, 0));
		tune.add(new Point(SPAN, 40));
		lane.automation.push(tune);

		final track = song.track(new mdd.song.Track("one"));

		if (cut) track.add(new mdd.song.Clip(0, SPAN, SPAN, 0, SPAN));
		else track.add(new mdd.song.Clip(0, 0, pattern.length));

		final stream = new mdd.play.Stream(1 << 16);
		new mdd.play.Sequencer(song).spanned(stream, 0, song.tempo.samplesAt(pattern.length));

		final from = song.tempo.samplesAt(SPAN);
		final out = [-1, -1];

		var address = 0;
		var held = -1;
		var high = 0;
		var low = 0;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if ((port & 1) == 0) {
				address = ((port >> 1) << 8) | value;
				continue;
			}

			switch (address) {
				case 0xB4: held = value;
				case 0xA4: high = value;
				case 0xA0: low = value;
				case 0x28:
					if (value == 0xF0 && stream.tickAt(index) >= from) {
						out[0] = held;
						out[1] = (high << 8) | low;
					}
				case _:
			}
		}

		return out;
	}

	static function busy(driving:Bool, ceiling:Int = 0):mdd.play.Stream {
		final song = new Song("busy", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN * 4));

		song.driving = driving;

		for (index in 0...6) {
			final part:Part = index;
			final lane = pattern.lane(part);

			var at = 0;

			while (at < SPAN * 4) {
				lane.add(new mdd.song.Note(at, 6, 60 + (at % 12), 100));
				at += 6;
			}

			for (slot in 0...4) {
				final line = new Automation(Automation.LEVEL, slot);
				final from = new Point(0, 0);

				from.shape = Automation.WAVE;
				from.steps = 200;

				line.add(from);
				line.add(new Point(SPAN * 4, 60));
				lane.automation.push(line);
			}
		}

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, pattern.length));

		final stream = new mdd.play.Stream(1 << 20);
		final sequencer = new mdd.play.Sequencer(song);

		if (ceiling > 0) sequencer.driver.perFrame = ceiling;

		sequencer.spanned(stream, 0, song.tempo.samplesAt(pattern.length));

		lastDriver = sequencer.driver;
		return stream;
	}

	static var lastDriver:Null<mdd.play.Driver> = null;

	static function busiest(stream:mdd.play.Stream):Int {
		final frame = Std.int(mdd.song.Tempo.TICKS / 60);

		var most = 0;
		var at = 0;
		var index = 0;
		var which = 0;

		while (index < stream.count) {
			var many = 0;

			while (index < stream.count && stream.tickAt(index) < at + frame) {
				if ((stream.portAt(index) & 1) != 0
					|| stream.kindAt(index) == mdd.play.Stream.PSG) many++;

				index++;
			}

			if (many > most && which > 0) most = many;

			at += frame;
			which++;
		}

		return most;
	}

	static inline final TIGHT = 24;

	static function driven():Void {
		final loose = busy(false);
		final held = busy(true);

		final quiet = lastDriver;
		final wasSpilled = quiet == null ? -1 : quiet.spilled;
		final wasLost = quiet == null ? -1 : quiet.lost;

		final tight = busy(true, TIGHT);
		final pressed = lastDriver;

		final was = busiest(loose);
		final kept = busiest(held);
		final now = busiest(tight);

		says("the driver is inert until a frame is too busy",
			held.count == loose.count && kept == was && wasSpilled == 0 && wasLost == 0,
			"a song with a note every six ticks on all six fm channels and a wave over"
			+ " every operator writes " + loose.count + " registers, busiest frame " + was
			+ ", and the driver at its own ceiling of " + mdd.play.Driver.PER_FRAME
			+ " moves " + wasSpilled + " of them and loses " + wasLost);

		says("and holds a frame to its ceiling when one is",
			now <= TIGHT && was > TIGHT && ordered(tight),
			"the same song against a ceiling of " + TIGHT + " writes at most " + now
			+ " in a frame where it wanted " + was + ", counting past the opening frame a"
			+ " driver has to itself, and still in the order the chip has to see them in");

		final where = Gate.root + "/vendor/vgm";

		if (sys.FileSystem.isDirectory(where)) {
			var name = "";
			name = Fixtures.found("Green Hill");

			if (name != "") {
				final source = new mdd.play.Stream(1 << 22);
				final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name),
					source);

				final song = mdd.format.Transcription.of(source, vgm.rate, name).song;
				final span = mdd.song.Tempo.TICKS * 30;

				final off = new mdd.play.Stream(1 << 22);
				new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK * 2)
					.spanned(off, 0, span);

				song.driving = true;

				final led = new mdd.play.Stream(1 << 22);
				final one = new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK * 2);
				one.spanned(led, 0, span);

				says("and a real file is unchanged by it",
					off.count == led.count && one.driver.spilled == 0
					&& one.driver.lost == 0,
					"thirty seconds of " + name + " writes " + off.count
					+ " registers without the driver and " + led.count + " with it, "
					+ one.driver.spilled + " of them late and " + one.driver.lost
					+ " lost, because a real driver made the file in the first place");
			}
		}

		says("and says what a driver could not keep up with",
			pressed != null && pressed.spilled > 0 && pressed.lost > 0,
			"at a ceiling a quarter of what the song asks for, "
			+ (pressed == null ? 0 : pressed.spilled) + " writes arrive late and "
			+ (pressed == null ? 0 : pressed.lost)
			+ " never arrive, which is counted rather than passed over quietly");
	}

	static function ordered(stream:mdd.play.Stream):Bool {
		for (index in 1...stream.count) {
			if (stream.tickAt(index) < stream.tickAt(index - 1)) return false;
		}

		return true;
	}

	static function named():Void {
		var many = 0;
		var packed = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final held = mdd.view.Parameter.of(part);

			many += held.length;

			for (one in held) {
				if (one.smooth || one.target == Automation.INSTRUMENT) continue;
				packed++;
			}
		}

		final fm = mdd.view.Parameter.of(Part.Fm1).length;
		final square = mdd.view.Parameter.of(Part.Psg1).length;
		final noise = mdd.view.Parameter.of(Part.Noise).length;
		final sampled = mdd.view.Parameter.of(Part.Dac).length;

		var lanes = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;

			for (one in mdd.view.Parameter.of(part)) {
				if (!one.smooth) continue;
				lanes += one.operators ? 4 : 1;
			}
		}

		says("and only so many of them can ramp at once",
			lanes < mdd.play.Driver.PER_FRAME,
			lanes + " lanes across the whole machine can carry a shape, so continuous"
			+ " automation costs at most " + lanes + " register writes a frame, against the "
			+ mdd.play.Driver.PER_FRAME + " a driver has");

		says("every part says what can be automated on it",
			fm == 11 && square == 3 && noise == 3 && sampled == 1 && packed == 44,
			many + " parameters over the eleven parts: " + fm + " on an fm channel, "
			+ square + " on a square, " + noise + " on the noise and " + sampled
			+ " on the converter. " + packed + " of them are registers carrying more than"
			+ " one setting, where a ramp would run one field into another, so they step");

		final where = Gate.root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return;

		var name = "";
		name = Fixtures.found("Green Hill");

		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
		final song = mdd.format.Transcription.of(stream, vgm.rate, name).song;

		var lines = 0;
		var known = 0;
		final missing = new StringBuf();

		for (pattern in song.patterns) {
			for (index in 0...Part.COUNT) {
				final part:Part = index;

				for (line in pattern.lane(part).automation) {
					lines++;

					if (mdd.view.Parameter.found(part, line.target, line.slot) != null) {
						known++;
						continue;
					}

					missing.add(part.name() + " target " + line.target + "  ");
				}
			}
		}

		lifted();

		says("and covers everything an import writes", lines > 0 && known == lines,
			known + " of " + lines + " automation lines an imported file makes have a"
			+ " parameter that names them"
			+ (missing.toString() == "" ? "" : ", missing " + missing.toString()));
	}

	static function lifted():Void {
		final where = Gate.root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return;

		var name = "";
		name = Fixtures.found("Green Hill");

		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
		final song = mdd.format.Transcription.of(stream, vgm.rate, name).song;

		var which = -1;
		var found:Null<Automation> = null;

		for (index in 0...song.patterns.length) {
			if (found != null) break;

			for (line in song.patterns[index].lane(Part.Fm1).automation) {
				if (line.target != Automation.LEVEL || line.points.length < 4) continue;

				which = index;
				found = line;
				break;
			}
		}

		if (found == null || which < 0) return;

		final span = mdd.song.Tempo.TICKS * 8;

		final before = new mdd.play.Stream(1 << 22);
		new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK * 2)
			.spanned(before, 0, span);

		final tracks = song.tracks.length;
		final many = found.points.length;

		final lift = new mdd.song.edit.LiftAutomation(which, Part.Fm1, found.target,
			found.slot);

		lift.apply(song);

		final after = new mdd.play.Stream(1 << 22);
		new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK * 2)
			.spanned(after, 0, span);

		says("an imported curve can move to the playlist and sound the same",
			song.tracks.length == tracks + 1 && after.count == before.count,
			"a level curve of " + many + " points moved off pattern " + which
			+ " onto a track of its own, and eight seconds writes " + after.count
			+ " registers against " + before.count + " before it moved");

		lift.revert(song);

		final back = new mdd.play.Stream(1 << 22);
		new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK * 2)
			.spanned(back, 0, span);

		says("and moving it back undoes cleanly",
			song.tracks.length == tracks && back.count == before.count,
			song.tracks.length + " tracks again and " + back.count
			+ " registers, which is where it started");
	}

	static function kept():Void {
		final song = new Song("shapes", 96, 120);
		final pattern = song.add(new Pattern("pattern 1", SPAN));
		final lane = pattern.lane(Part.Fm1);

		for (shape in 0...Automation.SHAPES) {
			final held = new Automation(Automation.LEVEL, shape);
			final from = new Point(0, LOW + shape);

			from.shape = shape;
			from.tension = shape * 10 - 40;
			from.steps = shape + 1;

			held.add(from);
			held.add(new Point(SPAN, HIGH));
			lane.automation.push(held);
		}

		final back = mdd.format.Project.read(mdd.format.Project.text(song));

		if (back == null) {
			says("a shape survives being written and read", false, "the project did not read");
			return;
		}

		final again = back.patternAt(0);
		final lines = again == null ? null : again.lane(Part.Fm1).automation;

		var right = 0;

		if (lines != null && lines.length == Automation.SHAPES) {
			for (shape in 0...Automation.SHAPES) {
				final one = lane.automation[shape].points[0];
				final two = lines[shape].points[0];

				if (one.shape != two.shape || one.tension != two.tension) continue;
				if (one.steps != two.steps || one.value != two.value) continue;

				right++;
			}
		}

		final driving = song.track(new mdd.song.Track("driving"));
		final clip = mdd.song.Clip.drives(Part.Psg1, Automation.TUNE, 0, 96, SPAN);
		final held = clip.line;

		if (held != null) {
			final from = new Point(0, -40);
			from.shape = Automation.WAVE;
			from.steps = 5;

			held.add(from);
			held.add(new Point(SPAN, 40));
		}

		driving.add(clip);

		final twice = mdd.format.Project.read(mdd.format.Project.text(song));
		var one:Null<mdd.song.Clip> = null;

		if (twice != null) {
			for (track in twice.tracks) {
				for (found in track.clips) if (found.automates()) one = found;
			}
		}

		final line = one == null ? null : one.line;

		says("and so does a clip that drives one", line != null
			&& one.kind == mdd.song.Clip.AUTOMATION && one.part == Part.Psg1.index()
			&& one.at == 96 && line.target == Automation.TUNE
			&& line.points.length == 2 && line.points[0].shape == Automation.WAVE
			&& line.points[0].steps == 5 && line.points[0].value == -40,
			line == null ? "the clip did not come back"
			: "the clip comes back on " + (one.part:Part).name() + " at " + one.at
			+ " driving " + line.points.length + " points, the first a wave of "
			+ line.points[0].steps + " cycles holding " + line.points[0].value);

		says("a shape survives being written and read", right == Automation.SHAPES,
			right + " of " + Automation.SHAPES
			+ " points keep their shape, tension and step count through the project format");
	}
}
