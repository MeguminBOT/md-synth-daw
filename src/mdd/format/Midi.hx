package mdd.format;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import mdd.song.Clip;
import mdd.song.Instrument;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Song;
import mdd.song.Track;

@:unreflective

/**
	Standard MIDI files, read and written.

	A MIDI file carries notes and a tempo map and nothing about the chips, so a write
	is a lossy view of a song and a read produces something that has to be given
	instruments before it sounds.
**/
final class Midi {
	/**
		Ticks per quarter note in a written file.
	**/
	public static inline final PPQN = 960;

	/**
		The channel a general MIDI file puts its drums on, counted from nought.

		A note there names a drum rather than a pitch, so the channel goes to the
		converter and the converter is read as a kit: the pitch picks the sample.
	**/
	public static inline final DRUMS = 9;

	/**
		Writes a song as a type one file: a tempo track, then one track per part.

		@param song The song to write.
		@return The file.
	**/
	public static function write(song:Song):Bytes {
		final flat = song.unshared();
		final out = new BytesOutput();

		out.bigEndian = true;

		out.writeString("MThd");
		out.writeInt32(6);
		out.writeUInt16(1);
		out.writeUInt16(Part.COUNT + 1);
		out.writeUInt16(PPQN);

		final scale = song.tempo.ppqn < 1 ? 1.0 : PPQN / song.tempo.ppqn;

		chunk(out, tempoTrack(song, scale));

		for (index in 0...Part.COUNT) chunk(out, partTrack(flat, index, scale));

		return out.getBytes();
	}

	/**
		Writes one track chunk, tag and length included.

		@param out Where it goes.
		@param body The track events.
	**/
	static function chunk(out:BytesOutput, body:Bytes):Void {
		out.writeString("MTrk");
		out.writeInt32(body.length);
		out.write(body);
	}

	/**
		@param bytes The file.
		@param at A position in it.
		@return The two byte value there, most significant byte first.
	**/
	static inline function wide(bytes:Bytes, at:Int):Int {
		return (bytes.get(at) << 8) | bytes.get(at + 1);
	}

	/**
		@param bytes The file.
		@param at A position in it.
		@return The four byte value there, most significant byte first.
	**/
	static inline function whole(bytes:Bytes, at:Int):Int {
		return (bytes.get(at) << 24) | (bytes.get(at + 1) << 16)
			| (bytes.get(at + 2) << 8) | bytes.get(at + 3);
	}

	/**
		Writes the tempo track, which carries every tempo change in the map.

		@param song The song to write.
		@param scale What to multiply a tick by to reach MIDI ticks.
		@return The track.
	**/
	static function tempoTrack(song:Song, scale:Float):Bytes {
		final out = new BytesOutput();
		var last = 0;

		for (i in 0...song.tempo.at.length) {
			final at = Math.round(song.tempo.at[i] * scale);

			variable(out, at - last);
			last = at;

			final micros = Std.int(60000000 / song.tempo.bpm[i]);

			out.writeByte(0xFF);
			out.writeByte(0x51);
			out.writeByte(3);
			out.writeByte((micros >> 16) & 0xFF);
			out.writeByte((micros >> 8) & 0xFF);
			out.writeByte(micros & 0xFF);
		}

		variable(out, 0);
		out.writeByte(0xFF);
		out.writeByte(0x2F);
		out.writeByte(0);

		return out.getBytes();
	}

