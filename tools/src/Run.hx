import sys.FileSystem;
import sys.io.File;

typedef Source = {
	final name:String;
	final present:String;
	final size:String;
	final about:String;
}

class Run {
	static inline final SDL_VERSION = "3.4.14";
	static inline final MINIAUDIO_COMMIT = "9634bedb5b5a2ca38c1ee7108a9358a4e233f14d";

	static final SOURCES:Array<Source> = [
		{
			name: "SDL3", present: "SDL3/include/SDL3/SDL.h", size: "12 MB",
			about: "the window and its events, called directly. A system package off Windows"
		},
		{
			name: "miniaudio", present: "miniaudio/miniaudio.h", size: "1 MB",
			about: "the audio device, called directly by native/audio.cpp"
		},
		{
			name: "stb", present: "stb/stb_truetype.h", size: "1 MB",
			about: "the glyph rasteriser the font atlas is baked with"
		}
	];

	static final TARGETS:Array<String> = ["mdd", "gate"];

	public static function main():Void {
		final args = Sys.args();
		final root = rootOf();

		if (args.length == 0) {
			usage();
			return;
		}

		switch (args[0]) {
			case "setup": setup(root);
			case "check": check(root);
			case "build": build(root, args.slice(1));
			case "run": start(root, args.slice(1));
			case "gate": gate(root, args.slice(1));
			case "clean": clean(root);
			case "help", "--help", "-h": usage();
			case unknown:
				Sys.println("mdd: no command called '" + unknown + "'");
				usage();
				Sys.exit(1);
		}
	}

	static function usage():Void {
		Sys.println("");
		Sys.println("  mdd setup             fetch SDL3, miniaudio, stb and the fonts into vendor/");
		Sys.println("  mdd check             what is present and what is missing");
		Sys.println("  mdd build [target]    build a target, default mdd. -debug for a debug build");
		Sys.println("  mdd run [args]        build the application and start it");
		Sys.println("  mdd gate [name]       every check, in order, or one by name");
		Sys.println("  mdd clean             delete export/");
		Sys.println("");
		Sys.println("  targets: " + TARGETS.join(", "));
		Sys.println("");
	}

	static function rootOf():String {
		return native(Sys.getCwd());
	}

	static function native(path:String):String {
		return haxe.io.Path.removeTrailingSlashes(
			StringTools.replace(FileSystem.absolutePath(path), "\\", "/"));
	}

	static function pad(text:String):String {
		return StringTools.rpad(text, " ", 14);
	}

	static function windows():Bool {
		return Sys.systemName() == "Windows";
	}

	static function setup(root:String):Void {
		final vendor = root + "/vendor";
		if (!FileSystem.exists(vendor)) FileSystem.createDirectory(vendor);

		Sys.println("");

		for (source in SOURCES) {
			if (FileSystem.exists(vendor + "/" + source.present)) {
				Sys.println("  " + pad(source.name) + "present");
				continue;
			}

			Sys.println("  " + pad(source.name) + "fetching, " + source.size);

			final done = switch (source.name) {
				case "SDL3": sdl(vendor);
				case "miniaudio": miniaudio(vendor);
				case "stb": stb(vendor);
				case _: false;
			}

			if (!done || !FileSystem.exists(vendor + "/" + source.present)) {
				Sys.println("  " + pad("") + "failed. " + source.about);
				if (source.name == "SDL3" && !windows()) {
					Sys.println("  " + pad("") + "off Windows, install SDL3 from the system packages");
				}
			}
		}

		Sys.println("");
		check(root);
	}

	static function check(root:String):Void {
		final vendor = root + "/vendor";
		var missing = 0;

		Sys.println("");
		Sys.println("  vendor");

		for (source in SOURCES) {
			final here = FileSystem.exists(vendor + "/" + source.present);
			if (!here) missing++;
			Sys.println("    " + (here ? "[x] " : "[ ] ") + pad(source.name) + source.about);
		}

		Sys.println("");
		Sys.println("  toolchain");

		final haxe = tool("haxe", ["--version"]);
		final curl = tool("curl", ["--version"]);
		Sys.println("    " + (haxe ? "[x] " : "[ ] ") + pad("haxe") + "4.3 or newer");
		Sys.println("    " + (curl ? "[x] " : "[ ] ") + pad("curl") + "what setup fetches with");

		Sys.println("");
		Sys.println("  built");

		for (target in TARGETS) {
			final exe = exeOf(root, target);
			Sys.println("    " + (exe != "" ? "[x] " : "[ ] ") + pad(target)
				+ (exe != "" ? exe.substr(root.length + 1) : "not built"));
		}

		Sys.println("");
		if (missing > 0) Sys.println("  " + missing + " missing. Run: mdd setup");
		Sys.println("");
	}

