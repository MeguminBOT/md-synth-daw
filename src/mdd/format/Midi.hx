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
final class Midi {
	public static inline final PPQN = 960;

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

	static function chunk(out:BytesOutput, body:Bytes):Void {
		out.writeString("MTrk");
		out.writeInt32(body.length);
		out.write(body);
	}

	static inline function wide(bytes:Bytes, at:Int):Int {
		return (bytes.get(at) << 8) | bytes.get(at + 1);
	}

	static inline function whole(bytes:Bytes, at:Int):Int {
		return (bytes.get(at) << 24) | (bytes.get(at + 1) << 16)
			| (bytes.get(at + 2) << 8) | bytes.get(at + 3);
	}

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
					final from = clip.at + note.at;
					final until = from + note.length;

					if (from >= clip.ends()) continue;

					final ends = until > clip.ends() ? clip.ends() : until;

					final one = Math.round(from * scale);
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

	public static function read(bytes:Bytes, name:String):Song {
		if (bytes.length < 14 || bytes.getString(0, 4) != "MThd") {
			throw "not a midi: the header chunk is not there";
		}

		final tracks = wide(bytes, 10);
		final division = wide(bytes, 12);
		final ppqn = (division & 0x8000) != 0 ? PPQN : division;

		final song = new Song(name, ppqn, 120);
		final pattern = song.add(new Pattern(name, ppqn * 4));

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			song.instrument(new Instrument(part.name(), part));
			song.rack[index] = index;
		}

		var at = 8 + whole(bytes, 4);
		var read = 0;
		var longest = 0;

		while (read < tracks && at + 8 <= bytes.length) {
			if (bytes.getString(at, 4) != "MTrk") break;

			final asked = whole(bytes, at + 4);
			at += 8;

			final room = bytes.length - at;
			final length = asked < 0 || asked > room ? room : asked;

			final ends = walk(bytes, at, at + length, song, pattern);
			if (ends > longest) longest = ends;

			at += length;
			read++;
		}

		pattern.length = longest + ppqn;

		if (!song.split(pattern)) {
			final track = song.track(new Track("imported"));
			track.add(new Clip(0, 0, pattern.length));
		}

		return song;
	}

	static function walk(bytes:Bytes, from:Int, to:Int, song:Song, pattern:Pattern):Int {
		var at = from;
		var tick = 0;
		var running = 0;
		var longest = 0;

		final open:Array<Int> = [];
		final since:Array<Int> = [];

		for (i in 0...128) {
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

				if (meta == 0x51 && length == 3) {
					final micros = (bytes.get(at) << 16) | (bytes.get(at + 1) << 8)
						| bytes.get(at + 2);
					if (micros > 0) song.tempo.set(tick, 60000000.0 / micros);
				}

				at += length;
				if (meta == 0x2F) break;
				continue;
			}

			if (kind == 0x80 || kind == 0x90) {
				final pitch = bytes.get(at) & 0x7F;
				final velocity = bytes.get(at + 1) & 0x7F;
				at += 2;

				final on = kind == 0x90 && velocity > 0;
				final part:Part = channel >= Part.COUNT ? Part.COUNT - 1 : channel;

				if (on) {
					open[pitch] = velocity;
					since[pitch] = tick;
					continue;
				}

				if (open[pitch] < 0) continue;

				final length = tick - since[pitch];
				open[pitch] = -1;

				if (length <= 0) continue;

				pattern.lane(part).add(new Note(since[pitch], length, pitch, 100, channel));
				if (tick > longest) longest = tick;
				continue;
			}

			at += switch (kind) {
				case 0xA0, 0xB0, 0xE0: 2;
				case 0xC0, 0xD0: 1;
				case _: status == 0xF0 || status == 0xF7 ? skip(bytes, at, to) : 0;
			}
		}

		return longest;
	}

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