	/**
		Writes one part as a track, with its notes and its name.

		@param song The song to write.
		@param index Which part.
		@param scale What to multiply a tick by to reach MIDI ticks.
		@return The track, or an empty one where the part carries nothing.
	**/
	static function partTrack(song:Song, index:Int, scale:Float):Bytes {
		final part:Part = index;
		final out = new BytesOutput();

		variable(out, 0);
		out.writeByte(0xFF);
		out.writeByte(0x03);

		final name = Bytes.ofString(part.name());
		out.writeByte(name.length);
		out.write(name);

		final events:Array<Int> = [];

		for (track in song.tracks) {
			if (track.muted) continue;

			for (clip in track.clips) {
				final pattern = song.patternAt(clip.pattern);
				if (pattern == null) continue;

				for (note in pattern.lane(part).notes) {
					final from = clip.origin() + note.at;
					final until = from + note.length;

					if (from >= clip.ends() || until <= clip.at) continue;

					final ends = until > clip.ends() ? clip.ends() : until;
					final head = from < clip.at ? clip.at : from;

					final one = Math.round(head * scale);
					var two = Math.round(ends * scale);

					if (two <= one) two = one + 1;

					events.push((one << 9) | (1 << 8) | (note.pitch & 0x7F));
					events.push((two << 9) | (note.pitch & 0x7F));
				}
			}
		}

		events.sort(function(a:Int, b:Int):Int return a - b);

		final channel = index > 15 ? 15 : index;
		var last = 0;

		for (packed in events) {
			final at = packed >> 9;
			final on = (packed & 0x100) != 0;
			final pitch = packed & 0x7F;

			variable(out, at - last);
			last = at;

			out.writeByte((on ? 0x90 : 0x80) | channel);
			out.writeByte(pitch);
			out.writeByte(on ? 100 : 0);
		}

		variable(out, 0);
		out.writeByte(0xFF);
		out.writeByte(0x2F);
		out.writeByte(0);

		return out.getBytes();
	}

	/**
		Writes a value in the variable length form MIDI uses for a delta time.

		@param out Where it goes.
		@param value The value.
	**/
	static function variable(out:BytesOutput, value:Int):Void {
		var held = value < 0 ? 0 : value;
		var buffer = held & 0x7F;

		held = held >> 7;

		while (held > 0) {
			buffer = (buffer << 8) | ((held & 0x7F) | 0x80);
			held = held >> 7;
		}

		while (true) {
			out.writeByte(buffer & 0xFF);
			if ((buffer & 0x80) == 0) break;
			buffer = buffer >> 8;
		}
	}

	/**
		@param bytes The file.
		@return How many ticks it counts to a quarter note. A file counting in frames a
			second is read as the resolution this application writes, because a note
			position is what is wanted and not a wall clock.
	**/
	public static function resolution(bytes:Bytes):Int {
		if (bytes.length < 14) throw "not a midi: the header chunk is not there";

		final division = wide(bytes, 12);
		return (division & 0x8000) != 0 ? PPQN : division;
	}

	/**
		Looks through a file without importing any of it.

		This is what lets a reader be shown what a file holds and choose, rather than
		having the whole of it land and then taking the unwanted parts back out.

		@param bytes The file.
		@return One strand for every track and channel that carries a note, in the order
			the file writes them, each already pointed at the part its channel would
			land on.
	**/
	public static function survey(bytes:Bytes):Array<Strand> {
		final out:Array<Strand> = [];

		chunks(bytes, null, null, out);
		return out;
	}

	/**
		Reads a whole file into a song of its own.

		@param bytes The file.
		@param name What to call the song.
		@return The song.
	**/
	public static function read(bytes:Bytes, name:String):Song {
		return taken(bytes, name, survey(bytes));
	}

	/**
		Reads the chosen strands into a song of its own.

		@param bytes The file.
		@param name What to call the song.
		@param strands What to take, and where each one goes.
		@return The song, split into a pattern for each part where more than one is used.
	**/
	public static function taken(bytes:Bytes, name:String,
			strands:Array<Strand>):Song {
		final ppqn = resolution(bytes);
		final song = new Song(name, ppqn, 120);
		final pattern = song.add(new Pattern(name, ppqn * 4));

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			song.instrument(new Instrument(part.name(), part));
			song.rack[index] = index;
		}

		final longest = chunks(bytes, song, pattern, strands);

		pattern.length = longest + ppqn;
		song.drums = kitted(strands);

		if (!song.split(pattern)) {
			final track = song.track(new Track("imported"));
			track.add(new Clip(0, 0, pattern.length));
		}