	static function tool(name:String, args:Array<String>):Bool {
		try {
			final run = new sys.io.Process(name, args);
			final code = run.exitCode();
			run.close();
			return code == 0;
		} catch (e:Dynamic) {
			return false;
		}
	}

	static function build(root:String, args:Array<String>):Void {
		final extra = new Array<String>();
		var target = "mdd";
		var debug = false;

		for (arg in args) {
			if (arg == "-debug" || arg == "--debug") debug = true;
			else if (StringTools.startsWith(arg, "-")) extra.push(arg);
			else target = arg;
		}

		if (TARGETS.indexOf(target) < 0) {
			Sys.println("mdd: nothing here builds '" + target + "'. Targets: " + TARGETS.join(", "));
			Sys.exit(1);
		}

		built(root, target, debug, extra);
		ship(root, target);
	}

	static function built(root:String, target:String, debug:Bool, extra:Array<String>):Void {
		final vendor = root + "/vendor";

		if (windows() && !FileSystem.exists(vendor + "/SDL3/lib/SDL3.lib")) {
			Sys.println("mdd: SDL3 is missing from vendor/. Run: mdd setup");
			Sys.exit(1);
		}

		final flags = [
			"-D", "SDL3PATH=" + native(vendor + "/SDL3"),
			"-D", "MINIAUDIOPATH=" + native(vendor + "/miniaudio"),
			"-D", "STBPATH=" + native(vendor + "/stb"),
			"-D", "NATIVEPATH=" + native(root + "/native")
		].concat(extra);

		if (debug) flags.push("-debug");

		Sys.println("  " + pad(target) + "building");

		release(target);

		final here = Sys.getCwd();
		Sys.setCwd(root);
		final code = Sys.command("haxe", [target + ".hxml"].concat(flags));
		Sys.setCwd(here);

		if (code != 0) Sys.exit(code);
	}

	static function release(target:String):Void {
		if (!windows()) return;
		try {
			final killer = new sys.io.Process("taskkill", ["/F", "/IM", target + ".exe"]);
			killer.exitCode();
			killer.close();
		} catch (e:Dynamic) {}
	}

	static function objOf(root:String, target:String):String {
		return root + "/export/obj/" + (target == "mdd" ? "app" : target);
	}

	static function stemOf(target:String):String {
		return target == "mdd" ? "App" : "Gate";
	}

	static function exeOf(root:String, target:String):String {
		final dir = objOf(root, target);
		final stem = stemOf(target);

		for (name in [dir + "/" + stem + ".exe", dir + "/" + stem]) {
			if (FileSystem.exists(name)) return name;
		}
		return "";
	}

	static function ship(root:String, target:String):String {
		final exe = exeOf(root, target);
		if (exe == "") return "";

		final into = root + "/export/bin";
		tree(into);

		final suffix = StringTools.endsWith(exe, ".exe") ? ".exe" : "";
		final shipped = into + "/" + target + suffix;

		copyFile(exe, shipped);

		final dll = root + "/vendor/SDL3/lib/SDL3.dll";
		if (windows() && FileSystem.exists(dll)) copyFile(dll, into + "/SDL3.dll");

		Sys.println("  " + pad(target) + shipped.substr(root.length + 1));
		return shipped;
	}

	static function start(root:String, args:Array<String>):Void {
		final extra = new Array<String>();
		final passed = new Array<String>();
		var debug = false;

		for (arg in args) {
			if (arg == "-debug" || arg == "--debug") debug = true;
			else if (StringTools.startsWith(arg, "-D")) extra.push(arg);
			else passed.push(arg);
		}

		built(root, "mdd", debug, extra);
		final shipped = ship(root, "mdd");
		if (shipped == "") {
			Sys.println("mdd: built, but no executable came out");
			Sys.exit(1);
		}

		Sys.println("");
		Sys.exit(Sys.command(shipped, passed));
	}

	static function gate(root:String, args:Array<String>):Void {
		final exe = exeOf(root, "gate");
		if (exe == "") {
			built(root, "gate", false, []);
		}

		final shipped = ship(root, "gate");
		if (shipped == "") {
			Sys.println("mdd: the gate is not built");
			Sys.exit(1);
		}

		Sys.exit(Sys.command(shipped, args.concat(["--root", root])));
	}

	static function clean(root:String):Void {
		for (target in TARGETS) release(target);

		final out = root + "/export";
		if (FileSystem.exists(out)) remove(out);
		Sys.println("  " + pad("clean") + "export/ is gone");
	}

