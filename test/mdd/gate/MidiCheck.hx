package mdd.gate;

import mdd.app.Keyboard;

@:unreflective
class MidiCheck {
	static var ran = 0;
	static var failed = 0;

	static var lastNote = -1;
	static var lastVelocity = -1;
	static var lastRelease = -1;
	static var lastBend = 0.0;
	static var lastWheel = 0.0;

	public static function run(args:Array<String>):Int {
		ran = 0;
		failed = 0;

		Sys.println("  midi");

		hosted();
		decoded();
		filtered();
		shifted();
		bent();
		aimed();
		guarded();
		surveyed();
		chosen();
		crossed();
		signed();
		overlong();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    " + failed + " FAILED");

		return failed == 0 ? 0 : 1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 38) + said + (ok ? "" : "   FAILED"));
	}

	static function hosted():Void {
		final many = mdd.host.Midi.count();

		final named:Array<String> = [];
		for (index in 0...many) named.push(Std.string(mdd.host.Midi.named(index)));

		says("the host counts its input devices", many >= 0,
			many == 0 ? "no midi input on this machine, which the application has to survive"
				: many + " listed: " + named.join(", "));

		final opened = mdd.host.Midi.open(many);

		says("opening a device that is not there fails", !opened && !mdd.host.Midi.holding(),
			"index " + many + " of " + many + " refused, and nothing is held open");

		mdd.host.Midi.close();

		says("an empty queue says so", mdd.host.Midi.take() == mdd.host.Midi.EMPTY
			&& mdd.host.Midi.lost() == 0,
			"nothing to take and nothing dropped");
	}

	static function held():Keyboard {
		final out = new Keyboard();

		lastNote = -1;
		lastVelocity = -1;
		lastRelease = -1;
		lastBend = 0;
		lastWheel = 0;

		out.onNote = function(pitch:Int, velocity:Int):Void {
			lastNote = pitch;
			lastVelocity = velocity;
		};

		out.onRelease = function(pitch:Int):Void lastRelease = pitch;
		out.onBend = function(value:Float):Void lastBend = value;
		out.onWheel = function(value:Float):Void lastWheel = value;

		return out;
	}

	static inline function packed(status:Int, one:Int, two:Int):Int {
		return status | (one << 8) | (two << 16);
	}

	static function decoded():Void {
		final keys = held();

		keys.takes(packed(Keyboard.NOTE_ON, 60, 100));
		final on = lastNote == 60 && lastVelocity == 100;

		keys.takes(packed(Keyboard.NOTE_OFF, 60, 0));
		final off = lastRelease == 60;

		lastRelease = -1;
		keys.takes(packed(Keyboard.NOTE_ON, 64, 0));

		says("a note on and a note off arrive", on && off && lastRelease == 64,
			"note 60 at velocity 100, released, and a note on at velocity 0 released 64");

		final keeps = held();
		keeps.takes(packed(Keyboard.CONTROL, Keyboard.WHEEL, 127));
		final wheel = lastWheel;

		keeps.takes(packed(Keyboard.CONTROL, Keyboard.SUSTAIN, 127));
		final down = keeps.pedal;

		keeps.takes(packed(Keyboard.CONTROL, Keyboard.SUSTAIN, 0));

		says("the wheel and the pedal are read", wheel == 1.0 && down && !keeps.pedal,
			"the wheel at its top is " + wheel + ", and the pedal goes down and up");
	}

	static function aimed():Void {
		final mapping = new mdd.app.Mapping();
		final patch = new mdd.song.Patch();

		mapping.drives(0, mdd.app.Mapping.OPERATOR, 0, 1);
		mapping.hears(0, 74);

		final keys = held();
		var seen = 0;

		keys.onControl = function(control:Int, value:Int):Void {
			final slot = mapping.slotFor(control);
			if (slot == mdd.app.Mapping.NONE) return;

			mapping.turns(patch, slot, value);
			seen++;
		};

		keys.takes(packed(Keyboard.CONTROL, 74, 127));
		final full = patch.attack[0];

		keys.takes(packed(Keyboard.CONTROL, 74, 0));
		final none = patch.attack[0];

		keys.takes(packed(Keyboard.CONTROL, 30, 127));

		says("a control message reaches the field it is aimed at",
			seen == 2 && full == 31 && none == 0,
			"control 74 at its top and bottom set an attack rate of " + full + " and "
			+ none + ", and an unmapped control changed nothing across " + seen
			+ " that were aimed");
	}

	static function filtered():Void {
		final keys = held();
		keys.channel = 3;

		keys.takes(packed(Keyboard.NOTE_ON | 5, 60, 100));
		final other = lastNote;

		keys.takes(packed(Keyboard.NOTE_ON | 3, 62, 90));

		says("a channel filter drops the other channels", other == -1 && lastNote == 62,
			"channel 5 ignored while listening to 3, and channel 3 played note 62");
	}

	static function shifted():Void {
		final keys = held();

		keys.transpose = 12;
		keys.forces = true;
		keys.forced = 64;

		keys.takes(packed(Keyboard.NOTE_ON, 48, 1));

		says("transpose and a forced velocity apply", lastNote == 60 && lastVelocity == 64,
			"note 48 shifted an octave to 60, and a velocity of 1 forced to 64");
	}

	static function bent():Void {
		final keys = held();

		keys.takes(packed(Keyboard.BEND, 0, 0));
		final down = lastBend;

		keys.takes(packed(Keyboard.BEND, 0, 64));
		final middle = lastBend;

		keys.takes(packed(Keyboard.BEND, 127, 127));
		final up = lastBend;

		says("the bend wheel spans its range", down == -1.0 && middle == 0.0 && up > 0.99,
			"the ends read " + down + " and " + round(up) + ", and the centre reads " + middle);
	}

	static function guarded():Void {
		final keys = held();

		final data = keys.takes(packed(0x40, 60, 100));
		final clock = keys.takes(packed(0xF8, 0, 0));

		keys.transpose = 72;
		final away = keys.takes(packed(Keyboard.NOTE_ON, 120, 100));

		says("what is not a channel message is refused", !data && !clock && lastNote == -1,
			"a data byte, a clock and a note shifted past 127 all left the keyboard alone"
			+ (away ? "" : ""));

		final counted = new Keyboard();
		counted.takes(packed(Keyboard.NOTE_ON, 60, 100));

		says("the last message is spelled out", counted.said == "note on 60 at 100",
			"the monitor reads '" + counted.said + "'");
	}

	/**
		Builds a type one file with three named tracks on three channels, one of them the
		drum channel, and two of them sounding the same pitch.

		@param ppqn How many ticks a quarter note is.
		@return The file.
	**/
	static function fileOf(ppqn:Int):haxe.io.Bytes {
		final out = new haxe.io.BytesOutput();
		out.bigEndian = true;

		out.writeString("MThd");
		out.writeInt32(6);
		out.writeUInt16(1);
		out.writeUInt16(3);
		out.writeUInt16(ppqn);

		chunked(out, "Lead", 0, [60, 62, 64], ppqn);
		chunked(out, "Bass", 1, [60, 38], ppqn);
		chunked(out, "Drums", 9, [36, 38, 42], ppqn);

		return out.getBytes();
	}

	/**
		Writes one track chunk: a name, then a note on and off for each pitch in turn.

		@param out Where it goes.
		@param called What to name the track.
		@param channel Which channel it writes on.
		@param pitches What it plays.
		@param ppqn How long each note is.
	**/
	static function chunked(out:haxe.io.BytesOutput, called:String, channel:Int,
			pitches:Array<Int>, ppqn:Int):Void {
		final body = new haxe.io.BytesOutput();
		body.bigEndian = true;

		body.writeByte(0);
		body.writeByte(0xFF);
		body.writeByte(0x03);
		body.writeByte(called.length);
		body.writeString(called);

		for (pitch in pitches) {
			body.writeByte(0);
			body.writeByte(0x90 | channel);
			body.writeByte(pitch);
			body.writeByte(100);

			body.writeByte(ppqn);
			body.writeByte(0x80 | channel);
			body.writeByte(pitch);
			body.writeByte(0);
		}

		body.writeByte(0);
		body.writeByte(0xFF);
		body.writeByte(0x2F);
		body.writeByte(0);

		final held = body.getBytes();

		out.writeString("MTrk");
		out.writeInt32(held.length);
		out.write(held);
	}

	/**
		A survey says what a file holds without importing any of it.
	**/
	static function surveyed():Void {
		final strands = mdd.format.Midi.survey(fileOf(96));

		final named = strands.length == 3 && strands[0].name == "Lead"
			&& strands[1].name == "Bass" && strands[2].name == "Drums";

		says("a survey names what a file holds", named,
			strands.length + " strands: " + shown(strands));

		final counted = strands.length == 3 && strands[0].notes == 3
			&& strands[1].notes == 2 && strands[2].notes == 3;

		says("and counts what each one plays", counted,
			counted ? "three, two and three notes"
			: "the survey read " + strands.length + " strands");

		final routed = strands.length == 3 && strands[0].part == 0
			&& strands[1].part == 1
			&& strands[2].part == mdd.song.Part.Dac.index() && strands[2].drums();

		says("and points each at the part its channel would land on", routed,
			routed ? "the first two channels to FM1 and FM2, and the drum channel to the converter"
			: "the survey read " + strands.length + " strands");
	}

	/**
		@param strands What a survey found.
		@return What they are called, for a line of output.
	**/
	static function shown(strands:Array<mdd.format.Strand>):String {
		final out:Array<String> = [];
		for (strand in strands) out.push(strand.titled());

		return out.join(", ");
	}

	/**
		Only the chosen strands are taken, each lands where it was pointed, and a file
		counted differently is scaled to the piece it joins.
	**/
	static function chosen():Void {
		final bytes = fileOf(96);
		final strands = mdd.format.Midi.survey(bytes);

		strands[0].taken = false;
		strands[1].part = mdd.song.Part.Fm5.index();

		final pattern = mdd.format.Midi.patterned(bytes, "held", strands, 96);

		var total = 0;
		for (index in 0...mdd.song.Part.COUNT) {
			total += pattern.lane(index).notes.length;
		}

		final first = pattern.lane(mdd.song.Part.Fm1).notes.length;
		final fifth = pattern.lane(mdd.song.Part.Fm5).notes.length;
		final converter = pattern.lane(mdd.song.Part.Dac).notes.length;

		says("only the strands that were taken arrive", first == 0 && total == 5,
			total + " notes in all, and the strand left behind wrote " + first);

		says("and each lands on the part it was pointed at",
			fifth == 2 && converter == 3,
			fifth + " on the fifth channel it was moved to, and " + converter
			+ " on the converter");

		final apart = mdd.format.Midi.survey(bytes);
		final scaled = mdd.format.Midi.patterned(bytes, "held", apart, 192);

		final one = pattern.lane(mdd.song.Part.Dac).notes;
		final two = scaled.lane(mdd.song.Part.Dac).notes;

		final moved = one.length == two.length && one.length > 1
			&& two[1].at == one[1].at * 2 && two[1].length == one[1].length * 2;

		says("and a file counted differently is scaled to the piece", moved,
			one.length > 1 && two.length > 1
			? "a note at " + one[1].at + " ticks lands at " + two[1].at
			+ " where the piece counts twice as finely"
			: "the converter read back " + one.length + " and " + two.length + " notes");
	}

	/**
		Two channels sounding the same pitch are two strands, and neither swallows the
		other. One table for every channel lost one of them.
	**/
	static function crossed():Void {
		final strands = mdd.format.Midi.survey(fileOf(96));

		var lowest = -1;
		var many = 0;

		for (strand in strands) {
			if (strand.channel != 1) continue;

			lowest = strand.lowest;
			many = strand.notes;
		}

		says("a pitch played on two channels is two notes",
			lowest == 38 && many == 2,
			"the second channel kept " + many + " notes, lowest " + lowest
			+ ", with the first channel sounding the same 60");
	}

	/**
		A piece's time signature is written into the file it exports and read back out of it, and a
		file with none reads as four four.
	**/
	static function signed():Void {
		final song = new mdd.song.Song("signed", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("p", 96 * 5));

		song.meter.sets(5, 4);
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 96, 60, 100));
		song.track(new mdd.song.Track("t")).add(new mdd.song.Clip(0, 0, pattern.length));

		final back = mdd.format.Midi.read(mdd.format.Midi.write(song), "signed");
		final plain = mdd.format.Midi.read(fileOf(96), "plain");

		says("a time signature survives a file", back.meter.beats == 5 && back.meter.unit == 4
			&& plain.meter.beats == 4 && plain.meter.unit == 4,
			"5/4 came back as " + back.meter.spelt() + ", and a file carrying none reads as "
			+ plain.meter.spelt());
	}

	/**
		A sysex whose length is five continuation bytes long, which overflows to a negative number
		when read, ends the track rather than walking the reader backwards through it for ever.
	**/
	static function overlong():Void {
		final out = new haxe.io.BytesOutput();
		out.bigEndian = true;

		out.writeString("MThd");
		out.writeInt32(6);
		out.writeUInt16(0);
		out.writeUInt16(1);
		out.writeUInt16(96);

		final track = new haxe.io.BytesOutput();

		for (byte in [0x00, 0x90, 60, 100, 0x60, 0x80, 60, 0, 0x00, 0xF0, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F,
				0x00, 0x90, 62, 100]) {
			track.writeByte(byte);
		}

		final body = track.getBytes();

		out.writeString("MTrk");
		out.writeInt32(body.length);
		out.write(body);

		final began = haxe.Timer.stamp();
		final song = mdd.format.Midi.read(out.getBytes(), "overlong");
		final spent = haxe.Timer.stamp() - began;

		var notes = 0;
		for (pattern in song.patterns) for (index in 0...mdd.song.Part.COUNT) notes += pattern.lanes[index].notes.length;

		says("an overlong sysex ends its track", spent < 1 && notes == 1,
			"the file read in " + round(spent * 1000) + " ms and kept the " + notes
			+ " note written before it");
	}

	static function round(value:Float):Float {
		return Math.round(value * 1000) / 1000;
	}
}