		return song;
	}

	/**
		Reads the chosen strands into one pattern, for adding to a piece that is already
		open.

		The piece keeps its own tempo and its own resolution. A file put beside an
		arrangement is joining it, so taking the file's tempo would move everything that
		was already there, and note positions are scaled to the resolution the piece
		counts in rather than the one the file was written at.

		@param bytes The file.
		@param name What to call the pattern.
		@param strands What to take, and where each one goes.
		@param ppqn How many ticks a quarter note is in the piece this joins.
		@return The pattern.
	**/
	public static function patterned(bytes:Bytes, name:String, strands:Array<Strand>,
			ppqn:Int):Pattern {
		final was = resolution(bytes);
		final pattern = new Pattern(name, ppqn * 4);

		final longest = chunks(bytes, null, pattern, strands);

		if (was > 0 && was != ppqn) rescaled(pattern, was, ppqn);

		final ends = was > 0 && was != ppqn
			? Math.round(longest * ppqn / was) : longest;

		pattern.length = ends + ppqn;
		return pattern;
	}

	/**
		Moves every note in a pattern from one resolution to another.

		@param pattern The pattern.
		@param was How many ticks a quarter note was.
		@param ppqn How many it is now.
	**/
	static function rescaled(pattern:Pattern, was:Int, ppqn:Int):Void {
		for (index in 0...Part.COUNT) {
			for (note in pattern.lane(index).notes) {
				note.at = Math.round(note.at * ppqn / was);
				note.length = Math.round(note.length * ppqn / was);

				if (note.length < 1) note.length = 1;
			}
		}
	}

	/**
		@param strands What is being taken.
		@return Whether any of it is the drum channel, which is what says the converter
			should read a note as a drum rather than as a pitch.
	**/
	public static function kitted(strands:Array<Strand>):Bool {
		for (strand in strands) {
			if (strand.taken && strand.drums()) return true;
		}

		return false;
	}

	/**
		Walks the track chunks, either surveying them or reading them in.

		@param bytes The file.
		@param song The song to put tempo changes in, or null to leave a tempo alone.
		@param pattern The pattern notes go into, or null to survey rather than read.
		@param strands What was found, or what to take. A survey fills this in; a read
			follows it.
		@return The last tick anything reached.
	**/
	static function chunks(bytes:Bytes, song:Null<Song>, pattern:Null<Pattern>,
			strands:Array<Strand>):Int {
		if (bytes.length < 14 || bytes.getString(0, 4) != "MThd") {
			throw "not a midi: the header chunk is not there";
		}

		final tracks = wide(bytes, 10);

		var at = 8 + whole(bytes, 4);
		var read = 0;
		var longest = 0;

		while (read < tracks && at + 8 <= bytes.length) {
			if (bytes.getString(at, 4) != "MTrk") break;

			final asked = whole(bytes, at + 4);
			at += 8;

			final room = bytes.length - at;
			final length = asked < 0 || asked > room ? room : asked;

			final ends = walk(bytes, at, at + length, song, pattern, read, strands);
			if (ends > longest) longest = ends;

			at += length;
			read++;
		}

		return longest;
	}

	/**
		@param strands Every strand known.
		@param track Which track chunk.
		@param channel Which channel.
		@return The strand for that pair, or null where there is none.
	**/
	static function stranded(strands:Array<Strand>, track:Int,
			channel:Int):Null<Strand> {
		for (strand in strands) {
			if (strand.track == track && strand.channel == channel) return strand;
		}

		return null;
	}

	/**
		@param channel A MIDI channel, counted from nought.
		@return Which part it lands on where nobody says otherwise. The drum channel goes
			to the converter, and a channel past the parts this machine has lands on the
			last of them.
	**/
	public static function parted(channel:Int):Int {
		if (channel == DRUMS) return Part.Dac.index();
		return channel >= Part.COUNT ? Part.COUNT - 1 : channel;
	}

	/**
		Walks one track, turning note on and note off pairs into notes, or counting them
		where there is nothing to put them in.

		@param bytes The file.
		@param from Where the track starts.
		@param to One past its end.
		@param song The song to put tempo changes in, or null to leave a tempo alone.
		@param pattern The pattern notes go into, or null to survey rather than read.
		@param track Which track chunk this is.
		@param strands What was found, or what to take.
		@return The last tick anything reached.
	**/
	static function walk(bytes:Bytes, from:Int, to:Int, song:Null<Song>,
			pattern:Null<Pattern>, track:Int, strands:Array<Strand>):Int {
		final surveying = pattern == null;

		var at = from;
		var tick = 0;
		var running = 0;
		var longest = 0;
		var called = "";

		final open:Array<Int> = [];
		final since:Array<Int> = [];

		for (i in 0...128 * 16) {
			open.push(-1);
			since.push(0);
		}

		while (at < to) {
			var shift = 0;
			var delta = 0;

			while (at < to) {
				final byte = bytes.get(at);
				at++;

				delta = (delta << 7) | (byte & 0x7F);
				shift++;

				if ((byte & 0x80) == 0 || shift > 4) break;
			}

			tick += delta;
			if (at >= to) break;

			var status = bytes.get(at);

			if (status < 0x80) status = running;
			else at++;

			running = status;

			final kind = status & 0xF0;
			final channel = status & 0x0F;

			if (status == 0xFF) {
				final meta = bytes.get(at);
				at++;

				var length = 0;
				while (at < to) {
					final byte = bytes.get(at);
					at++;
					length = (length << 7) | (byte & 0x7F);
					if ((byte & 0x80) == 0) break;
				}

				if (meta == 0x51 && length == 3 && song != null) {
					final micros = (bytes.get(at) << 16) | (bytes.get(at + 1) << 8)
						| bytes.get(at + 2);
					if (micros > 0) song.tempo.set(tick, 60000000.0 / micros);
				}

				if (meta == 0x03 && length > 0 && at + length <= to) {
					called = named(bytes, at, length);
				}

				at += length;
				if (meta == 0x2F) break;
				continue;
			}

			if (kind == 0x80 || kind == 0x90) {
				final pitch = bytes.get(at) & 0x7F;
				final velocity = bytes.get(at + 1) & 0x7F;
				at += 2;

				final slot = channel * 128 + pitch;
				final on = kind == 0x90 && velocity > 0;

				if (on) {
					open[slot] = velocity;
					since[slot] = tick;
					continue;
				}

				if (open[slot] < 0) continue;

				final length = tick - since[slot];
				final struck = open[slot];
				open[slot] = -1;

				if (length <= 0) continue;

				var strand = stranded(strands, track, channel);

				if (strand == null) {
					if (!surveying) continue;

					strand = new Strand(track, channel);
					strand.part = parted(channel);
					strands.push(strand);
				}

				if (surveying) {
					strand.counts(pitch, tick);
					if (strand.name == "") strand.name = called;
				} else if (strand.taken) {
					final part:Part = strand.part;

					pattern.lane(part).add(new Note(since[slot], length, pitch, struck,
						strand.part));
				} else continue;

				if (tick > longest) longest = tick;
				continue;
			}

			at += switch (kind) {
				case 0xA0, 0xB0, 0xE0: 2;
				case 0xC0, 0xD0: 1;
				case _: status == 0xF0 || status == 0xF7 ? skip(bytes, at, to) : 0;
			}
		}

		if (surveying && called != "") {
			for (strand in strands) {
				if (strand.track == track && strand.name == "") strand.name = called;
			}
		}

		return longest;
	}

	/**
		@param bytes The file.
		@param at Where the text starts.
		@param length How long it is.
		@return It as text, with anything that is not printable left out, because a track
			name is written in whatever a sequencer felt like and lands in a menu.
	**/
	static function named(bytes:Bytes, at:Int, length:Int):String {
		final out = new StringBuf();

		for (index in 0...length) {
			final code = bytes.get(at + index);
			if (code >= 0x20 && code < 0x7F) out.addChar(code);
		}

		return StringTools.trim(out.toString());
	}

	/**
		Steps over an event that is not a note or a tempo.

		@param bytes The file.
		@param at Where the event starts.
		@param to One past the end of the track.
		@return Where the next event starts.
	**/
	static function skip(bytes:Bytes, at:Int, to:Int):Int {
		var pen = at;
		var length = 0;

		while (pen < to) {
			final byte = bytes.get(pen);
			pen++;
			length = (length << 7) | (byte & 0x7F);
			if ((byte & 0x80) == 0) break;
		}

		return (pen - at) + length;
	}
}