	static function sdl(vendor:String):Bool {
		if (!windows()) return FileSystem.exists("/usr/include/SDL3/SDL.h")
			|| FileSystem.exists("/usr/local/include/SDL3/SDL.h");

		final base = "https://github.com/libsdl-org/SDL/releases/download/release-" + SDL_VERSION;
		final archive = vendor + "/.sdl3.zip";
		final staging = vendor + "/.sdl3";

		if (!download(base + "/SDL3-devel-" + SDL_VERSION + "-VC.zip", archive)) return false;

		if (FileSystem.exists(staging)) remove(staging);
		FileSystem.createDirectory(staging);
		unpack(archive, staging);

		final unpacked = staging + "/SDL3-" + SDL_VERSION;
		if (!FileSystem.exists(unpacked)) {
			remove(staging);
			return false;
		}

		tree(vendor + "/SDL3/lib");
		copyTree(unpacked + "/include", vendor + "/SDL3/include");
		copyFile(unpacked + "/lib/x64/SDL3.dll", vendor + "/SDL3/lib/SDL3.dll");
		copyFile(unpacked + "/lib/x64/SDL3.lib", vendor + "/SDL3/lib/SDL3.lib");
		copyFile(unpacked + "/LICENSE.txt", vendor + "/SDL3/LICENSE.txt");

		FileSystem.deleteFile(archive);
		remove(staging);
		return true;
	}

	static function miniaudio(vendor:String):Bool {
		final base = "https://raw.githubusercontent.com/mackron/miniaudio/" + MINIAUDIO_COMMIT;
		tree(vendor + "/miniaudio");

		return download(base + "/miniaudio.h", vendor + "/miniaudio/miniaudio.h")
			&& download(base + "/LICENSE", vendor + "/miniaudio/LICENSE");
	}

	static function stb(vendor:String):Bool {
		final into = vendor + "/stb";
		tree(into);

		final sha = resolved("nothings", "stb", "master");
		final base = "https://raw.githubusercontent.com/nothings/stb/"
			+ (sha == "" ? "master" : sha);

		if (!download(base + "/stb_truetype.h", into + "/stb_truetype.h")) return false;
		download(base + "/LICENSE", into + "/LICENSE");

		final header = File.getContent(into + "/stb_truetype.h");
		if (header.indexOf("stbtt_PackFontRange") < 0) {
			FileSystem.deleteFile(into + "/stb_truetype.h");
			return false;
		}

		File.saveContent(into + "/COMMIT", sha == "" ? "master, unpinned" : sha);
		return true;
	}

	static function resolved(owner:String, repository:String, branch:String):String {
		try {
			final run = new sys.io.Process("curl", [
				"-sL", "--fail",
				"https://api.github.com/repos/" + owner + "/" + repository + "/commits/" + branch
			]);
			final said = run.stdout.readAll().toString();
			final code = run.exitCode();
			run.close();
			if (code != 0) return "";

			final at = said.indexOf("\"sha\"");
			if (at < 0) return "";

			final open = said.indexOf("\"", said.indexOf(":", at)) + 1;
			final shut = said.indexOf("\"", open);
			if (open <= 0 || shut <= open) return "";

			return said.substring(open, shut);
		} catch (e:Dynamic) {
			return "";
		}
	}

	static function download(url:String, into:String):Bool {
		return Sys.command("curl", ["-sL", "--fail", "-o", into, url]) == 0;
	}

	static function unpack(archive:String, into:String):Void {
		final ways = [
			{ tool: "tar", flags: ["-xf", archive, "-C", into] },
			{ tool: "unzip", flags: ["-o", "-q", archive, "-d", into] }
		];

		for (way in ways) {
			try {
				final run = new sys.io.Process(way.tool, way.flags);
				final code = run.exitCode();
				run.close();
				if (code == 0) return;
			} catch (e:Dynamic) {}
		}
	}

	static function tree(path:String):Void {
		if (FileSystem.exists(path)) return;

		final parent = haxe.io.Path.directory(path);
		if (parent != "" && parent != path && !FileSystem.exists(parent)) tree(parent);
		FileSystem.createDirectory(path);
	}

	static function copyTree(from:String, to:String):Void {
		tree(to);

		for (entry in FileSystem.readDirectory(from)) {
			final source = from + "/" + entry;
			final target = to + "/" + entry;

			if (FileSystem.isDirectory(source)) copyTree(source, target);
			else copyFile(source, target);
		}
	}

	static function copyFile(from:String, to:String):Void {
		var attempt = 0;

		while (attempt < 5) {
			try {
				File.copy(from, to);
				return;
			} catch (e:Dynamic) {
				attempt++;
				Sys.sleep(0.2 * attempt);
			}
		}

		final code = windows()
			? Sys.command("cmd", ["/c", "copy", "/y",
				StringTools.replace(from, "/", "\\"), StringTools.replace(to, "/", "\\")])
			: Sys.command("cp", ["-f", from, to]);

		if (code != 0) throw "mdd: could not copy " + from;
	}

	static function remove(path:String):Void {
		if (!FileSystem.exists(path)) return;

		if (!FileSystem.isDirectory(path)) {
			FileSystem.deleteFile(path);
			return;
		}

		for (entry in FileSystem.readDirectory(path)) remove(path + "/" + entry);
		FileSystem.deleteDirectory(path);
	}
}
