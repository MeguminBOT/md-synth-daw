package mdd.host;

/**
	The fonts installed on this machine: where the system keeps them, and what each calls itself.

	Every TrueType, OpenType and collection file under the system's font folders and the user's
	own is named from its `name` table, a font named twice is listed once, and the list is sorted
	by name. Reading the names costs a few small reads a file, so it is done when it is first asked
	for rather than at start, and the caller keeps what it gets.
**/
@:unreflective
final class Installed {
	/**
		How deep into a font folder's own folders the search goes.
	**/
	static inline final DEEPEST = 4;

	/**
		The most files looked at, so a folder of tens of thousands cannot hold the interface up.
	**/
	static inline final MOST = 4000;

	/**
		What each font is called, sorted.
	**/
	public final names:Array<String> = [];

	/**
		The file each is in, by the same index.
	**/
	public final paths:Array<String> = [];

	function new() {}

	/**
		Looks through the font folders.

		@return The fonts found, which may be none.
	**/
	public static function found():Installed {
		final out = new Installed();
		final files:Array<String> = [];

		for (folder in folders()) looked(folder, 0, files);

		final named:Array<String> = [];
		final held:Array<String> = [];

		for (path in files) {
			final name = mdd.format.Sfnt.named(path);
			if (name == "" || named.indexOf(name) >= 0) continue;

			named.push(name);
			held.push(path);
		}

		final order = [for (index in 0...named.length) index];
		order.sort(function(one:Int, two:Int):Int {
			final first = named[one].toLowerCase();
			final second = named[two].toLowerCase();
			return first < second ? -1 : (first > second ? 1 : 0);
		});

		for (index in order) {
			out.names.push(named[index]);
			out.paths.push(held[index]);
		}

		return out;
	}

	/**
		@return The folders fonts are installed in on this system, whether or not each exists.
	**/
	static function folders():Array<String> {
		final home = Sys.getEnv("HOME");

		#if windows
		final windows = Sys.getEnv("WINDIR");
		final local = Sys.getEnv("LOCALAPPDATA");

		return [(windows == null ? "C:/Windows" : windows) + "/Fonts",
			(local == null ? "" : local + "/Microsoft/Windows/Fonts")];
		#elseif mac
		return ["/System/Library/Fonts", "/Library/Fonts", (home == null ? "" : home + "/Library/Fonts")];
		#elseif android
		return ["/system/fonts"];
		#else
		return ["/usr/share/fonts", "/usr/local/share/fonts",
			(home == null ? "" : home + "/.local/share/fonts"), (home == null ? "" : home + "/.fonts")];
		#end
	}

	/**
		Adds every font file in a folder and its folders to a list.

		@param folder The folder.
		@param depth How deep this folder is.
		@param into The list.
	**/
	static function looked(folder:String, depth:Int, into:Array<String>):Void {
		if (folder == "" || depth > DEEPEST || into.length >= MOST) return;

		final held = try sys.FileSystem.readDirectory(folder) catch (e:Dynamic) null;
		if (held == null) return;

		for (name in held) {
			if (into.length >= MOST) return;

			final path = folder + "/" + name;
			final lower = name.toLowerCase();

			if (StringTools.endsWith(lower, ".ttf") || StringTools.endsWith(lower, ".otf")
				|| StringTools.endsWith(lower, ".ttc")) {
				into.push(path);
				continue;
			}

			if (name.indexOf(".") < 0 && (try sys.FileSystem.isDirectory(path) catch (e:Dynamic) false)) {
				looked(path, depth + 1, into);
			}
		}
	}
}
