import sys.FileSystem;
import sys.io.File;

/**
	The one command this repository is driven by: setup, check, build, run, gate,
	package, notes, display and clean.

	It reads the build file, fetches what the vendor folder is missing, generates the
	configuration, the native build file and the editor completion files, and drives
	the compiler. Nothing here is written by hand twice: every option lives in the
	build file and everything generated from it is thrown away by `clean`.
**/
class Run {
	static inline final SDL_VERSION = "3.4.14";
	static inline final MINIAUDIO_COMMIT = "9634bedb5b5a2ca38c1ee7108a9358a4e233f14d";

	static inline final OGG_VERSION = "1.3.5";
	static inline final VORBIS_VERSION = "1.3.7";
	static inline final OPUS_VERSION = "1.5.2";
	static inline final VPX_TAG = "v1.17.0";
	static inline final WEBM_TAG = "libwebm-1.0.0.32";

	static inline final PRESENCE:Int = 1024;


	/**
		Reads the arguments and runs one command. Exits nonzero on anything that failed.
	**/
	public static function main():Void {
		final args = Sys.args();
		final root = native(Sys.getCwd());
		final debug = args.indexOf("-debug") >= 0 || args.indexOf("--debug") >= 0;
		final project = read(root, debug, picked(read(root, debug, ""), args));

		if (args.length == 0) {
			usage(project);
			return;
		}

		switch (args[0]) {
			case "setup": setup(root, project, args.slice(1));
			case "check": check(root, project);
			case "presence": presence(root, project);
			case "display": display(root, project, true);
			case "build": build(root, project, args.slice(1), debug);
			case "run": start(root, project, args.slice(1), debug);
			case "gate": gate(root, project, args.slice(1));
			case "package": packaged(root, project, args.slice(1));
			case "notes": if (!Notes.write(root, project, args.slice(1))) Sys.exit(1);
			case "clean": clean(root, project);
			case "help", "--help", "-h": usage(project);
			case unknown:
				Sys.println("mdd: no command called '" + unknown + "'");
				usage(project);
				Sys.exit(1);
		}
	}

	static function overrides(root:String, project:Project):String {
		final into = root + "/" + project.output + "/build";
		tree(into);

		final out = new StringBuf();
		out.add("<xml>\n\n");

		final home = Sys.getEnv("HOME") != null ? Sys.getEnv("HOME") : Sys.getEnv("USERPROFILE");

		if (home != null && FileSystem.exists(home + "/.hxcpp_config.xml")) {
			out.add("\t<include name=\"" + native(home) + "/.hxcpp_config.xml\" noerror=\"1\" />\n\n");
		}

		out.add("\t<section id=\"vars\">\n");
		out.add("\t\t<set name=\"NO_PRECOMPILED_HEADERS\" value=\"1\" />\n");
		out.add("\t</section>\n\n");

		out.add("\t<section id=\"exes\">\n");
		out.add("\t\t<compiler id=\"MSVC\" exe=\"clang-cl.exe\" if=\"windows\">\n");
		out.add("\t\t\t<getversion value=\"clang-cl.exe -v\" />\n");
		out.add("\t\t\t<objdir value=\"obj/clang-cl${OBJEXT}${OBJCACHE}${XPOBJ}\" />\n");

		for (flag in CLANG_QUIET) {
			out.add("\t\t\t<flag value=\"" + flag + "\" />\n");
		}

		out.add("\t\t</compiler>\n");
		out.add("\t</section>\n");

		out.add("\n</xml>\n");

		final where = into + "/toolchain.xml";
		File.saveContent(where, out.toString());

		return where;
	}

	static final CLANG_QUIET:Array<String> = ["-Wno-unused-command-line-argument",
		"-Wno-invalid-offsetof", "-Wno-parentheses-equality", "-Wno-parentheses",
		"-Wno-deprecated-declarations", "-Wno-microsoft-cast", "-Wno-microsoft-include",
		"-Wno-unknown-pragmas", "-Wno-ignored-attributes", "-Wno-ignored-pragma-intrinsic",
		"-Wno-nonportable-include-path"];

	static function picked(project:Project, args:Array<String>):String {
		for (arg in args) {
			if (!StringTools.startsWith(arg, "--")) continue;

			final want = arg.substr(2);
			for (held in project.toolchains) if (held.name == want) return want;
		}

		for (held in project.toolchains) {
			if (held.probe == "" || tool(held.probe, ["--version"])) return held.name;
		}

		return "";
	}

	static function read(root:String, debug:Bool, toolchain:String):Project {
		final path = root + "/mdd.xml";

		if (!FileSystem.exists(path)) {
			Sys.println("mdd: no mdd.xml beside the command");
			Sys.exit(1);
		}

		try {
			return new Project(path, system(), debug, toolchain, machine());
		} catch (e:Dynamic) {
			Sys.println("mdd: mdd.xml would not read: " + e);
			Sys.exit(1);
			return null;
		}
	}

	static function stamp(project:Project):String {
		return project.short + "-" + project.version + "-"
			+ system() + "-" + machine();
	}

