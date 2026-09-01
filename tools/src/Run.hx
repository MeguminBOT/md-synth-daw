import sys.FileSystem;
import sys.io.File;

class Run {
	static inline final SDL_VERSION = "3.4.14";
	static inline final MINIAUDIO_COMMIT = "9634bedb5b5a2ca38c1ee7108a9358a4e233f14d";

	static final FACES:Array<String> = ["Go-Regular", "Go-Medium", "Go-Mono", "Go-Mono-Bold"];

	public static function main():Void {
		final args = Sys.args();
		final root = native(Sys.getCwd());
		final debug = args.indexOf("-debug") >= 0 || args.indexOf("--debug") >= 0;
		final project = read(root, debug);

		if (args.length == 0) {
			usage(project);
			return;
		}

		switch (args[0]) {
			case "setup": setup(root, project);
			case "check": check(root, project);
			case "build": build(root, project, args.slice(1), debug);
			case "run": start(root, project, args.slice(1), debug);
			case "gate": gate(root, project, args.slice(1));
			case "clean": clean(root, project);
			case "help", "--help", "-h": usage(project);
			case unknown:
				Sys.println("mdd: no command called '" + unknown + "'");
				usage(project);
				Sys.exit(1);
		}
	}

	static function read(root:String, debug:Bool):Project {
		final path = root + "/project.xml";

		if (!FileSystem.exists(path)) {
			Sys.println("mdd: no project.xml beside the command");
			Sys.exit(1);
		}

		try {
			return new Project(path, system(), debug);
		} catch (e:Dynamic) {
			Sys.println("mdd: project.xml would not read: " + e);
			Sys.exit(1);
			return null;
		}
	}

	static function system():String {
		return switch (Sys.systemName()) {
			case "Windows": "windows";
			case "Mac": "mac";
			case _: "linux";
		}
	}

	static inline function windows():Bool {
		return system() == "windows";
	}

	static function usage(project:Project):Void {
		Sys.println("");
		Sys.println("  mdd setup             fetch what vendor/ is missing");
		Sys.println("  mdd check             what is present and what is missing");
		Sys.println("  mdd build [target]    build a target. -debug for a debug build");
		Sys.println("  mdd run [args]        build the application and start it");
		Sys.println("  mdd gate [name]       every check, in order, or one by name");
		Sys.println("  mdd clean             delete the output directory");
		Sys.println("");
		Sys.println("  targets: " + project.names().join(", "));
		Sys.println("  every option lives in project.xml, and there is no .hxml");
		Sys.println("");
	}

	static function native(path:String):String {
		return haxe.io.Path.removeTrailingSlashes(
			StringTools.replace(FileSystem.absolutePath(path), "\\", "/"));
	}

	static function pad(text:String):String {
		return StringTools.rpad(text, " ", 14);
	}

	static function setup(root:String, project:Project):Void {
		final vendor = root + "/vendor";
		tree(vendor);

		Sys.println("");

		for (source in project.vendors) {
			if (FileSystem.exists(vendor + "/" + source.present)) {
				Sys.println("  " + pad(source.name) + "present");
				continue;
			}

			Sys.println("  " + pad(source.name) + "fetching, " + source.size);

			final done = switch (source.name) {
				case "SDL3": sdl(vendor);
				case "miniaudio": miniaudio(vendor);
				case "stb": stb(vendor);
				case "fonts": fonts(vendor);
				case _: false;
			}

			if (!done || !FileSystem.exists(vendor + "/" + source.present)) {
				Sys.println("  " + pad("") + "failed. " + source.about);
				if (source.name == "SDL3" && !windows()) {
					Sys.println("  " + pad("") + "install SDL3 from the system packages");
				}
			}
		}

		Sys.println("");
		check(root, project);
	}

