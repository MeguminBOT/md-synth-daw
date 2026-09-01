package mdd.format;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

class Chunks {
	public static inline final MARK = "MDDC";

	final out:BytesOutput = new BytesOutput();

	public function new() {
		out.writeString(MARK);
	}

	public function add(tag:String, body:Bytes):Void {
		final name = StringTools.rpad(tag, " ", 4).substr(0, 4);

		out.writeString(name);
		out.writeInt32(body.length);
		out.write(body);

		if ((body.length & 1) != 0) out.writeByte(0);
	}

	public function bytes():Bytes {
		return out.getBytes();
	}

	public static function read(bytes:Bytes):Array<Chunk> {
		final found:Array<Chunk> = [];

		if (bytes.length < 4 || bytes.getString(0, 4) != MARK) return found;

		final input = new BytesInput(bytes);
		input.position = 4;

		while (input.position + 8 <= bytes.length) {
			final tag = input.readString(4);
			final length = input.readInt32();

			if (length < 0 || input.position + length > bytes.length) break;

			found.push({ tag: tag, body: input.read(length) });
			if ((length & 1) != 0 && input.position < bytes.length) input.readByte();
		}

		return found;
	}

	public static function of(found:Array<Chunk>, tag:String):Array<Chunk> {
		final want = StringTools.rpad(tag, " ", 4).substr(0, 4);
		return [for (chunk in found) if (chunk.tag == want) chunk];
	}
}

typedef Chunk = {
	final tag:String;
	final body:Bytes;
}
