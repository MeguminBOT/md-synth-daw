package mdd.app;

import mdd.host.Paths;
import sys.FileSystem;

@:unreflective

/**
	The banks that ship beside the application rather than inside it, written into a reader's
	presets folder the first time the application sees them there.

	Once written, a bank is the reader's own: it can be renamed, changed or deleted like anything
	else in the folder, and a bank the reader deleted stays deleted, because what was written is
	remembered. A newer build shipping a bank that changed writes it again only over a copy the
	reader left exactly as it was written, so nothing a reader did is undone.

	What was written is kept as one line, which names the presets folder it was written into,
	so choosing another folder has the banks written into that one as well.
**/
final class ShippedBanks {
	/**
		Writes every shipped bank into the presets folder where it has not been written before, and
		a newer one over a copy nobody changed.

		@param from The folder the banks ship in, beside the application, laid out by family.
		@param into The presets folder.
		@param record What was written before, as this returned it last time, or an empty string.
		@return What has been written now, to keep for next time.
	**/
	public static function plants(from:String, into:String, record:String):String {
		final names:Array<String> = [];
		final hashes:Array<String> = [];

		read(record, into, names, hashes);

		if (!FileSystem.exists(from) || !FileSystem.isDirectory(from)) return spelt(into, names, hashes);

		for (family in FileSystem.readDirectory(from)) {
			final folder = from + "/" + family;
			if (!FileSystem.isDirectory(folder)) continue;

			for (name in FileSystem.readDirectory(folder)) {
				final shipped = folder + "/" + name;
				if (FileSystem.isDirectory(shipped)) continue;

				final relative = family + "/" + name;
				final target = into + "/" + relative;
				final fresh = hashOf(shipped);
				final at = names.indexOf(relative);

				if (fresh == "") continue;

				if (at < 0) {
					if (!FileSystem.exists(target)) copied(shipped, target);

					names.push(relative);
					hashes.push(fresh);
					continue;
				}

				if (hashes[at] == fresh) continue;

				if (FileSystem.exists(target) && hashOf(target) == hashes[at]) copied(shipped, target);
				hashes[at] = fresh;
			}
		}

		return spelt(into, names, hashes);
	}

	/**
		@param record What `plants` returned.
		@param into The presets folder.
		@return Every file in it that was written from a shipped bank, whether or not it is still
			there, which is what the browser lists as shipped rather than as the reader's own.
	**/
	public static function planted(record:String, into:String):Array<String> {
		final names:Array<String> = [];
		read(record, into, names, []);

		final out:Array<String> = [];
		for (name in names) out.push(into + "/" + name);

		return out;
	}

	/**
		Takes back what `plants` returned, where it is about this presets folder.

		@param record What `plants` returned.
		@param into The presets folder it should be about.
		@param names Where the files it names go.
		@param hashes Where the hash each was written with goes, by the same index.
	**/
	static function read(record:String, into:String, names:Array<String>, hashes:Array<String>):Void {
		final parts = record.split(";");
		if (parts.length < 2 || StringTools.urlDecode(parts[0]) != into) return;

		for (entry in parts[1].split(",")) {
			final bar = entry.indexOf("|");
			if (bar <= 0) continue;

			names.push(StringTools.urlDecode(entry.substr(0, bar)));
			hashes.push(entry.substr(bar + 1));
		}
	}

	static function spelt(into:String, names:Array<String>, hashes:Array<String>):String {
		final out:Array<String> = [];
		for (at in 0...names.length) out.push(StringTools.urlEncode(names[at]) + "|" + hashes[at]);

		return StringTools.urlEncode(into) + ";" + out.join(",");
	}

	/**
		@param path A file.
		@return The MD5 of what it holds, or an empty string where it will not read.
	**/
	static function hashOf(path:String):String {
		try {
			return haxe.crypto.Md5.make(sys.io.File.getBytes(path)).toHex();
		} catch (e:Dynamic) {
			return "";
		}
	}

	static function copied(from:String, to:String):Void {
		try {
			Paths.make(haxe.io.Path.directory(to));
			sys.io.File.saveBytes(to, sys.io.File.getBytes(from));
		} catch (e:Dynamic) {}
	}
}