	static function check(root:String, project:Project):Void {
		final vendor = root + "/vendor";
		var missing = 0;

		Sys.println("");
		Sys.println("  " + project.title + " " + project.version + ", building for " + system());
		Sys.println("");
		Sys.println("  vendor");

		for (source in project.vendors) {
			final here = FileSystem.exists(vendor + "/" + source.present);
			if (!here) missing++;
			Sys.println("    " + (here ? "[x] " : "[ ] ") + pad(source.name) + source.about);
		}

		Sys.println("");
		Sys.println("  toolchain");
		Sys.println("    " + (tool("haxe", ["--version"]) ? "[x] " : "[ ] ") + pad("haxe")
			+ "4.3 or newer");
		Sys.println("    " + (tool("curl", ["--version"]) ? "[x] " : "[ ] ") + pad("curl")
			+ "what setup fetches with");

		Sys.println("");
		Sys.println("  built");

		for (target in project.targets) {
			final exe = exeOf(root, project, target.id);
			Sys.println("    " + (exe != "" ? "[x] " : "[ ] ") + pad(target.id)
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

	static function build(root:String, project:Project, args:Array<String>, debug:Bool):Void {
		var target = project.targets[0].id;
		for (arg in args) if (!StringTools.startsWith(arg, "-")) target = arg;

		if (project.targetOf(target) == null) {
			Sys.println("mdd: nothing here builds '" + target + "'. Targets: "
				+ project.names().join(", "));
			Sys.exit(1);
		}

		built(root, project, target, debug);
		ship(root, project, target);
	}

	static function configure(root:String, project:Project):Void {
		final into = root + "/" + project.generated + "/mdd";
		tree(into);

		final out = new StringBuf();
		out.add("package mdd;\n\n");
		out.add("class Config {\n");
		out.add("\tpublic static inline final TITLE = \"" + project.title + "\";\n");
		out.add("\tpublic static inline final VERSION = \"" + project.version + "\";\n");
		out.add("\tpublic static inline final WIDTH = " + project.windowWidth + ";\n");
		out.add("\tpublic static inline final HEIGHT = " + project.windowHeight + ";\n");
		out.add("\tpublic static inline final LEAST_WIDTH = " + project.leastWidth + ";\n");
		out.add("\tpublic static inline final LEAST_HEIGHT = " + project.leastHeight + ";\n");
		out.add("\tpublic static inline final VSYNC = " + project.vsync + ";\n");
		out.add("\tpublic static inline final RESIZABLE = " + project.resizable + ";\n");
		out.add("\tpublic static inline final HIGH_DPI = " + project.highDpi + ";\n");
		out.add("}\n");

		File.saveContent(into + "/Config.hx", out.toString());
	}

	static function nativeXml(root:String, project:Project):String {
		final into = root + "/" + project.output + "/build";
		tree(into);

		final flags = new StringBuf();
		for (path in project.includes) {
			flags.add("\t\t<compilerflag value=\"-I" + native(root + "/" + path) + "\" />\n");
		}

		final out = new StringBuf();
		out.add("<xml>\n");

		for (id in ["haxe", "__main__", "mdd_native"]) {
			out.add("\t<files id=\"" + id + "\">\n");
			out.add(flags.toString());

			if (id == "mdd_native") {
				for (file in project.nativeFiles) {
					out.add("\t\t<file name=\"" + native(root + "/" + project.nativePath) + "/"
						+ file + "\" />\n");
				}
			}

			out.add("\t</files>\n");
		}

		out.add("\t<target id=\"haxe\">\n");

		for (link in project.links) {
			out.add("\t\t<lib name=\""
				+ (StringTools.startsWith(link, "-") ? link : native(root + "/" + link))
				+ "\" />\n");
		}

		out.add("\t\t<files id=\"mdd_native\" />\n");
		out.add("\t</target>\n");
		out.add("</xml>\n");

		final path = into + "/native.xml";
		File.saveContent(path, out.toString());
		return native(path);
	}

	static function built(root:String, project:Project, target:String, debug:Bool):Void {
		if (windows() && !FileSystem.exists(root + "/" + project.pathOf("SDL3PATH")
				+ "/lib/SDL3.lib")) {
			Sys.println("mdd: SDL3 is missing from vendor/. Run: mdd setup");
			Sys.exit(1);
		}

		configure(root, project);
		final xml = nativeXml(root, project);
		final one = project.targetOf(target);

		final args = ["-main", one.main, "-cpp", root + "/" + project.output + "/obj/" + target];

		for (path in project.sourcesOf(target)) {
			args.push("-cp");
			args.push(root + "/" + path);
		}

		args.push("-cp");
		args.push(root + "/" + project.generated);

		for (define in project.defines) {
			args.push("-D");
			args.push(define);
		}

		for (one in project.paths) {
			args.push("-D");
			args.push(one.name + "=" + native(root + "/" + one.value));
		}

		args.push("-D");
		args.push("MDDBUILD=" + xml);

		if (debug) args.push("-debug");

		Sys.println("  " + pad(target) + "building");
		release(target);

		final here = Sys.getCwd();
		Sys.setCwd(root);
		final code = Sys.command("haxe", args);
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

	static function exeOf(root:String, project:Project, target:String):String {
		final one = project.targetOf(target);
		if (one == null) return "";

		final dir = root + "/" + project.output + "/obj/" + target;
		final stem = one.main.split(".").pop();

		for (name in [dir + "/" + stem + ".exe", dir + "/" + stem]) {
			if (FileSystem.exists(name)) return name;
		}
		return "";
	}

	static function ship(root:String, project:Project, target:String):String {
		final exe = exeOf(root, project, target);
		if (exe == "") return "";

		final into = root + "/" + project.output + "/bin";
		tree(into);

		final suffix = StringTools.endsWith(exe, ".exe") ? ".exe" : "";
		final shipped = into + "/" + target + suffix;

		copyFile(exe, shipped);

		for (one in project.ships) {
			final from = root + "/" + one;
			if (FileSystem.exists(from)) {
				copyFile(from, into + "/" + haxe.io.Path.withoutDirectory(one));
			}
		}

		Sys.println("  " + pad(target) + shipped.substr(root.length + 1));
		return shipped;
	}

	static function start(root:String, project:Project, args:Array<String>, debug:Bool):Void {
		final passed = [for (arg in args) if (!StringTools.startsWith(arg, "-")) arg];
		final first = project.targets[0].id;

		built(root, project, first, debug);
		final shipped = ship(root, project, first);

		if (shipped == "") {
			Sys.println("mdd: built, but no executable came out");
			Sys.exit(1);
		}

		Sys.println("");
		Sys.exit(Sys.command(shipped, passed));
	}

	static function gate(root:String, project:Project, args:Array<String>):Void {
		if (exeOf(root, project, "gate") == "") built(root, project, "gate", false);

		final shipped = ship(root, project, "gate");
		if (shipped == "") {
			Sys.println("mdd: the gate is not built");
			Sys.exit(1);
		}

		Sys.exit(Sys.command(shipped, args.concat(["--root", root])));
	}

	static function clean(root:String, project:Project):Void {
		for (target in project.targets) release(target.id);

		final out = root + "/" + project.output;
		if (FileSystem.exists(out)) remove(out);
		Sys.println("  " + pad("clean") + project.output + "/ is gone");
	}

	static function sdl(vendor:String):Bool {
		if (!windows()) {
			for (where in ["/usr/include/SDL3/SDL.h", "/usr/local/include/SDL3/SDL.h",
					"/opt/homebrew/include/SDL3/SDL.h"]) {
				if (FileSystem.exists(where)) return true;
			}
			return false;
		}

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

		if (File.getContent(into + "/stb_truetype.h").indexOf("stbtt_PackFontRange") < 0) {
			FileSystem.deleteFile(into + "/stb_truetype.h");
			return false;
		}

		File.saveContent(into + "/COMMIT", sha == "" ? "master, unpinned" : sha);
		return true;
	}

	static function fonts(vendor:String):Bool {
		final into = vendor + "/fonts";
		tree(into);

		final base = "https://go.googlesource.com/image/+/master/font/gofont/ttfs/";

		for (face in FACES) {
			final coded = into + "/." + face + ".b64";
			if (!download(base + face + ".ttf?format=TEXT", coded)) return false;

			File.saveBytes(into + "/" + face + ".ttf", decode(coded));
			FileSystem.deleteFile(coded);
		}

		final licence = into + "/.LICENSE.b64";
		if (download("https://go.googlesource.com/image/+/master/LICENSE?format=TEXT", licence)) {
			File.saveBytes(into + "/LICENSE", decode(licence));
			FileSystem.deleteFile(licence);
		}

		for (face in FACES) {
			if (!FileSystem.exists(into + "/" + face + ".ttf")) return false;
		}
		return true;
	}

	static function decode(path:String):haxe.io.Bytes {
		final packed = StringTools.replace(
			StringTools.replace(File.getContent(path), "\n", ""), "\r", "");
		return haxe.crypto.Base64.decode(packed);
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
		for (way in [
			{ tool: "tar", flags: ["-xf", archive, "-C", into] },
			{ tool: "unzip", flags: ["-o", "-q", archive, "-d", into] }
		]) {
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
