package mdd.gate;

import haxe.io.Bytes;
import haxe.io.BytesOutput;

@:unreflective
class Png {
	static final SIGNATURE:Array<Int> = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

	public static function write(rgba:haxe.ds.Vector<cpp.UInt8>, width:Int, height:Int):Bytes {
		final out = new BytesOutput();
		out.bigEndian = true;

		for (byte in SIGNATURE) out.writeByte(byte);

		final header = new BytesOutput();
		header.bigEndian = true;

		header.writeInt32(width);
		header.writeInt32(height);
		header.writeByte(8);
		header.writeByte(2);
		header.writeByte(0);
		header.writeByte(0);
		header.writeByte(0);

		chunk(out, "IHDR", header.getBytes());

		final raw = Bytes.alloc(height * (1 + width * 3));
		var at = 0;

		for (row in 0...height) {
			raw.set(at, 0);
			at++;

			for (column in 0...width) {
				final from = (row * width + column) * 4;

				raw.set(at, rgba[from]);
				raw.set(at + 1, rgba[from + 1]);
				raw.set(at + 2, rgba[from + 2]);
				at += 3;
			}
		}

		chunk(out, "IDAT", haxe.zip.Compress.run(raw, 6));
		chunk(out, "IEND", Bytes.alloc(0));

		return out.getBytes();
	}

	static function chunk(out:BytesOutput, tag:String, body:Bytes):Void {
		out.writeInt32(body.length);

		final held = new BytesOutput();
		held.bigEndian = true;
		held.writeString(tag);
		held.write(body);

		final all = held.getBytes();

		out.write(all);
		out.writeInt32(haxe.crypto.Crc32.make(all));
	}
}
