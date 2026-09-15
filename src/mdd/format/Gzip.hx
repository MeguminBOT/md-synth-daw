package mdd.format;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.zip.InflateImpl;

@:unreflective

/**
	The gzip wrapper, taken off.

	A VGM file is usually handed out gzipped under the suffix `vgz`, and what is inside
	is byte for byte the file `Vgm` already reads. Only the wrapper is understood here:
	the deflate stream itself goes to the standard library.
**/
final class Gzip {
	static inline final FIRST = 0x1F;
	static inline final SECOND = 0x8B;

	/**
		The only compression method a gzip member is allowed to name.
	**/
	static inline final DEFLATE = 8;

	static inline final HEADER = 10;
	static inline final CHUNK = 65536;

	/**
		The most a file is allowed to turn into.

		Deflate reaches about a thousand to one on the kind of repetition a register log is
		full of, so a few megabytes on disk unpacks to gigabytes in hand, and a reader that
		takes whatever arrives is killed by the allocator long before it reads a byte. A
		register log of this size is already twenty times the longest thing anybody has
		imported, so the ceiling only ever catches a file that was built to be one.
	**/
	static inline final MOST = 256 * 1024 * 1024;

	static inline final HAS_CRC = 0x02;
	static inline final HAS_EXTRA = 0x04;
	static inline final HAS_NAME = 0x08;
	static inline final HAS_COMMENT = 0x10;

	/**
		@param bytes A file.
		@return Whether it opens as a deflated gzip member. A file that does not is left alone
			rather than refused, because the plain form of every format read here is valid too.
	**/
	public static function wraps(bytes:Bytes):Bool {
		return bytes.length > HEADER + 8 && bytes.get(0) == FIRST && bytes.get(1) == SECOND
			&& bytes.get(2) == DEFLATE;
	}

	/**
		Takes the wrapper off, where there is one.

		@param bytes A file, wrapped or not.
		@return What was inside, or the same bytes back untouched where nothing wrapped them.
	**/
	public static function opened(bytes:Bytes):Bytes {
		if (!wraps(bytes)) return bytes;

		final flags = bytes.get(3);
		var at = HEADER;

		if ((flags & HAS_EXTRA) != 0) {
			if (at + 2 > bytes.length) throw "not a gzip: the extra field is not there";
			at += 2 + (bytes.get(at) | (bytes.get(at + 1) << 8));
		}

		if ((flags & HAS_NAME) != 0) at = past(bytes, at);
		if ((flags & HAS_COMMENT) != 0) at = past(bytes, at);
		if ((flags & HAS_CRC) != 0) at += 2;

		if (at < HEADER || at >= bytes.length) {
			throw "not a gzip: the header runs past the end of the file";
		}

		return inflated(new BytesInput(bytes, at, bytes.length - at));
	}

	/**
		@param from The deflate stream, with no wrapper of its own left on it.
		@return What it holds.
	**/
	static function inflated(from:BytesInput):Bytes {
		final inflate = new InflateImpl(from, false, false);
		final buffer = Bytes.alloc(CHUNK);
		final out = new BytesBuffer();

		var held = 0;

		while (true) {
			final many = inflate.readBytes(buffer, 0, CHUNK);

			held += many;

			if (held > MOST) {
				throw "not a gzip worth opening: it unpacks to more than "
					+ Std.int(MOST / (1024 * 1024)) + " MB";
			}

			out.addBytes(buffer, 0, many);

			if (many < CHUNK) break;
		}

		return out.getBytes();
	}

	/**
		@param bytes The file.
		@param from Where a name or a comment starts.
		@return Where the byte after its terminator sits.
	**/
	static function past(bytes:Bytes, from:Int):Int {
		var at = from;

		while (at < bytes.length && bytes.get(at) != 0) at++;
		return at + 1;
	}
}
