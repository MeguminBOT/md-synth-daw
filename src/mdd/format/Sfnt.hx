package mdd.format;

import haxe.io.Bytes;

/**
	Reads what a font file calls itself: the family and the style its `name` table gives, out of a
	TrueType or OpenType file or the first face of a collection.

	Only the header, the table directory and the `name` table are read, so a folder of hundreds of
	fonts is named without reading hundreds of whole files. The typographic names are preferred
	over the legacy ones where both are there, and the Windows names in English over the rest.
	Anything short, truncated or pointing past its own end answers with nothing rather than
	reading further.
**/
@:unreflective
final class Sfnt {
	/**
		The most bytes the `name` table is read to. Real tables are a few kilobytes.
	**/
	static inline final LONGEST = 1 << 20;

	/**
		@param path A font file.
		@return What it calls itself, its family and its style unless the style is regular, or an
			empty string where it will not read.
	**/
	public static function named(path:String):String {
		final input = try sys.io.File.read(path, true) catch (e:Dynamic) null;
		if (input == null) return "";

		final said = try spelt(input) catch (e:Dynamic) "";

		input.close();
		return said;
	}

	static function spelt(input:sys.io.FileInput):String {
		var base = 0;
		var head = bytesAt(input, 0, 12);
		if (head == null) return "";

		if (head.getString(0, 4) == "ttcf") {
			final offsets = bytesAt(input, 12, 4);
			if (offsets == null) return "";

			base = unsigned(offsets, 0, 4);
			head = bytesAt(input, base, 12);
			if (head == null) return "";
		}

		final tables = unsigned(head, 4, 2);
		if (tables <= 0 || tables > 512) return "";

		final directory = bytesAt(input, base + 12, tables * 16);
		if (directory == null) return "";

		for (index in 0...tables) {
			final at = index * 16;
			if (directory.getString(at, 4) != "name") continue;

			final offset = unsigned(directory, at + 8, 4);
			final length = unsigned(directory, at + 12, 4);

			if (length < 6 || length > LONGEST) return "";

			final table = bytesAt(input, offset, length);
			return table == null ? "" : fromTable(table);
		}

		return "";
	}

	/**
		@param table The `name` table.
		@return The family and style it names.
	**/
	static function fromTable(table:Bytes):String {
		final count = unsigned(table, 2, 2);
		final strings = unsigned(table, 4, 2);

		var family = "";
		var familyRank = 0;
		var style = "";
		var styleRank = 0;

		for (index in 0...count) {
			final at = 6 + index * 12;
			if (at + 12 > table.length) break;

			final platform = unsigned(table, at, 2);
			final encoding = unsigned(table, at + 2, 2);
			final language = unsigned(table, at + 4, 2);
			final which = unsigned(table, at + 6, 2);
			final length = unsigned(table, at + 8, 2);
			final offset = strings + unsigned(table, at + 10, 2);

			if (offset + length > table.length) continue;

			final wide = platform == 3 && (encoding == 1 || encoding == 10);
			final roman = platform == 1 && encoding == 0;
			if (!wide && !roman) continue;

			final rank = (which == 16 || which == 17 ? 4 : 0) + (wide ? 2 : 0)
				+ (language == 0x409 || (roman && language == 0) ? 1 : 0);

			if ((which == 1 || which == 16) && rank > familyRank) {
				family = wide ? utf16(table, offset, length) : table.getString(offset, length);
				familyRank = rank;
			}

			if ((which == 2 || which == 17) && rank > styleRank) {
				style = wide ? utf16(table, offset, length) : table.getString(offset, length);
				styleRank = rank;
			}
		}

		family = StringTools.trim(family);
		style = StringTools.trim(style);

		if (family == "") return "";
		return style == "" || style.toLowerCase() == "regular" ? family : family + " " + style;
	}

	/**
		@return A string of big endian UTF-16, surrogate pairs joined.
	**/
	static function utf16(table:Bytes, offset:Int, length:Int):String {
		final out = new StringBuf();
		var at = offset;

		while (at + 1 < offset + length) {
			var code = (table.get(at) << 8) | table.get(at + 1);
			at += 2;

			if (code >= 0xD800 && code < 0xDC00 && at + 1 < offset + length) {
				final low = (table.get(at) << 8) | table.get(at + 1);

				if (low >= 0xDC00 && low < 0xE000) {
					at += 2;
					code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
				} else code = 0;
			} else if (code >= 0xD800 && code < 0xE000) code = 0;

			if (code > 0) out.addChar(code);
		}

		return out.toString();
	}

	static function bytesAt(input:sys.io.FileInput, offset:Int, length:Int):Null<Bytes> {
		if (offset < 0 || length <= 0) return null;

		input.seek(offset, sys.io.FileSeek.SeekBegin);

		final out = Bytes.alloc(length);
		final read = input.readBytes(out, 0, length);

		return read == length ? out : null;
	}

	static inline function unsigned(bytes:Bytes, at:Int, width:Int):Int {
		var out = 0;
		for (index in 0...width) out = (out << 8) | bytes.get(at + index);
		return out;
	}
}