	static function machine():String {
		for (arg in Sys.args()) {
			if (arg == "--arm64") return "arm64";
			if (arg == "--x86_64") return "x86_64";
		}

		final told = Sys.getEnv("MDD_ARCH");
		if (told != null && told != "") return told;

		if (windows()) {
			final held = Sys.getEnv("PROCESSOR_ARCHITECTURE");
			final over = Sys.getEnv("PROCESSOR_ARCHITEW6432");
			final name = over != null && over != "" ? over : (held == null ? "" : held);
			return name.toUpperCase() == "ARM64" ? "arm64" : "x86_64";
		}

		try {
			final out = new sys.io.Process("uname", ["-m"]);
			final said = StringTools.trim(out.stdout.readAll().toString());
			out.close();
			return said == "aarch64" || said == "arm64" ? "arm64" : "x86_64";
		} catch (e:Dynamic) {
			return "x86_64";
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
		Sys.println("  mdd presence          draw the discord art assets from assets/presence");
		Sys.println("  mdd check             what is present and what is missing");
		Sys.println("  mdd build [target]    build a target. -debug for a debug build");
		Sys.println("  mdd run [args]        build the application and start it");
		Sys.println("  mdd run -debug        the same, carrying the hxcpp debug server on"
			+ " 6972");
		Sys.println("  mdd gate [name]       every check, in order, or one by name");
		Sys.println("  mdd package [kind]    portable, installer, or both");
		Sys.println("  mdd notes [tag]       write the release notes for a tag into export/");
		Sys.println("  mdd display           write the editor's completion files again");
		Sys.println("  mdd clean             delete the output directory");
		Sys.println("");
		Sys.println("  targets: " + project.names().join(", "));
		Sys.println("  a debugger attaches to a -debug build; vscode has the launch"
			+ " entries for it");
		Sys.println("  every option lives in mdd.xml, and there is no .hxml");
		Sys.println("");
	}

	static function loose(link:String):Bool {
		if (StringTools.startsWith(link, "-")) return true;
		return link.indexOf("/") < 0 && link.indexOf("\\") < 0;
	}

	static function rooted(path:String):Bool {
		if (StringTools.startsWith(path, "/")) return true;
		return path.length > 2 && path.charAt(1) == ":";
	}

	static function native(path:String):String {
		return haxe.io.Path.removeTrailingSlashes(
			StringTools.replace(FileSystem.absolutePath(path), "\\", "/"));
	}

	static function pad(text:String):String {
		return StringTools.rpad(text, " ", 14);
	}

	static function vendored(root:String, source:{final present:String; final system:String;}):Bool {
		if (FileSystem.exists(root + "/vendor/" + source.present)) return true;
		if (source.system == "") return false;

		for (where in source.system.split(",")) {
			if (FileSystem.exists(StringTools.trim(where))) return true;
		}

		return false;
	}

	static function asked(args:Array<String>, flag:String):Bool {
		return args.indexOf("--" + flag) >= 0;
	}

	static function setup(root:String, project:Project, args:Array<String>):Void {
		final vendor = root + "/vendor";
		tree(vendor);

		Sys.println("");

		for (source in project.vendors) {
			if (vendored(root, source)) {
				Sys.println("  " + pad(source.name) + "present");
				continue;
			}

			if (source.flag != "" && !asked(args, source.flag)) {
				Sys.println("  " + pad(source.name) + "not fetched, ask with --" + source.flag);
				continue;
			}

			Sys.println("  " + pad(source.name) + "fetching, " + source.size);

			final done = switch (source.name) {
				case "SDL3": sdl(vendor);
				case "miniaudio": miniaudio(vendor);
				case "stb": stb(vendor);
				case "fonts": fonts(root, project);
				case "Nuked-OPN2": nuked(vendor);
				case "qlementine": qlementine(vendor, project);
				case "libogg": xiph(vendor, "ogg", OGG_VERSION, "libogg");
				case "libvorbis": xiph(vendor, "vorbis", VORBIS_VERSION, "libvorbis");
				case "libopus": xiph(vendor, "opus", OPUS_VERSION, "libopus");
				case "libvpx": github(vendor, "webmproject/libvpx", VPX_TAG, "libvpx");
				case "libwebm": github(vendor, "webmproject/libwebm", WEBM_TAG, "libwebm");
				case _: false;
			}

			if (!done || !vendored(root, source)) {
				Sys.println("  " + pad("") + "failed. " + source.about);
				if (source.name == "SDL3" && !windows()) {
					Sys.println("  " + pad("") + "install SDL3 from the system packages");
				}
			}
		}

		if (FileSystem.exists(vendor + "/fonts")) pairings(root, project);

		Sys.println("");
		check(root, project);
	}

	static function presence(root:String, project:Project):Void {
		final from = root + "/assets/presence";

		if (!FileSystem.exists(from)) {
			Sys.println("mdd: nothing in assets/presence to draw");
			return;
		}

		final into = root + "/" + project.output + "/presence";
		tree(into);

		Sys.println("");

		final held = FileSystem.readDirectory(from);
		held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		for (entry in held) {
			if (!StringTools.endsWith(entry, ".svg")) continue;

			final name = entry.substr(0, entry.length - 4);
			final svg = Svg.read(File.getContent(from + "/" + entry));

			final rgba = Raster.paint(svg, PRESENCE);
			final at = into + "/" + name + ".png";

			File.saveBytes(at, Png.write(rgba, PRESENCE));

			Sys.println("  " + pad(name) + PRESENCE + "x" + PRESENCE + ", "
				+ Math.round(FileSystem.stat(at).size / 1024) + " kb");
		}

		Sys.println("");
		Sys.println("  upload these as the art assets of the discord application named in");
		Sys.println("  mdd.xml, under the same names, then set them in the presence block");
		Sys.println("");
	}

	static function check(root:String, project:Project):Void {
		final vendor = root + "/vendor";
		var missing = 0;

		Sys.println("");
		Sys.println("  " + project.title + " " + project.version + ", building for " + system());
		Sys.println("");
		Sys.println("  vendor");

		for (source in project.vendors) {
			final here = vendored(root, source);
			final spare = source.flag != "";

			if (!here && !spare) missing++;

			final mark = here ? "[x] " : (spare ? "[-] " : "[ ] ");
			final tail = here || !spare ? "" : ". Ask with: mdd setup --" + source.flag;

			Sys.println("    " + mark + pad(source.name) + source.about + tail);
		}

		Sys.println("");
		Sys.println("  toolchain");
		Sys.println("    " + (tool("haxe", ["--version"]) ? "[x] " : "[ ] ") + pad("haxe")
			+ "4.3 or newer");
		Sys.println("    " + (tool("curl", ["--version"]) ? "[x] " : "[ ] ") + pad("curl")
			+ "what setup fetches with");

		final hxcpp = hxcppAt();
		Sys.println("    " + (hxcpp == "" ? "[ ] " : "[x] ") + pad("hxcpp")
			+ (hxcpp == "" ? "not installed. Ask with: haxelib git hxcpp "
				+ "https://github.com/HaxeFoundation/hxcpp.git" : hxcpp));

		if (project.toolchains.length > 0) {
			Sys.println("");
			Sys.println("  compilers");

			for (held in project.toolchains) {
				final here = held.probe == "" || tool(held.probe, ["--version"]);
				final mark = held.name == project.toolchain ? "[>] "
					: (here ? "[x] " : "[ ] ");

				Sys.println("    " + mark + pad(held.name) + held.about
					+ (held.name == project.toolchain ? ", what a build uses here" : ""));
			}
		}

		Sys.println("");
		Sys.println("  built");

		for (target in project.targets) {
			final exe = exeOf(root, project, target.id);
			Sys.println("    " + (exe != "" ? "[x] " : "[ ] ") + pad(target.id)
				+ (exe != "" ? exe.substr(root.length + 1) : "not built"));
		}

		Sys.println("");
		Sys.println("  completion");
		display(root, project, true);

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

	static function configure(root:String, project:Project, spoken:Array<String>):Void {
		final into = root + "/" + project.generated + "/mdd";
		tree(into);

		final out = new StringBuf();
		out.add("package mdd;\n\n");
		out.add("class Config {\n");
		out.add("\tpublic static inline final TITLE = \"" + project.title + "\";\n");
		out.add("\tpublic static inline final SHORT = \"" + project.short + "\";\n");
		out.add("\tpublic static inline final COMPANY = \"" + project.company + "\";\n");
		out.add("\tpublic static inline final DESCRIPTION = \"" + project.description + "\";\n");
		out.add("\tpublic static inline final GITHUB = \"" + project.github + "\";\n");
		out.add("\tpublic static inline final DISCORD = \"" + project.discord + "\";\n");
		out.add("\tpublic static inline final DISCORD_COVER = \"" + project.discordCover + "\";\n");
		out.add("\tpublic static inline final DISCORD_PLAYING = \"" + project.discordPlaying + "\";\n");
		out.add("\tpublic static inline final DISCORD_STOPPED = \"" + project.discordStopped + "\";\n");
		out.add("\tpublic static inline final DISCORD_WORKING = \"" + project.discordWorking + "\";\n");
		
		out.add("\tpublic static inline final VERSION = \"" + project.version + "\";\n");
		out.add("\tpublic static inline final WIDTH = " + project.windowWidth + ";\n");
		out.add("\tpublic static inline final HEIGHT = " + project.windowHeight + ";\n");
		out.add("\tpublic static inline final LEAST_WIDTH = " + project.leastWidth + ";\n");
		out.add("\tpublic static inline final LEAST_HEIGHT = " + project.leastHeight + ";\n");
		out.add("\tpublic static inline final VSYNC = " + project.vsync + ";\n");
		out.add("\tpublic static inline final RESIZABLE = " + project.resizable + ";\n");
		out.add("\tpublic static inline final HIGH_DPI = " + project.highDpi + ";\n");
		out.add("\tpublic static inline final SPOKEN = \"" + spoken.join(",") + "\";\n");
		out.add("\tpublic static inline final SUFFIX = \"" + project.formatSuffix + "\";\n");
		out.add("\tpublic static inline final FORMAT = \"" + project.formatName + "\";\n");
		out.add("\tpublic static inline final MIME = \"" + project.formatMime + "\";\n");
		out.add("\n\t/**\n\t\tWhat a preset file is called, past the dot.\n\t**/\n");
		out.add("\tpublic static inline final PRESET = \"" + project.presetSuffix + "\";\n");
		out.add("\n\t/**\n\t\tWhat the desktop calls a preset file.\n\t**/\n");
		out.add("\tpublic static inline final PRESET_FORMAT = \"" + project.presetName + "\";\n");
		out.add("\n\t/**\n\t\tThe media type a preset file is served as.\n\t**/\n");
		out.add("\tpublic static inline final PRESET_MIME = \"" + project.presetMime + "\";\n");
		out.add("\n\t/**\n\t\tWhat a bank of presets is called, past the dot.\n\t**/\n");
		out.add("\tpublic static inline final BANK = \"" + project.bankSuffix + "\";\n");
		out.add("\n\t/**\n\t\tWhat the desktop calls a bank of presets.\n\t**/\n");
		out.add("\tpublic static inline final BANK_FORMAT = \"" + project.bankName + "\";\n");
		out.add("\n\t/**\n\t\tThe media type a bank of presets is served as.\n\t**/\n");
		out.add("\tpublic static inline final BANK_MIME = \"" + project.bankMime + "\";\n");
		out.add("}\n");

		File.saveContent(into + "/Config.hx", out.toString());
	}

	static function languages(root:String, project:Project):Array<String> {
		final from = root + "/" + project.languages;
		final into = root + "/" + project.output + "/lang";

		final found:Array<String> = [];
		if (!FileSystem.exists(from)) return found;

		tree(into);

		for (entry in FileSystem.readDirectory(from)) {
			if (!StringTools.endsWith(entry, ".json")) continue;

			final code = entry.substr(0, entry.length - 5);
			final packed = into + "/" + code + ".mdl";

			if (!packing(from + "/" + entry, packed, code)) continue;
			found.push(code);
		}

		found.sort(byName);
		return found;
	}

	static function byName(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	static function packing(from:String, into:String, code:String):Bool {
		var table:Dynamic = null;

		try {
			table = haxe.Json.parse(File.getContent(from));
		} catch (e:Dynamic) {
			Sys.println("  " + pad(code) + "would not read: " + e);
			return false;
		}

		final keys = Reflect.fields(table);
		keys.sort(byName);

		final out = new haxe.io.BytesOutput();

		out.writeString("MDL1");
		out.writeInt32(keys.length);

		for (key in keys) {
			final said = Std.string(Reflect.field(table, key));

			final left = haxe.io.Bytes.ofString(key);
			final right = haxe.io.Bytes.ofString(said);

			out.writeUInt16(left.length);
			out.write(left);
			out.writeUInt16(right.length);
			out.write(right);
		}

		File.saveBytes(into, out.getBytes());
		return true;
	}

	static function grown(root:String, grove:Grove):Array<String> {
		final where = root + "/" + grove.path;
		final found:Array<String> = [];

		if (!FileSystem.isDirectory(where)) return found;

		final names = FileSystem.readDirectory(where);
		names.sort(byName);

		for (name in names) {
			if (!grove.wanted(name)) continue;

			found.push(native(where) + "/" + name);
		}

		return found;
	}

	/**
		Which hxcpp a build would use, named the way a person can compare it against what
		the workflows install.

		The version haxelib reports is the one in `haxelib.json`, which a git checkout leaves
		at whatever the last release said, so it tells a reader nothing about how new the
		checkout is. The tag the checkout sits on is what does, and it is asked of git.

		@return A description, or an empty string where hxcpp is not installed.
	**/
	static function hxcppAt():String {
		final where = StringTools.trim(reads("haxelib", ["path", "hxcpp"]).split("\n")[0]);
		if (where == "" || !FileSystem.exists(where)) return "";

		final here = Sys.getCwd();
		var said = "";

		try {
			Sys.setCwd(where);
			said = StringTools.trim(reads("git", ["describe", "--tags", "--always"]));
		} catch (e:Dynamic) {
			said = "";
		}

		Sys.setCwd(here);

		if (said != "") return said + ", from git";
		return "from haxelib, which trails the tags. See docs/BUILDING.md";
	}

	static function nativeXml(root:String, project:Project):String {
		final into = root + "/" + project.output + "/build";
		tree(into);

		final flags = new StringBuf();
		for (flag in project.compileFlags) {
			flags.add("\t\t<compilerflag value=\"" + flag + "\" />\n");
		}

		for (path in project.includes) {
			if (rooted(path) && !FileSystem.exists(path)) continue;

			final where = rooted(path) ? path : root + "/" + path;
			flags.add("\t\t<compilerflag value=\"-I" + native(where) + "\" />\n");
		}

		final script = windows() ? resourceScript(root, project) : "";

		final out = new StringBuf();
		out.add("<xml>\n");

		for (id in ["haxe", "__main__", "mdd_native"]) {
			out.add("\t<files id=\"" + id + "\">\n");
			out.add(flags.toString());

			if (id == "mdd_native") {
				for (flag in project.nativeFlags) {
					out.add("\t\t<compilerflag value=\"" + flag + "\" />\n");
				}

				for (file in project.nativeFiles) {
					out.add("\t\t<file name=\"" + native(root + "/" + project.nativePath) + "/"
						+ file + "\" />\n");
				}

				for (grove in project.nativeTrees) {
					if (grove.include != "") continue;

					for (name in grown(root, grove)) {
						out.add("\t\t<file name=\"" + name + "\" />\n");
					}
				}

			}

			out.add("\t</files>\n");
		}

		final extra:Array<String> = [];

		for (index in 0...project.nativeTrees.length) {
			final grove = project.nativeTrees[index];
			if (grove.include == "") continue;

			final id = "mdd_tree_" + index;
			extra.push(id);

			out.add("\t<files id=\"" + id + "\">\n");
			out.add(flags.toString());
			out.add("\t\t<compilerflag value=\"-I"
				+ native(root + "/" + grove.include) + "\" />\n");

			for (flag in project.nativeFlags) {
				out.add("\t\t<compilerflag value=\"" + flag + "\" />\n");
			}

			for (name in grown(root, grove)) {
				out.add("\t\t<file name=\"" + name + "\" />\n");
			}

			out.add("\t</files>\n");
		}

		if (script != "") {
			out.add("\t<files id=\"mdd_resource\">\n");
			out.add("\t\t<file name=\"" + script + "\" />\n");
			out.add("\t</files>\n");
		}

		out.add("\t<target id=\"haxe\">\n");

		for (flag in project.linkFlags) {
			out.add("\t\t<flag value=\"" + flag + "\" />\n");
		}

		for (link in project.links) {
			if (!loose(link)) {
				out.add("\t\t<lib name=\"" + native(root + "/" + link)
					+ "\" />\n");
				continue;
			}

			for (part in link.split(" ")) {
				final one = StringTools.trim(part);
				if (one == "") continue;

				if (StringTools.startsWith(one, "-L/")
						&& !FileSystem.exists(one.substr(2))) continue;

				out.add("\t\t<lib name=\"" + one + "\" />\n");
			}
		}

		out.add("\t\t<files id=\"mdd_native\" />\n");
		if (script != "") out.add("\t\t<files id=\"mdd_resource\" />\n");
		for (id in extra) out.add("\t\t<files id=\"" + id + "\" />\n");
		out.add("\t</target>\n");
		out.add("</xml>\n");

		final path = into + "/native.xml";
		File.saveContent(path, out.toString());
		return native(path);
	}

	static function resourceScript(root:String, project:Project):String {
		final ico = native(root + "/" + project.appIcon) + "/" + project.short + ".ico";
		if (!FileSystem.exists(ico)) return "";

		final into = root + "/" + project.output + "/build";
		tree(into);

		final parts = project.version.split(".");
		while (parts.length < 4) parts.push("0");

		final out = new StringBuf();
		out.add("1 ICON \"" + ico + "\"\n\n");
		out.add("1 VERSIONINFO\n");
		out.add("FILEVERSION " + parts.join(",") + "\n");
		out.add("PRODUCTVERSION " + parts.join(",") + "\n");
		out.add("BEGIN\n");
		out.add("  BLOCK \"StringFileInfo\"\n");
		out.add("  BEGIN\n");
		out.add("    BLOCK \"080904b0\"\n");
		out.add("    BEGIN\n");
		out.add("      VALUE \"CompanyName\", \"" + project.company + "\"\n");
		out.add("      VALUE \"FileDescription\", \"" + project.title + "\"\n");
		out.add("      VALUE \"Comments\", \"" + project.description + "\"\n");
		out.add("      VALUE \"FileVersion\", \"" + project.version + "\"\n");
		out.add("      VALUE \"InternalName\", \"" + project.short + "\"\n");
		out.add("      VALUE \"OriginalFilename\", \"" + project.short + ".exe\"\n");
		out.add("      VALUE \"ProductName\", \"" + project.title + "\"\n");
		out.add("      VALUE \"ProductVersion\", \"" + project.version + "\"\n");
		out.add("    END\n");
		out.add("  END\n");
		out.add("  BLOCK \"VarFileInfo\"\n");
		out.add("  BEGIN\n");
		out.add("    VALUE \"Translation\", 0x809, 1200\n");
		out.add("  END\n");
		out.add("END\n");

		final path = into + "/" + project.short + ".rc";
		File.saveContent(path, out.toString());
		return native(path);
	}

	static function display(root:String, project:Project, loud:Bool):Void {
		final spoken = languages(root, project);

		configure(root, project, spoken);
		Catalogue.named(project, root, root + "/" + project.generated);
		Icons.named(project, root + "/" + project.generated);
		Icons.typefaces(project, root + "/" + project.generated, root + "/" + project.typefacePath);
		final xml = nativeXml(root, project);

		for (one in project.targets) {
			final name = one.id == project.targets[0].id
				? "completion.hxml" : "completion-" + one.id + ".hxml";

			final args = typing(compiled(root, project, one.id, spoken, xml, false));
			args.push("--no-output");

			written(root, name, one.id, args, loud);
		}

		written(root, "completion-tools.hxml", "tools",
			["-main", "Run", "-cp", root + "/tools/src", "--interp", "--no-output"], loud);

		database(root, project, loud);
	}

	/**
		Leaves out of a completion file what only changes the code a build generates: dead code
		elimination and the analyzer's optimisations. The language server types the same code
		without them and generates none, so they cost it time and change nothing it reports.

		@param args The arguments a build would use.
		@return The same arguments without those.
	**/
	static function typing(args:Array<String>):Array<String> {
		final out:Array<String> = [];
		var index = 0;

		while (index < args.length) {
			final flag = args[index];
			final next = index + 1 < args.length ? args[index + 1] : "";

			if (flag == "-dce" || (flag == "-D" && next == "analyzer-optimize")) {
				index += 2;
				continue;
			}

			out.push(flag);
			index++;
		}

		return out;
	}

	/**
		Writes the compilation database a C or C++ editor reads, so completion in a native file
		sees the include paths and defines the build compiles it with. There is one entry per
		native source, with the trees walked the way `nativeXml` walks them. Nothing builds from
		it.

		@param root The repository.
		@param project The build file, read for this platform and toolchain.
		@param loud Whether to say what was written.
	**/
	static function database(root:String, project:Project, loud:Bool):Void {
		final shared:Array<String> = [];

		for (flag in project.compileFlags) shared.push(flag);

		for (path in project.includes) {
			if (rooted(path) && !FileSystem.exists(path)) continue;
			shared.push("-I" + native(rooted(path) ? path : root + "/" + path));
		}

		for (flag in project.nativeFlags) shared.push(flag);

		final entries:Array<String> = [];

		for (file in project.nativeFiles) {
			entries.push(entry(root, project, native(root + "/" + project.nativePath) + "/" + file,
				shared, ""));
		}

		for (grove in project.nativeTrees) {
			final own = grove.include == "" ? "" : "-I" + native(root + "/" + grove.include);
			for (name in grown(root, grove)) entries.push(entry(root, project, name, shared, own));
		}

		final into = root + "/" + project.output;
		tree(into);

		File.saveContent(into + "/compile_commands.json", "[\n" + entries.join(",\n") + "\n]\n");

		if (loud) {
			Sys.println("    " + pad("native") + project.output + "/compile_commands.json, "
				+ entries.length + " files for " + project.toolchain);
		}
	}

	/**
		@param root The repository.
		@param project The build file, read for this platform and toolchain.
		@param file A native source, as an absolute path.
		@param shared The flags every native source is compiled with.
		@param own A flag only this file's tree adds, or an empty string for none.
		@return The file's entry in the compilation database, as JSON.
	**/
	static function entry(root:String, project:Project, file:String, shared:Array<String>,
			own:String):String {
		final plain = StringTools.endsWith(file, ".c");
		final cl = project.toolchain == "msvc" || project.toolchain == "clang-cl";

		final args:Array<String> = [switch (project.toolchain) {
			case "msvc": "cl.exe";
			case "clang-cl": "clang-cl.exe";
			case "gcc": plain ? "gcc" : "g++";
			case _: plain ? "clang" : "clang++";
		}];

		if (!plain) args.push(cl ? "/std:c++17" : "-std=c++17");
		for (flag in shared) args.push(flag);
		if (own != "") args.push(own);

		args.push("-c");
		args.push(file);

		return "\t{\"directory\": " + haxe.Json.stringify(native(root)) + ", \"file\": "
			+ haxe.Json.stringify(file) + ", \"arguments\": " + haxe.Json.stringify(args) + "}";
	}

	static function written(root:String, name:String, target:String, args:Array<String>,
			loud:Bool):Void {
		final out = new StringBuf();

		out.add("# The " + target + " arguments the editor's Haxe language server reads.\n");
		out.add("# Generated by mdd from mdd.xml. Edit that file: this one is written again.\n");
		out.add("#\n");
		out.add("# Nothing builds from here. mdd build reads the same options and adds the\n");
		out.add("# resources, the output, and the dead code elimination and optimisation this\n");
		out.add("# file leaves out because the language server generates no code.\n\n");

		var index = 0;

		while (index < args.length) {
			final flag = args[index++];
			out.add(flag);

			if (index < args.length && !StringTools.startsWith(args[index], "-")) {
				out.add(" ");
				out.add(relative(root, args[index++]));
			}

			out.add("\n");
		}

		File.saveContent(root + "/" + name, relative(root, out.toString()));
		if (loud) Sys.println("    " + pad(target) + name);
	}

	static function relative(root:String, value:String):String {
		return StringTools.replace(value, root + "/", "");
	}

	static function compiled(root:String, project:Project, target:String, spoken:Array<String>,
			xml:String, resources:Bool):Array<String> {
		final one = project.targetOf(target);
		final args = ["-main", one.main, "-cpp", root + "/" + project.output + "/obj/" + target];

		for (path in project.sourcesOf(target)) {
			args.push("-cp");
			args.push(root + "/" + path);
		}

		args.push("-cp");
		args.push(root + "/" + project.generated);

		for (library in project.libraries) {
			args.push("-lib");
			args.push(library);
		}

		if (project.dce != "") {
			args.push("-dce");
			args.push(project.dce);
		}

		for (define in project.defines) {
			args.push("-D");
			args.push(define);
		}

		for (named in project.paths) {
			args.push("-D");
			args.push(named.name + "=" + native(root + "/" + named.value));
		}

		args.push("-D");
		args.push("MDDBUILD=" + xml);

		switch (project.toolchain) {
			case "clang-cl":
				Sys.putEnv("HXCPP_CONFIG", native(overrides(root, project)));

			case "mingw":
				args.push("-D");
				args.push("HXCPP_MINGW");

			case "clang":
				args.push("-D");
				args.push("CXX=clang++");

			case _:
		}

		if (!resources) return args;

		for (code in spoken) {
			args.push("-resource");
			args.push(root + "/" + project.output + "/lang/" + code + ".mdl@lang." + code);
		}

		final face = root + "/" + project.appIcon + "/" + project.short + "-64.rgba";

		if (FileSystem.exists(face)) {
			args.push("-resource");
			args.push(face + "@icon");
		}

		final banks = root + "/export/banks";

		if (FileSystem.exists(banks)) {
			final held = FileSystem.readDirectory(banks);
			held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

			for (name in held) {
				final dot = name.lastIndexOf(".");
				if (dot <= 0) continue;

				args.push("-resource");
				args.push(banks + "/" + name + "@bank." + name.substr(0, dot));
			}
		}

		return args;
	}

	/**
		Writes the banks the application ships out as records, where a document has changed or gone
		since they were last written: the starting bank into the folder compiled into the
		application, and every other bank, a file for each family it has presets for, into a folder
		copied beside the built binary. A package takes that folder from there, and the application
		writes what is in it into a reader's presets folder once, where it can be deleted. The
		documents are what anyone improving a name or a tag edits, and what a build carries is what
		the application reads.

		@param root The repository.
		@param project What the build file says.
	**/
	static function banked(root:String, project:Project):Void {
		final from = root + "/assets/presets";
		final into = root + "/export/banks";
		final beside = root + "/export/shipped";
		final bin = root + "/" + project.output + "/bin/presets";

		if (!FileSystem.exists(from)) return;

		final stamp = into + "/written";
		final listing = listed(from);

		var stale = !FileSystem.exists(stamp) || !FileSystem.exists(beside)
			|| File.getContent(stamp) != listing;

		if (!stale) {
			final written = FileSystem.stat(stamp).mtime.getTime();

			for (name in FileSystem.readDirectory(from)) {
				if (FileSystem.stat(from + "/" + name).mtime.getTime() > written) stale = true;
			}
		}

		if (stale) {
			Sys.println("  " + pad("banks") + "writing the shipped banks as records");

			if (FileSystem.exists(into)) remove(into);
			if (FileSystem.exists(beside)) remove(beside);

			tree(into);

			final here = Sys.getCwd();
			Sys.setCwd(root);

			final code = Sys.command("haxe", ["-cp", "src", "-cp", project.generated, "-cp", "tools/src",
				"--run", "Banker", from, into, beside]);

			Sys.setCwd(here);

			if (code != 0) {
				Sys.println("mdd: the shipped banks could not be written");
				Sys.exit(code);
			}

			File.saveContent(stamp, listing);
		}

		if (stale || !FileSystem.exists(bin)) {
			if (FileSystem.exists(bin)) remove(bin);
			mirrored(beside, bin);
		}
	}

	/**
		@param from The folder the bank documents are in.
		@return Every document in it, one a line in order, which is what says one was added or
			taken away since the banks were last written.
	**/
	static function listed(from:String):String {
		final held = FileSystem.readDirectory(from).filter(function(name:String):Bool
			return StringTools.endsWith(name.toLowerCase(), ".json"));

		held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		return held.join("\n");
	}

	/**
		Copies a folder and everything in it.

		@param from The folder.
		@param to Where the copy goes, made where it is not there.
	**/
	static function mirrored(from:String, to:String):Void {
		if (!FileSystem.exists(from)) return;

		tree(to);

		for (name in FileSystem.readDirectory(from)) {
			final path = from + "/" + name;

			if (FileSystem.isDirectory(path)) mirrored(path, to + "/" + name);
			else copyFile(path, to + "/" + name);
		}
	}

	static function built(root:String, project:Project, target:String, debug:Bool):Void {
		if (windows() && !FileSystem.exists(root + "/" + project.pathOf("SDL3PATH")
				+ "/lib/SDL3.lib")) {
			Sys.println("mdd: SDL3 is missing from vendor/. Run: mdd setup");
			Sys.exit(1);
		}

		final spoken = languages(root, project);

		configure(root, project, spoken);
		Catalogue.named(project, root, root + "/" + project.generated);
		Icons.named(project, root + "/" + project.generated);
		Icons.typefaces(project, root + "/" + project.generated, root + "/" + project.typefacePath);
		Icons.built(root, project, root + "/" + project.output + "/icons", false);
		banked(root, project);

		final xml = nativeXml(root, project);

		final args = compiled(root, project, target, spoken, xml, true);
		if (debug) args.push("-debug");

		display(root, read(root, false, project.toolchain), false);

		Sys.println("  " + pad(target) + "building"
			+ (project.toolchain == "" ? "" : " with " + project.toolchain));
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

	static function strips(root:String, project:Project, target:String, exe:String):Void {
		if (project.stripped.length == 0 || !FileSystem.exists(exe)) return;

		final cutter = tool("llvm-objcopy", ["--version"]) ? "llvm-objcopy"
			: (tool("objcopy", ["--version"]) ? "objcopy" : "");

		if (cutter == "") {
			Sys.println("  " + pad(target) + "no objcopy, so the symbols stay in the binary");
			return;
		}

		final args:Array<String> = [];
		for (name in project.stripped) args.push("--remove-section=" + name);
		args.push(native(exe));

		final was = FileSystem.stat(exe).size;
		if (Sys.command(cutter, args) != 0) return;

		final now = FileSystem.stat(exe).size;
		if (now >= was) return;

		Sys.println("  " + pad(target) + "shed " + Math.round((was - now) / 1048576)
			+ " MB of what the crash report never reads");
	}

	/**
		Puts the library the window is built on beside the binary, and points the binary at
		that copy rather than at wherever the machine that built it kept the original.

		Windows names its own copy in the build file and needs nothing more. macOS and Linux
		link whatever the package manager installed, so the binary comes out holding an
		absolute path: `/opt/homebrew` on an arm64 Mac, `/usr/local` on an Intel one, and the
		distribution's own directory on Linux. None of those exist on the machine an archive is
		unpacked on, and the loader stops rather than looking anywhere else.

		macOS is repointed here because the path is written into the binary at link time from
		the library's own install name. Linux is repointed at link time instead, by the rpath
		of `$ORIGIN` the build file passes, so there is nothing left to do but carry the copy.

		@param project The build file.
		@param target Which target, for the line printed.
		@param exe The binary, already beside what it ships with.
	**/
	static function carries(project:Project, target:String, exe:String):Void {
		if (windows() || project.carry == "" || !FileSystem.exists(exe)) return;

		final apple = system() == "mac";
		final reader = apple ? "otool" : "ldd";

		final said = reads(reader, apple ? ["-L", native(exe)] : [native(exe)]);
		if (said == "") return;

		var from = "";

		for (line in said.split("\n")) {
			final held = StringTools.trim(line);
			if (held.indexOf(project.carry) < 0) continue;

			if (apple) from = held.split(" ")[0];
			else if (held.indexOf("=> ") >= 0) {
				from = StringTools.trim(held.split("=> ")[1]).split(" ")[0];
			}

			break;
		}

		if (from == "" || StringTools.startsWith(from, "@") || StringTools.startsWith(from, "$")) {
			return;
		}

		if (!FileSystem.exists(from)) {
			Sys.println("  " + pad(target) + reader + " names " + from
				+ ", which is not there to carry");
			return;
		}

		final name = haxe.io.Path.withoutDirectory(from);
		final beside = haxe.io.Path.directory(exe) + "/" + name;

		copyFile(from, beside);
		runnable(beside);

		if (!apple) {
			Sys.println("  " + pad(target) + "carries " + name + " beside it");
			return;
		}

		if (Sys.command("install_name_tool", ["-change", from, "@executable_path/" + name,
				native(exe)]) != 0) {
			Sys.println("  " + pad(target) + "install_name_tool would not repoint " + name
				+ ", so the binary still wants " + from);
			return;
		}

		if (Sys.command("codesign", ["--force", "--sign", "-", native(exe)]) != 0) {
			Sys.println("  " + pad(target) + "codesign would not sign the binary again, and an"
				+ " arm64 Mac refuses one whose signature install_name_tool broke");
			return;
		}

		Sys.println("  " + pad(target) + "carries " + name + " beside it");
	}

	/**
		@param name A program.
		@param args What to pass it.
		@return What it wrote, or an empty string where it would not run or failed.
	**/
	static function reads(name:String, args:Array<String>):String {
		try {
			final run = new sys.io.Process(name, args);
			final said = run.stdout.readAll().toString();
			final code = run.exitCode();

			run.close();
			return code == 0 ? said : "";
		} catch (e:Dynamic) {
			return "";
		}
	}

	static function exeOf(root:String, project:Project, target:String):String {
		final one = project.targetOf(target);
		if (one == null) return "";

		final dir = root + "/" + project.output + "/obj/" + target;
		final stem = one.main.split(".").pop();

		var found = "";
		var newest = 0.0;

		for (name in [dir + "/" + stem + ".exe", dir + "/" + stem,
				dir + "/" + stem + "-debug.exe", dir + "/" + stem + "-debug"]) {
			if (!FileSystem.exists(name)) continue;

			final made = FileSystem.stat(name).mtime.getTime();
			if (made < newest) continue;

			newest = made;
			found = name;
		}

		return found;
	}

	static function ship(root:String, project:Project, target:String):String {
		final exe = exeOf(root, project, target);
		if (exe == "") return "";

		final into = root + "/" + project.output + "/bin";
		tree(into);

		final suffix = StringTools.endsWith(exe, ".exe") ? ".exe" : "";
		final shipped = into + "/" + target + suffix;

		copyFile(exe, shipped);
		runnable(shipped);
		strips(root, project, target, shipped);
		carries(project, target, shipped);

		for (one in project.ships) {
			final from = root + "/" + one;
			if (FileSystem.exists(from)) {
				copyFile(from, into + "/" + haxe.io.Path.withoutDirectory(one));
			}
		}

		final atlases = root + "/" + project.output + "/icons";

		if (FileSystem.exists(atlases)) {
			tree(into + "/icons");

			for (name in FileSystem.readDirectory(atlases)) {
				copyFile(atlases + "/" + name, into + "/icons/" + name);
			}
		}

		if (target == project.targets[0].id) besideFonts(root, project, into);

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

	static function compiler():String {
		for (name in ["gcc", "clang", "cc"]) if (tool(name, ["--version"])) return name;
		return "";
	}

	static function opn2(root:String, project:Project):Void {
		final source = root + "/vendor/Nuked-OPN2/ym3438.c";
		if (!FileSystem.exists(source)) return;

		final into = root + "/" + project.output + "/bin";
		tree(into);

		final exe = into + "/opn2" + (windows() ? ".exe" : "");
		final own = root + "/tools/opn2/opn2.c";

		if (FileSystem.exists(exe)
			&& FileSystem.stat(exe).mtime.getTime() >= FileSystem.stat(own).mtime.getTime()
			&& FileSystem.stat(exe).mtime.getTime() >= FileSystem.stat(source).mtime.getTime()) {
			return;
		}

		final which = compiler();
		if (which == "") {
			Sys.println("  " + pad("opn2") + "no C compiler on the path, the reference cannot build");
			return;
		}

		Sys.println("  " + pad("opn2") + "building the reference with " + which);

		final code = Sys.command(which, [
			"-O2", "-o", exe, own, source, "-I" + root + "/vendor/Nuked-OPN2"
		]);

		if (code != 0) Sys.println("  " + pad("opn2") + "the reference would not build");
	}

	static inline final SKIPPED = 2;

	static function gate(root:String, project:Project, args:Array<String>):Void {
		if (exeOf(root, project, "gate") == "") built(root, project, "gate", false);

		if (args.length == 0 || args[0] == "chip") opn2(root, project);


		final shipped = ship(root, project, "gate");
		if (shipped == "") {
			Sys.println("mdd: the gate is not built");
			Sys.exit(1);
		}

		final code = Sys.command(shipped, args.concat(["--root", root]));
		Sys.exit(code == SKIPPED ? 0 : code);
	}

	static function packaged(root:String, project:Project, args:Array<String>):Void {
		final kind = args.length > 0 && !StringTools.startsWith(args[0], "-") ? args[0] : "both";

		if (exeOf(root, project, project.targets[0].id) == "") {
			Sys.println("mdd: build it first");
			Sys.exit(1);
		}

		Sys.println("");

		if (kind == "portable" || kind == "both") portable(root, project);
		if (kind == "installer" || kind == "both") installer(root, project);

		Sys.println("");
	}

	/**
		@param project What the build file declares.
		@param name A file beside the built binary.
		@return Whether it goes into a package: the application's own binary, a library the build
			file ships, or the one it carries from the system. Anything else that lands beside the
			binary stays behind, which is what keeps a stale archive or a check program out of what
			a reader downloads.
	**/
	static function packs(project:Project, name:String):Bool {
		final lower = name.toLowerCase();
		final binary = project.targets[0].id + (windows() ? ".exe" : "");

		if (lower == binary.toLowerCase()) return true;

		for (one in project.ships) {
			if (haxe.io.Path.withoutDirectory(one).toLowerCase() == lower) return true;
		}

		return !windows() && project.carry != "" && name.indexOf(project.carry) >= 0;
	}

	/**
		@param face A face the build file declares.
		@return Whether the application fetches it for itself when the language it serves is
			picked, which it can only do for a face pinned to a commit and a hash. The installer
			offers a face like that as a choice, and a portable folder leaves it out.
	**/
	static function fetched(face:Project.Face):Bool {
		return face.language != "" && face.commit != "" && face.sha256 != "";
	}

	/**
		@param project What the build file declares.
		@param name A file in the fonts folder.
		@param whole Whether the faces the application can fetch for itself go in too.
		@return Whether it goes beside the binary: a face, unless it is one of those and they are
			being left out, and every licence text, which is small and which a fetched face needs
			as much as one that ships.
	**/
	static function faced(project:Project, name:String, whole:Bool):Bool {
		final lower = name.toLowerCase();

		if (StringTools.endsWith(lower, ".txt") || name == "LICENSE") return true;
		if (!StringTools.endsWith(lower, ".ttf")) return false;
		if (whole) return true;

		for (face in project.faces) if (face.name == name && fetched(face)) return false;

		return true;
	}

	/**
		Puts the faces a portable folder holds beside the built binary, so that running it from
		`export/bin` finds its fonts where a reader's copy does. The application looks nowhere
		else, and that is what stops a fonts folder missing from a download being covered by the
		one in this repository.

		A face is copied only where it is missing or older than its source, and one that no longer
		belongs there is removed.

		@param root The repository.
		@param project What the build file declares.
		@param into The folder the binary is in.
	**/
	static function besideFonts(root:String, project:Project, into:String):Void {
		final from = root + "/" + project.pathOf("FONTPATH");
		final to = into + "/fonts";

		if (!FileSystem.exists(from)) return;

		tree(to);

		final wanted:Array<String> = [];

		for (entry in FileSystem.readDirectory(from)) {
			if (!faced(project, entry, false)) continue;

			wanted.push(entry);

			final source = from + "/" + entry;
			final target = to + "/" + entry;

			if (FileSystem.exists(target) && FileSystem.stat(target).mtime.getTime()
					>= FileSystem.stat(source).mtime.getTime()) {
				continue;
			}

			copyFile(source, target);
		}

		for (entry in FileSystem.readDirectory(to)) {
			if (wanted.indexOf(entry) < 0) FileSystem.deleteFile(to + "/" + entry);
		}
	}

	/**
		Gathers everything a package holds into one folder.

		@param root The repository.
		@param project What the build file declares.
		@param into The folder to gather into.
		@param whole Whether the faces the application can fetch for itself go in too, which an
			installer offers as a choice and a portable folder leaves out.
		@return The folder.
	**/
	static function staged(root:String, project:Project, into:String, whole:Bool):String {
		if (FileSystem.exists(into)) remove(into);
		tree(into);

		final bin = root + "/" + project.output + "/bin";

		for (entry in FileSystem.readDirectory(bin)) {
			final from = bin + "/" + entry;
			if (FileSystem.isDirectory(from)) continue;
			if (!packs(project, entry)) continue;

			copyFile(from, into + "/" + entry);
		}


		final atlases = bin + "/icons";

		if (FileSystem.exists(atlases)) {
			tree(into + "/icons");

			for (entry in FileSystem.readDirectory(atlases)) {
				copyFile(atlases + "/" + entry, into + "/icons/" + entry);
			}
		}

		final notice = root + "/vendor/qlementine/LICENSE";
		if (FileSystem.exists(notice)) copyFile(notice, into + "/icons/LICENSE");

		mirrored(bin + "/presets", into + "/presets");

		final fonts = root + "/" + project.pathOf("FONTPATH");
		tree(into + "/fonts");

		for (entry in FileSystem.readDirectory(fonts)) {
			if (!faced(project, entry, whole)) continue;

			copyFile(fonts + "/" + entry, into + "/fonts/" + entry);
		}

		for (entry in ["LICENSE", "README.md"]) {
			if (FileSystem.exists(root + "/" + entry)) copyFile(root + "/" + entry, into + "/" + entry);
		}

		return into;
	}

	static function archived(where:String, what:String, into:String):Int {
		final here = Sys.getCwd();
		Sys.setCwd(where);

		final made = windows()
			? Sys.command("powershell", ["-NoProfile", "-Command",
				"Compress-Archive -Path '" + what + "' -DestinationPath '" + into
				+ "' -CompressionLevel Optimal -Force"])
			: Sys.command("tar", ["-czf", into, what]);

		Sys.setCwd(here);
		return made;
	}

	static function toolAt(name:String, where:Array<String>):String {
		if (tool(name, ["/?"])) return name;
		for (path in where) if (FileSystem.exists(path)) return path;

		return "";
	}

	static function portable(root:String, project:Project):Void {
		final name = stamp(project) + "-portable";
		final into = root + "/" + project.output + "/package/" + name;

		staged(root, project, into, false);

		File.saveContent(into + "/portable.txt",
			"This file keeps " + project.title + " portable: settings, projects and presets go\n"
			+ "into userdata/ beside the program rather than into the account's documents.\n"
			+ "Delete it and userdata/ to use the usual place.\n");

		for (what in ["settings", "projects", "presets", "updates"]) {
			tree(into + "/userdata/" + what);
			File.saveContent(into + "/userdata/" + what + "/.keep", "");
		}

		final archive = root + "/" + project.output + "/package/" + name
			+ (windows() ? ".zip" : ".tar.gz");

		if (FileSystem.exists(archive)) FileSystem.deleteFile(archive);

		final made = archived(root + "/" + project.output + "/package", name,
			name + (windows() ? ".zip" : ".tar.gz"));

		if (made != 0) {
			Sys.println("  " + pad("portable") + "the folder is at " + into
				+ ", but tar would not archive it");
			return;
		}

		Sys.println("  " + pad("portable") + archive.substr(root.length + 1) + ", "
			+ Math.round(FileSystem.stat(archive).size / 1024) + " kb");
	}

	/**
		Writes the terms the installer asks to be accepted: the template from the build file
		with the project's name and pages filled in, and the licence after it.

		The page they are shown on wraps text to its own width, so a paragraph wrapped in the
		template is joined back into one line here, and a line starting with a dash stays a
		line of its own.

		@param root The repository root.
		@param project What the build file declares.
		@return The file written, or an empty string where the build file names no template
			or it is not there.
	**/
	static function termed(root:String, project:Project):String {
		final from = root + "/" + project.terms;
		if (project.terms == "" || !FileSystem.exists(from)) return "";

		final page = "https://github.com/" + project.github;

		var said = File.getContent(from);
		said = StringTools.replace(said, "{title}", project.title);
		said = StringTools.replace(said, "{releases}", page + "/releases");
		said = StringTools.replace(said, "{source}", page);

		final licence = root + "/LICENSE";
		if (FileSystem.exists(licence)) said += "\n" + File.getContent(licence);

		final into = root + "/" + project.output + "/package/terms.txt";
		File.saveContent(into, unwrapped(said));

		return into;
	}

	/**
		@param said Text wrapped by hand.
		@return The same text with each paragraph on one line, blank lines between them kept,
			and each line that starts with a dash or follows a colon kept on its own.
	**/
	static function unwrapped(said:String):String {
		final out = new StringBuf();
		var line = "";

		for (raw in StringTools.replace(said, "\r\n", "\n").split("\n")) {
			final held = StringTools.trim(raw);

			if (held == "") {
				if (line != "") out.add(line + "\r\n");
				out.add("\r\n");
				line = "";
				continue;
			}

			final alone = StringTools.startsWith(held, "- ") || StringTools.startsWith(held, "http")
				|| StringTools.endsWith(line, ":");

			if (line == "") {
				line = held;
			} else if (alone) {
				out.add(line + "\r\n");
				line = held;
			} else {
				line += " " + held;
			}
		}

		if (line != "") out.add(line + "\r\n");

		return out.toString();
	}

	/**
		@param code A language code.
		@return The installer component a language's face is listed under.
	**/
	static function component(code:String):String {
		return "languages\\" + StringTools.replace(code, "-", "").toLowerCase();
	}

	/**
		@param root The repository root.
		@param project What the build file declares.
		@param code A language code.
		@return What the language is called in English, from the reference language's own
			table, or the code where the table does not name it.
	**/
	static function called(root:String, project:Project, code:String):String {
		final from = root + "/" + project.languages + "/en-GB.json";
		if (!FileSystem.exists(from)) return code;

		try {
			final table:Dynamic = haxe.Json.parse(File.getContent(from));
			final said:Null<String> = Reflect.field(table, "languageName."
				+ StringTools.replace(code, "-", ""));

			return said == null ? code : said;
		} catch (e:Dynamic) {
			return code;
		}
	}

	static function installer(root:String, project:Project):Void {
		if (windows()) {
			inno(root, project);
			return;
		}

		if (system() == "mac") {
			bundle(root, project);
			return;
		}

		desktop(root, project);
	}

	/**
		Writes the Windows installer script and compiles it where Inno Setup is installed.

		The folder page is always shown, an update included, with the last folder filled
		in, and it says how much the install takes. A folder that already holds other
		files gets a folder of its own made inside it: uninstalling removes the whole
		install folder, and a program put straight into a shared folder would take
		everything else in there with it. Inno's own warning about an existing folder is
		off, because it asked whether to install there anyway just before this said it
		would not.

		A face only one language needs is a choice on the components page, ticked unless it
		is cleared. Clearing it leaves the face out, and the application downloads it again
		if that language is picked; running the installer again without it deletes the copy
		an earlier install left, so clearing one is what makes the install smaller rather
		than only what stops it growing.

		A face the application fetched for itself under the userdata folder goes with it,
		licence notice and all, since that copy is read in place of an installed one. Inno's
		own warning for a cleared component says nothing is uninstalled, so the message is
		given the text these entries earn.

		@param root The repository root.
		@param project What the build file declares.
	**/
	static function inno(root:String, project:Project):Void {
		final into = root + "/" + project.output + "/package/windows";
		staged(root, project, into, true);

		final script = root + "/" + project.output + "/package/" + project.short + ".iss";
		final out = new StringBuf();

		out.add("[Setup]\n");
		out.add("AppId={{" + identity(project) + "}\n");
		out.add("AppName=" + project.title + "\n");
		out.add("AppVersion=" + project.version + "\n");
		out.add("AppPublisher=" + project.company + "\n");
		out.add("AppSupportURL=https://github.com/" + project.github + "\n");
		out.add("DefaultDirName={autopf}\\" + project.title + "\n");
		out.add("DefaultGroupName=" + project.title + "\n");
		out.add("UninstallDisplayName=" + project.title + " " + project.version + "\n");
		out.add("UninstallDisplayIcon={app}\\" + project.short + ".exe\n");
		out.add("OutputDir=" + StringTools.replace(root + "/" + project.output + "/package",
			"/", "\\") + "\n");
		out.add("OutputBaseFilename=" + stamp(project)
			+ "-setup\n");
		out.add("Compression=lzma2/max\n");
		out.add("SolidCompression=yes\n");
		out.add("ArchitecturesInstallIn64BitMode=x64compatible\n");
		out.add("ArchitecturesAllowed=x64compatible\n");
		out.add("PrivilegesRequiredOverridesAllowed=dialog\n");
		out.add("AppMutex=" + project.short + "-running,Global\\" + project.short
			+ "-running\n");
		out.add("SetupMutex=" + project.short + "-setup,Global\\" + project.short
			+ "-setup\n");
		out.add("CloseApplications=yes\n");
		out.add("RestartApplications=no\n");
		final ico = native(root + "/" + project.appIcon) + "/" + project.short + ".ico";
		if (FileSystem.exists(ico)) out.add("SetupIconFile=" + StringTools.replace(ico,
			"/", "\\") + "\n");

		final agreed = termed(root, project);

		if (agreed != "") out.add("LicenseFile=" + StringTools.replace(agreed, "/", "\\") + "\n");

		out.add("WizardStyle=modern\n");
		out.add("DisableProgramGroupPage=yes\n");
		out.add("DisableDirPage=no\n");
		out.add("DirExistsWarning=no\n\n");

		out.add("[Messages]\n");
		out.add("DiskSpaceMBLabel=" + project.title + " takes [mb] MB of disk space.\n");
		out.add("DiskSpaceGBLabel=" + project.title + " takes [gb] GB of disk space.\n");
		out.add("ComponentsDiskSpaceMBLabel=" + project.title
			+ " takes [mb] MB of disk space with these languages.\n");
		out.add("ComponentsDiskSpaceGBLabel=" + project.title
			+ " takes [gb] GB of disk space with these languages.\n");
		out.add("WizardLicense=Terms of use and licence\n");
		out.add("LicenseLabel=Please read these terms before installing " + project.title + ".\n");
		out.add("LicenseLabel3=You need to accept the terms of use and the licence before "
			+ project.title + " is installed.\n");
		out.add("LicenseAccepted=I &accept the terms\n");
		out.add("LicenseNotAccepted=I &do not accept the terms\n");
		out.add("SelectComponentsLabel2=Every language is included. Clear one to leave out the"
			+ " font it needs; picking it later in " + project.title
			+ " downloads the font again.\n");
		out.add("NoUninstallWarning=These languages already have the font they need:%n%n%1%n"
			+ "Clearing one deletes that font, and any copy " + project.title
			+ " downloaded for it. Picking the language again downloads it once more.%n%n"
			+ "Would you like to continue anyway?\n\n");

		final optional = [for (face in project.faces) if (fetched(face)) face];

		out.add("[Types]\n");
		out.add("Name: \"full\"; Description: \"Every language\"\n");
		out.add("Name: \"custom\"; Description: \"Choose the languages\"; Flags: iscustom\n\n");

		out.add("[Components]\n");
		out.add("Name: \"core\"; Description: \"" + project.title
			+ ", with every language that needs no font of its own\"; Types: full custom;"
			+ " Flags: fixed\n");

		if (optional.length > 0) {
			out.add("Name: \"languages\"; Description: \"Languages that need a font of their own\";"
				+ " Types: full\n");

			for (face in optional) {
				out.add("Name: \"" + component(face.language) + "\"; Description: \""
					+ called(root, project, face.language) + "\"; Types: full\n");
			}
		}

		out.add("\n");

		final source = StringTools.replace(into, "/", "\\");

		out.add("[Files]\n");
		out.add("Source: \"" + source + "\\*\"; DestDir: \"{app}\"; Components: core;"
			+ " Excludes: \"" + [for (face in optional) "\\fonts\\" + face.name].join(",")
			+ "\"; Flags: recursesubdirs ignoreversion\n");

		for (face in optional) {
			out.add("Source: \"" + source + "\\fonts\\" + face.name + "\"; DestDir: \"{app}\\fonts\";"
				+ " Components: " + component(face.language) + "; Flags: ignoreversion\n");
		}

		out.add("\n");

		if (optional.length > 0) {
			final fetched = "{userdocs}\\" + project.title + "\\fonts\\";

			out.add("[InstallDelete]\n");

			for (face in optional) {
				final unwanted = "\"; Components: not " + component(face.language) + "\n";

				out.add("Type: files; Name: \"{app}\\fonts\\" + face.name + unwanted);
				out.add("Type: files; Name: \"" + fetched + face.name + unwanted);
				out.add("Type: files; Name: \"" + fetched + Icons.noticed(face) + unwanted);
			}

			out.add("\n");
		}

		out.add("[Icons]\n");
		out.add("Name: \"{group}\\" + project.title + "\"; Filename: \"{app}\\"
			+ project.short + ".exe\"\n");
		out.add("Name: \"{group}\\Uninstall " + project.title
			+ "\"; Filename: \"{uninstallexe}\"\n");
		out.add("Name: \"{autodesktop}\\" + project.title + "\"; Filename: \"{app}\\"
			+ project.short + ".exe\"; Tasks: desktopicon\n\n");

		out.add("[Tasks]\n");
		out.add("Name: \"desktopicon\"; Description: \"Create a desktop shortcut\"\n\n");

		final progid = project.short + ".project";
		final classes = "Software\\Classes\\";
		final suffix = "." + project.formatSuffix;

		out.add("[Registry]\n");

		out.add("Root: HKA; Subkey: \"" + classes + suffix + "\"; ValueType: string; "
			+ "ValueData: \"" + progid
			+ "\"; Flags: uninsdeletevalue uninsdeletekeyifempty\n");
		out.add("Root: HKA; Subkey: \"" + classes + suffix + "\"; ValueType: string; "
			+ "ValueName: \"Content Type\"; ValueData: \"" + project.formatMime
			+ "\"; Flags: uninsdeletevalue\n");
		out.add("Root: HKA; Subkey: \"" + classes + suffix + "\"; ValueType: string; "
			+ "ValueName: \"PerceivedType\"; ValueData: \"audio\"; Flags: uninsdeletevalue\n");
		out.add("Root: HKA; Subkey: \"" + classes + suffix + "\\OpenWithProgids\"; "
			+ "ValueType: string; ValueName: \"" + progid + "\"; ValueData: \"\"; "
			+ "Flags: uninsdeletevalue uninsdeletekeyifempty\n");

		out.add("Root: HKA; Subkey: \"" + classes + progid + "\"; ValueType: string; "
			+ "ValueData: \"" + project.formatName + "\"; Flags: uninsdeletekey\n");
		out.add("Root: HKA; Subkey: \"" + classes + progid + "\"; ValueType: string; "
			+ "ValueName: \"FriendlyTypeName\"; ValueData: \"" + project.formatName + "\"\n");
		out.add("Root: HKA; Subkey: \"" + classes + progid + "\\DefaultIcon\"; "
			+ "ValueType: string; ValueData: \"{app}\\" + project.short + ".exe,0\"\n");
		out.add("Root: HKA; Subkey: \"" + classes + progid + "\\shell\\open\\command\"; "
			+ "ValueType: string; ValueData: \"\"\"{app}\\" + project.short
			+ ".exe\"\" \"\"%1\"\"\"\n");

		out.add("Root: HKA; Subkey: \"" + classes + "Applications\\" + project.short
			+ ".exe\\SupportedTypes\"; ValueType: string; ValueName: \"" + suffix
			+ "\"; ValueData: \"\"; Flags: uninsdeletekey\n\n");

		out.add("[Run]\n");
		out.add("Filename: \"{app}\\" + project.short
			+ ".exe\"; Description: \"Start " + project.title
			+ "\"; Flags: nowait postinstall skipifsilent\n\n");

		out.add("[UninstallDelete]\n");
		out.add("Type: filesandordirs; Name: \"{app}\"\n\n");

		out.add("[Code]\n");
		out.add("var Keep: Boolean;\n\n");
		out.add("function Alone(): Boolean;\n");
		out.add("begin\n");
		out.add("  Result := True;\n");
		out.add("  while CheckForMutexes('" + project.short + "-running,Global\\" + project.short + "-running') do\n");
		out.add("  begin\n");
		out.add("    if MsgBox(\n");
		out.add("      '" + project.title + " is still running.' + #13#10 + #13#10 +\n");
		out.add("      'Close every window it has open, then click Retry.',\n");
		out.add("      mbError, MB_RETRYCANCEL) = IDCANCEL then\n");
		out.add("    begin\n");
		out.add("      Result := False;\n");
		out.add("      Exit;\n");
		out.add("    end;\n");
		out.add("  end;\n");
		out.add("end;\n\n");
		final title = pascal(project.title);
		final version = pascal(project.version);
		final uninstall = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{"
			+ identity(project) + "}_is1";

		out.add("function Installed(): String;\n");
		out.add("var Key, Held: String;\n");
		out.add("begin\n");
		out.add("  Result := '';\n");
		out.add("  Key := '" + uninstall + "';\n\n");
		out.add("  if RegQueryStringValue(HKLM, Key, 'DisplayVersion', Held) then\n");
		out.add("  begin\n");
		out.add("    Result := Held;\n");
		out.add("    Exit;\n");
		out.add("  end;\n\n");
		out.add("  if RegQueryStringValue(HKCU, Key, 'DisplayVersion', Held) then\n");
		out.add("    Result := Held;\n");
		out.add("end;\n\n");

		out.add("function Piece(var Said: String): Integer;\n");
		out.add("var At: Integer;\n");
		out.add("begin\n");
		out.add("  At := Pos('.', Said);\n\n");
		out.add("  if At = 0 then\n");
		out.add("  begin\n");
		out.add("    Result := StrToIntDef(Said, 0);\n");
		out.add("    Said := '';\n");
		out.add("    Exit;\n");
		out.add("  end;\n\n");
		out.add("  Result := StrToIntDef(Copy(Said, 1, At - 1), 0);\n");
		out.add("  Said := Copy(Said, At + 1, Length(Said));\n");
		out.add("end;\n\n");

		out.add("function Ranks(One, Two: String): Integer;\n");
		out.add("var Left, Right: Integer;\n");
		out.add("begin\n");
		out.add("  Result := 0;\n\n");
		out.add("  while (Result = 0) and ((One <> '') or (Two <> '')) do\n");
		out.add("  begin\n");
		out.add("    Left := Piece(One);\n");
		out.add("    Right := Piece(Two);\n\n");
		out.add("    if Left < Right then Result := -1\n");
		out.add("    else if Left > Right then Result := 1;\n");
		out.add("  end;\n");
		out.add("end;\n\n");

		out.add("function InitializeSetup(): Boolean;\n");
		out.add("var Held, Said: String;\n");
		out.add("begin\n");
		out.add("  Result := False;\n");
		out.add("  if not Alone() then Exit;\n\n");
		out.add("  Held := Installed();\n\n");
		out.add("  if Held = '' then\n");
		out.add("  begin\n");
		out.add("    Result := True;\n");
		out.add("    Exit;\n");
		out.add("  end;\n\n");
		out.add("  if Ranks(Held, '" + version + "') < 0 then\n");
		out.add("    Said := 'Update it to " + version + "?'\n");
		out.add("  else if Ranks(Held, '" + version + "') > 0 then\n");
		out.add("    Said := 'That is newer than the " + version
			+ " this installer carries.' + #13#10 + 'Replace it anyway?'\n");
		out.add("  else\n");
		out.add("    Said := 'Install " + version + " again over it?';\n\n");
		out.add("  Result := SuppressibleMsgBox(\n");
		out.add("    '" + title + " ' + Held + ' is already installed.' + #13#10 + #13#10 +\n");
		out.add("    Said + #13#10 + #13#10 +\n");
		out.add("    'Your projects, presets and settings are left alone either way.',\n");
		out.add("    mbConfirmation, MB_YESNO, IDYES) = IDYES;\n");
		out.add("end;\n\n");
		out.add("function Crowded(Where: String): Boolean;\n");
		out.add("var Found: TFindRec;\n");
		out.add("begin\n");
		out.add("  Result := False;\n");
		out.add("  if not FindFirst(AddBackslash(Where) + '*', Found) then Exit;\n\n");
		out.add("  try\n");
		out.add("    repeat\n");
		out.add("      if (Found.Name <> '.') and (Found.Name <> '..') then Result := True;\n");
		out.add("    until Result or not FindNext(Found);\n");
		out.add("  finally\n");
		out.add("    FindClose(Found);\n");
		out.add("  end;\n");
		out.add("end;\n\n");
		out.add("function NextButtonClick(CurPageID: Integer): Boolean;\n");
		out.add("var Where: String;\n");
		out.add("begin\n");
		out.add("  Result := True;\n");
		out.add("  if CurPageID <> wpSelectDir then Exit;\n\n");
		out.add("  Where := RemoveBackslashUnlessRoot(WizardDirValue());\n\n");
		out.add("  if FileExists(AddBackslash(Where) + '" + project.short + ".exe') then Exit;\n");
		out.add("  if not Crowded(Where) then Exit;\n\n");
		out.add("  WizardForm.DirEdit.Text := AddBackslash(Where) + '" + project.title + "';\n\n");
		out.add("  MsgBox(\n");
		out.add("    'That folder already has other files in it, so " + project.title
			+ " will go in a folder of its own inside it:' + #13#10 + #13#10 +\n");
		out.add("    WizardForm.DirEdit.Text + #13#10 + #13#10 +\n");
		out.add("    'Uninstalling removes the whole install folder, so nothing else should be"
			+ " in it.',\n");
		out.add("    mbInformation, MB_OK);\n\n");
		out.add("  Result := False;\n");
		out.add("end;\n\n");
		out.add("function InitializeUninstall(): Boolean;\n");
		out.add("begin\n");
		out.add("  if not Alone() then\n");
		out.add("  begin\n");
		out.add("    Result := False;\n");
		out.add("    Exit;\n");
		out.add("  end;\n\n");
		out.add("  Keep := MsgBox(\n");
		out.add("    'Keep your projects, presets and settings?' + #13#10 + #13#10 +\n");
		out.add("    'Yes  keeps everything in Documents\\" + project.title
			+ "' + #13#10 +\n");
		out.add("    'No   removes them along with the program.',\n");
		out.add("    mbConfirmation, MB_YESNO) = IDYES;\n");
		out.add("  Result := True;\n");
		out.add("end;\n\n");
		out.add("procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);\n");
		out.add("var Held, Where: String;\n");
		out.add("begin\n");
		out.add("  if CurUninstallStep <> usPostUninstall then Exit;\n\n");
		out.add("  Where := ExpandConstant('{app}');\n");
		out.add("  if DirExists(Where) then DelTree(Where, True, True, True);\n\n");
		out.add("  if Keep then Exit;\n\n");
		out.add("  Held := ExpandConstant('{userdocs}\\" + project.title + "');\n");
		out.add("  if DirExists(Held) then DelTree(Held, True, True, True);\n");
		out.add("end;\n");

		File.saveContent(script, out.toString());

		final iscc = toolAt("iscc", [
			"C:/Program Files (x86)/Inno Setup 6/ISCC.exe",
			"C:/Program Files/Inno Setup 6/ISCC.exe",
			"C:/Program Files (x86)/Inno Setup 5/ISCC.exe"
		]);

		if (iscc == "") {
			Sys.println("  " + pad("installer") + script.substr(root.length + 1)
				+ " is written; install Inno Setup and run iscc on it");
			return;
		}

		final made = Sys.command(iscc, ["/Q", script]);

		if (made != 0) {
			Sys.println("  " + pad("installer") + "iscc would not build " + script);
			return;
		}

		Sys.println("  " + pad("installer") + project.output + "/package/"
			+ stamp(project) + "-setup.exe");
	}

	/**
		@param said Any text.
		@return It as a Pascal string body, where the only thing to escape is the quote and
			the way to escape it is to write it twice. The installer script is Pascal, and a
			title carrying an apostrophe would otherwise end the string it sits in and leave
			the rest to be read as code.
	**/
	static function pascal(said:String):String {
		return StringTools.replace(said, "'", "''");
	}

	static function identity(project:Project):String {
		final said = project.company + "." + project.short + ".mdd";
		var held = 0x811C9DC5;

		for (i in 0...said.length) {
			held = held ^ said.charCodeAt(i);
			held = (held * 16777619) & 0x7FFFFFFF;
		}

		var mixed = held;
		mixed = (mixed ^ (mixed >> 13)) & 0x7FFFFFFF;
		mixed = (mixed * 1103515245 + 12345) & 0x7FFFFFFF;

		final left = StringTools.hex(held, 8);
		final right = StringTools.hex(mixed, 8);

		return left + "-" + right.substr(0, 4) + "-4" + right.substr(4, 3) + "-A"
			+ left.substr(0, 3) + "-" + left.substr(3, 5) + right.substr(0, 7);
	}

	static function bundle(root:String, project:Project):Void {
		final app = root + "/" + project.output + "/package/" + project.title + ".app";
		final inside = app + "/Contents";

		if (FileSystem.exists(app)) remove(app);

		tree(inside + "/MacOS");
		tree(inside + "/Resources");

		staged(root, project, inside + "/MacOS", true);

		final out = new StringBuf();
		out.add("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
		out.add("<plist version=\"1.0\">\n<dict>\n");
		out.add("\t<key>CFBundleName</key><string>" + project.title + "</string>\n");
		out.add("\t<key>CFBundleExecutable</key><string>" + project.short + "</string>\n");
		out.add("\t<key>CFBundleIdentifier</key><string>com." + project.company + "."
			+ project.short + "</string>\n");
		out.add("\t<key>CFBundleShortVersionString</key><string>" + project.version
			+ "</string>\n");
		out.add("\t<key>CFBundleIconFile</key><string>" + project.short + "</string>\n");
		out.add("\t<key>CFBundlePackageType</key><string>APPL</string>\n");
		out.add("\t<key>NSHighResolutionCapable</key><true/>\n");

		final suffixes = [project.formatSuffix, project.presetSuffix, project.bankSuffix];
		final names = [project.formatName, project.presetName, project.bankName];
		final mimes = [project.formatMime, project.presetMime, project.bankMime];

		out.add("\t<key>CFBundleDocumentTypes</key>\n\t<array>\n");

		for (at in 0...suffixes.length) {
			if (suffixes[at] == "") continue;

			out.add("\t\t<dict>\n");
			out.add("\t\t\t<key>CFBundleTypeName</key><string>" + names[at] + "</string>\n");
			out.add("\t\t\t<key>CFBundleTypeRole</key><string>" + (at == 0 ? "Editor" : "Viewer")
				+ "</string>\n");
			out.add("\t\t\t<key>LSHandlerRank</key><string>Owner</string>\n");
			out.add("\t\t\t<key>CFBundleTypeIconFile</key><string>" + project.short
				+ "</string>\n");
			out.add("\t\t\t<key>LSItemContentTypes</key>\n\t\t\t<array><string>com."
				+ project.company + "." + project.short + "." + suffixes[at] + "</string></array>\n");
			out.add("\t\t</dict>\n");
		}

		out.add("\t</array>\n");
		out.add("\t<key>UTExportedTypeDeclarations</key>\n\t<array>\n");

		for (at in 0...suffixes.length) {
			if (suffixes[at] == "") continue;

			out.add("\t\t<dict>\n");
			out.add("\t\t\t<key>UTTypeIdentifier</key><string>com." + project.company + "."
				+ project.short + "." + suffixes[at] + "</string>\n");
			out.add("\t\t\t<key>UTTypeDescription</key><string>" + names[at] + "</string>\n");
			out.add("\t\t\t<key>UTTypeConformsTo</key>\n\t\t\t<array><string>public.data</string>"
				+ (at == 0 ? "<string>public.zip-archive</string>" : "") + "</array>\n");
			out.add("\t\t\t<key>UTTypeTagSpecification</key>\n\t\t\t<dict>\n");
			out.add("\t\t\t\t<key>public.filename-extension</key>\n\t\t\t\t<array><string>"
				+ suffixes[at] + "</string></array>\n");
			out.add("\t\t\t\t<key>public.mime-type</key>\n\t\t\t\t<array><string>"
				+ mimes[at] + "</string></array>\n");
			out.add("\t\t\t</dict>\n\t\t</dict>\n");
		}

		out.add("\t</array>\n");

		out.add("</dict>\n</plist>\n");

		File.saveContent(inside + "/Info.plist", out.toString());

		final image = root + "/" + project.output + "/package/"
			+ stamp(project) + ".dmg";

		if (FileSystem.exists(image)) FileSystem.deleteFile(image);

		if (!tool("hdiutil", ["help"])) {
			Sys.println("  " + pad("installer") + app.substr(root.length + 1)
				+ " is built; hdiutil is what turns it into a dmg");
			return;
		}

		final made = Sys.command("hdiutil", ["create", "-volname", project.title, "-srcfolder",
			app, "-ov", "-format", "UDZO", image]);

		Sys.println("  " + pad("installer") + (made == 0
			? image.substr(root.length + 1) : "hdiutil would not make a dmg"));
	}

	/**
		The sizes a desktop's icon theme is given, each as its own picture.
	**/
	static final THEMED:Array<Int> = [16, 24, 32, 48, 64, 128, 256, 512];

	/**
		Puts the pictures the install script gives the desktop's icon theme beside it, and only
		those. Nothing else reads them: the window icon and the program's own are built into the
		binary, and a file association points at the program.

		@param root The repository.
		@param project What the build file declares.
		@param into The package folder.
	**/
	static function themed(root:String, project:Project, into:String):Void {
		final from = root + "/" + project.appIcon;
		if (!FileSystem.exists(from)) return;

		tree(into + "/appicon");

		for (size in THEMED) {
			final name = project.short + "-" + size + ".png";
			if (FileSystem.exists(from + "/" + name)) copyFile(from + "/" + name, into + "/appicon/" + name);
		}
	}

	static function desktop(root:String, project:Project):Void {
		final into = root + "/" + project.output + "/package/"
			+ stamp(project) + "-installer";

		staged(root, project, into, true);
		themed(root, project, into);

		final out = new StringBuf();
		out.add("[Desktop Entry]\n");
		out.add("Type=Application\n");
		out.add("Name=" + project.title + "\n");
		out.add("Comment=" + project.description + "\n");
		out.add("Exec=" + project.short + "\n");
		out.add("Terminal=false\n");
		out.add("Icon=" + project.short + "\n");
		out.add("Categories=AudioVideo;Audio;Music;\n");
		out.add("MimeType=" + project.formatMime + ";\n");

		File.saveContent(into + "/" + project.short + ".desktop", out.toString());

		final mime = new StringBuf();
		mime.add("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
		mime.add("<mime-info xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\">\n");
		mime.add("\t<mime-type type=\"" + project.formatMime + "\">\n");
		mime.add("\t\t<comment>" + project.formatName + "</comment>\n");
		mime.add("\t\t<glob pattern=\"*." + project.formatSuffix + "\"/>\n");
		mime.add("\t\t<icon name=\"" + project.short + "\"/>\n");
		mime.add("\t</mime-type>\n");
		mime.add("</mime-info>\n");

		File.saveContent(into + "/" + project.short + ".xml", mime.toString());

		final out2 = new StringBuf();
		out2.add("#!/usr/bin/env sh\n");
		out2.add("set -e\n");
		out2.add("HERE=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\n");
		out2.add("PREFIX=\"${PREFIX:-$HOME/.local}\"\n");
		out2.add("mkdir -p \"$PREFIX/lib/" + project.short + "\" \"$PREFIX/bin\" "
			+ "\"$PREFIX/share/applications\"\n");
		out2.add("cp -r \"$HERE\"/* \"$PREFIX/lib/" + project.short + "/\"\n");
		out2.add("ln -sf \"$PREFIX/lib/" + project.short + "/" + project.short
			+ "\" \"$PREFIX/bin/" + project.short + "\"\n");
		out2.add("cp \"$HERE/" + project.short + ".desktop\" "
			+ "\"$PREFIX/share/applications/\"\n");
		for (size in THEMED) {
			final where = "$PREFIX/share/icons/hicolor/" + size + "x" + size + "/apps";
			out2.add("mkdir -p \"" + where + "\"\n");
			out2.add("cp \"$HERE/appicon/" + project.short + "-" + size + ".png\" "
				+ "\"" + where + "/" + project.short + ".png\"\n");
		}

		out2.add("mkdir -p \"$PREFIX/share/mime/packages\"\n");
		out2.add("cp \"$HERE/" + project.short + ".xml\" \"$PREFIX/share/mime/packages/\"\n");
		out2.add("command -v update-mime-database >/dev/null 2>&1 && "
			+ "update-mime-database \"$PREFIX/share/mime\" || true\n");
		out2.add("command -v update-desktop-database >/dev/null 2>&1 && "
			+ "update-desktop-database \"$PREFIX/share/applications\" || true\n");
		out2.add("echo \"installed to $PREFIX\"\n");

		File.saveContent(into + "/install.sh", out2.toString());

		final out3 = new StringBuf();
		out3.add("#!/usr/bin/env sh\n");
		out3.add("set -e\n");
		out3.add("PREFIX=\"${PREFIX:-$HOME/.local}\"\n");
		out3.add("printf 'Keep projects, presets and settings? [Y/n] '\n");
		out3.add("read KEEP\n");
		out3.add("rm -rf \"$PREFIX/lib/" + project.short + "\"\n");
		out3.add("rm -f \"$PREFIX/bin/" + project.short + "\"\n");
		out3.add("rm -f \"$PREFIX/share/applications/" + project.short + ".desktop\"\n");
		out3.add("rm -f \"$PREFIX/share/mime/packages/" + project.short + ".xml\"\n");
		out3.add("command -v update-mime-database >/dev/null 2>&1 && "
			+ "update-mime-database \"$PREFIX/share/mime\" || true\n");
		out3.add("case \"$KEEP\" in\n");
		out3.add("  [Nn]*) rm -rf \"$HOME/Documents/" + project.title + "\" ;;\n");
		out3.add("  *) echo \"kept $HOME/Documents/" + project.title + "\" ;;\n");
		out3.add("esac\n");
		out3.add("echo \"removed from $PREFIX\"\n");

		File.saveContent(into + "/uninstall.sh", out3.toString());

		final archive = into + ".tar.gz";
		if (FileSystem.exists(archive)) FileSystem.deleteFile(archive);

		final held = stamp(project) + "-installer";
		final made = archived(root + "/" + project.output + "/package", held, held + ".tar.gz");

		Sys.println("  " + pad("installer") + (made == 0
			? archive.substr(root.length + 1) + " with install.sh and a desktop entry"
			: "tar would not archive " + into));
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

	/**
		Fetches a tagged source archive from GitHub into `vendor/`.

		A GitHub archive unpacks into one folder named after the repository and the tag, and
		the two are not joined the same way for every repository: `v1.17.0` of libvpx unpacks
		as `libvpx-1.17.0` and `libwebm-1.0.0.32` of libwebm as `libwebm-libwebm-1.0.0.32`. So
		the folder is found by looking rather than by building its name.

		@param vendor The vendor folder.
		@param repository The owner and the repository, separated by a slash.
		@param tag The tag to fetch.
		@param into The folder under `vendor/` to put it in.
		@return Whether it arrived.
	**/
	static function github(vendor:String, repository:String, tag:String, into:String):Bool {
		final name = repository.split("/").pop();
		final archive = vendor + "/." + name + ".tar.gz";
		final staging = vendor + "/." + name;

		if (!download("https://github.com/" + repository + "/archive/refs/tags/" + tag + ".tar.gz",
				archive)) {
			return false;
		}

		if (FileSystem.exists(staging)) remove(staging);
		FileSystem.createDirectory(staging);
		unpack(archive, staging);

		var unpacked = "";

		for (entry in FileSystem.readDirectory(staging)) {
			if (FileSystem.isDirectory(staging + "/" + entry)) unpacked = staging + "/" + entry;
		}

		if (unpacked == "") {
			remove(staging);
			return false;
		}

		final where = vendor + "/" + into;
		if (FileSystem.exists(where)) remove(where);

		copyTree(unpacked, where);

		FileSystem.deleteFile(archive);
		remove(staging);

		return true;
	}

	static function xiph(vendor:String, name:String, version:String, into:String):Bool {
		final archive = vendor + "/." + name + ".tar.gz";
		final staging = vendor + "/." + name;

		final url = "https://github.com/xiph/" + name + "/archive/refs/tags/v" + version
			+ ".tar.gz";

		if (!download(url, archive)) return false;

		if (FileSystem.exists(staging)) remove(staging);
		FileSystem.createDirectory(staging);
		unpack(archive, staging);

		final unpacked = staging + "/" + name + "-" + version;

		if (!FileSystem.exists(unpacked)) {
			remove(staging);
			return false;
		}

		final where = vendor + "/" + into;
		if (FileSystem.exists(where)) remove(where);

		copyTree(unpacked, where);

		FileSystem.deleteFile(archive);
		remove(staging);

		if (name == "ogg") typed(where);
		return true;
	}

	static function typed(where:String):Void {
		final out = new StringBuf();

		out.add("#ifndef __CONFIG_TYPES_H__\n");
		out.add("#define __CONFIG_TYPES_H__\n\n");
		out.add("#include <stdint.h>\n\n");
		out.add("typedef int16_t ogg_int16_t;\n");
		out.add("typedef uint16_t ogg_uint16_t;\n");
		out.add("typedef int32_t ogg_int32_t;\n");
		out.add("typedef uint32_t ogg_uint32_t;\n");
		out.add("typedef int64_t ogg_int64_t;\n");
		out.add("typedef uint64_t ogg_uint64_t;\n\n");
		out.add("#endif\n");

		File.saveContent(where + "/include/ogg/config_types.h", out.toString());
	}

	static function nuked(vendor:String):Bool {
		final into = vendor + "/Nuked-OPN2";
		tree(into);

		final sha = resolved("nukeykt", "Nuked-OPN2", "master");
		final base = "https://raw.githubusercontent.com/nukeykt/Nuked-OPN2/"
			+ (sha == "" ? "master" : sha);

		if (!download(base + "/ym3438.c", into + "/ym3438.c")) return false;
		if (!download(base + "/ym3438.h", into + "/ym3438.h")) return false;
		download(base + "/LICENSE", into + "/LICENSE");

		File.saveContent(into + "/COMMIT", sha == "" ? "master, unpinned" : sha);
		return true;
	}

	static function qlementine(vendor:String, project:Project):Bool {
		final into = vendor + "/qlementine/16";

		final sha = resolved("oclero", "qlementine-icons", "master");
		final base = "https://raw.githubusercontent.com/oclero/qlementine-icons/"
			+ (sha == "" ? "master" : sha);

		final art = base + "/sources/resources/icons/16/";
		var missed = 0;

		for (icon in project.icons) {
			final at = icon.from.indexOf(":");
			if (at < 0 || icon.from.substr(0, at) != "qlementine") continue;

			final tail = icon.from.substr(at + 1);
			final where = into + "/" + tail + ".svg";

			if (FileSystem.exists(where)) continue;

			tree(haxe.io.Path.directory(where));
			if (!download(art + tail + ".svg", where)) missed++;
		}

		download(base + "/LICENSE", vendor + "/qlementine/LICENSE");
		File.saveContent(vendor + "/qlementine/COMMIT",
			sha == "" ? "master, unpinned" : sha);

		return missed == 0;
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

	static function fonts(root:String, project:Project):Bool {
		final into = root + "/" + project.typefacePath;
		tree(into);

		final licence = into + "/.LICENSE.b64";

		if (download("https://go.googlesource.com/image/+/master/LICENSE?format=TEXT", licence)) {
			File.saveBytes(into + "/LICENSE", decode(licence));
			FileSystem.deleteFile(licence);
		}

		return pairings(root, project);
	}

	static function pairings(root:String, project:Project):Bool {
		final into = root + "/" + project.typefacePath;
		final ofl = "https://raw.githubusercontent.com/google/fonts/main/ofl/";
		final go = "https://go.googlesource.com/image/+/master/font/gofont/ttfs/";

		var every = true;

		for (face in project.faces) {
			final held = into + "/" + face.name;
			if (FileSystem.exists(held)) continue;

			final at = face.from.indexOf(":");
			if (at < 0) continue;

			final kind = face.from.substr(0, at);
			final tail = face.from.substr(at + 1);

			if (kind == "go") {
				final coded = into + "/." + face.name + ".b64";

				if (!download(go + tail + "?format=TEXT", coded)) {
					every = false;
					continue;
				}

				File.saveBytes(held, decode(coded));
				FileSystem.deleteFile(coded);
				continue;
			}

			final base = face.commit == "" ? ofl
				: "https://raw.githubusercontent.com/google/fonts/" + face.commit + "/ofl/";

			if (!download(base + encoded(tail), held)) {
				every = false;
				continue;
			}

			final family = tail.split("/")[0];
			final notice = into + "/OFL-" + family + ".txt";

			if (!FileSystem.exists(notice)) download(ofl + family + "/OFL.txt", notice);
		}

		return every;
	}

	static function encoded(name:String):String {
		return StringTools.replace(StringTools.replace(name, "[", "%5B"), "]", "%5D");
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

	static function alike(from:String, to:String):Bool {
		if (!FileSystem.exists(to)) return false;

		try {
			final source = FileSystem.stat(from);
			final held = FileSystem.stat(to);

			return held.size == source.size
				&& held.mtime.getTime() >= source.mtime.getTime();
		} catch (e:Dynamic) {
			return false;
		}
	}

	static function runnable(path:String):Void {
		if (windows() || !FileSystem.exists(path)) return;

		Sys.command("chmod", ["+x", path]);
	}

	static function copyFile(from:String, to:String):Void {
		if (alike(from, to)) return;

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
