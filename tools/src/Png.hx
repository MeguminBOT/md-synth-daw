import haxe.io.Bytes;
import haxe.io.BytesOutput;

/**
	Writes a PNG. It is the smallest writer that produces a valid file, because the
	only thing it writes is an icon that is about to be read back by the build.
**/
class Png {
	/**
		Writes square pixels as a PNG.

		@param rgba The pixels, four bytes each.
		@param size How wide and tall the image is.
		@return The file.
	**/
	public static function write(rgba:Bytes, size:Int):Bytes {
		final out = new BytesOutput();
		out.bigEndian = true;

		out.writeByte(0x89);
		out.writeString("PNG");
		out.writeByte(13);
		out.writeByte(10);
		out.writeByte(26);
		out.writeByte(10);

		final head = new BytesOutput();
		head.bigEndian = true;

		head.writeInt32(size);
		head.writeInt32(size);
		head.writeByte(8);
		head.writeByte(6);
		head.writeByte(0);
		head.writeByte(0);
		head.writeByte(0);

		chunk(out, "IHDR", head.getBytes());

		final raw = Bytes.alloc(size * (size * 4 + 1));
		var at = 0;

		for (row in 0...size) {
			raw.set(at, 0);
			at++;

			raw.blit(at, rgba, row * size * 4, size * 4);
			at += size * 4;
		}

		chunk(out, "IDAT", haxe.zip.Compress.run(raw, 9));
		chunk(out, "IEND", Bytes.alloc(0));

		return out.getBytes();
	}

	static function chunk(out:BytesOutput, name:String, body:Bytes):Void {
		out.writeInt32(body.length);

		final held = new BytesOutput();
		held.writeString(name);
		held.write(body);

		final all = held.getBytes();

		out.write(all);
		out.writeInt32(haxe.crypto.Crc32.make(all));
	}
}
