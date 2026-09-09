package mdd.format;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

/**
	A tagged container: a mark, then a run of four byte tags each followed by a length
	and a body.

	It is what a project is written into when it is written as one file rather than a
	folder, and it is deliberately simple enough that a reader can skip a tag it does
	not know.
**/
class Chunks {
	/**
		The four bytes a container begins with.
	**/
	public static inline final MARK = "MDDC";

	final out:BytesOutput = new BytesOutput();

	/**
		Builds an empty container.
	**/
	public function new() {
		out.writeString(MARK);
	}

	/**
		Adds one chunk.

		@param tag Its four byte tag.
		@param body Its contents.
	**/
	public function add(tag:String, body:Bytes):Void {
		final name = StringTools.rpad(tag, " ", 4).substr(0, 4);

		out.writeString(name);
		out.writeInt32(body.length);
		out.write(body);

		if ((body.length & 1) != 0) out.writeByte(0);
	}

	/**
		@return The whole container, mark and all.
	**/
	public function bytes():Bytes {
		return out.getBytes();
	}

	/**
		Reads a container.

		@param bytes The container.
		@return Its chunks, or an empty array where the mark is wrong.
	**/
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

	/**
		@param found The chunks read out of a container.
		@param tag The tag wanted.
		@return Every chunk carrying it, in order.
	**/
	public static function of(found:Array<Chunk>, tag:String):Array<Chunk> {
		final want = StringTools.rpad(tag, " ", 4).substr(0, 4);
		return [for (chunk in found) if (chunk.tag == want) chunk];
	}
}

/**
	One chunk: its four byte tag and its contents.
**/
typedef Chunk = {
	final tag:String;
	final body:Bytes;
}
