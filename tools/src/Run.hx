import sys.FileSystem;
import sys.io.File;

class Run {
	static inline final SDL_VERSION = "3.4.14";
	static inline final MINIAUDIO_COMMIT = "9634bedb5b5a2ca38c1ee7108a9358a4e233f14d";

	static inline final OGG_VERSION = "1.3.5";
	static inline final VORBIS_VERSION = "1.3.7";
	static inline final OPUS_VERSION = "1.5.2";


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
			case "display": display(root, project, true);
			case "build": build(root, project, args.slice(1), debug);
			case "run": start(root, project, args.slice(1), debug);
			case "gate": gate(root, project, args.slice(1));
			case "package": packaged(root, project, args.slice(1));
			case "clean": clean(root, project);
			case "help", "--help", "-h": usage(project);
			case unknown:
				Sys.println("mdd: no command called '" + unknown + "'");
				usage(project);
				Sys.exit(1);
		}
	}

	static function read(root:String, debug:Bool):Project {
		final path = root + "/mdd.xml";

		if (!FileSystem.exists(path)) {
			Sys.println("mdd: no mdd.xml beside the command");
			Sys.exit(1);
		}

		try {
			return new Project(path, system(), debug);
		} catch (e:Dynamic) {
			Sys.println("mdd: mdd.xml would not read: " + e);
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
		Sys.println("  mdd run -debug        the same, carrying the hxcpp debug server on"
			+ " 6972");
		Sys.println("  mdd gate [name]       every check, in order, or one by name");
		Sys.println("  mdd package [kind]    portable, installer, or both");
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
				case "fonts": fonts(root, project);
				case "Nuked-OPN2": nuked(vendor);
				case "qlementine": qlementine(vendor, project);
				case "libogg": xiph(vendor, "ogg", OGG_VERSION, "libogg");
				case "libvorbis": xiph(vendor, "vorbis", VORBIS_VERSION, "libvorbis");
				case "libopus": xiph(vendor, "opus", OPUS_VERSION, "libopus");
				case _: false;
			}

			if (!done || !FileSystem.exists(vendor + "/" + source.present)) {
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
		out.add("\tpublic static inline final GITHUB = \"" + project.github + "\";\n");
		
		out.add("\tpublic static inline final VERSION = \"" + project.version + "\";\n");
		out.add("\tpublic static inline final WIDTH = " + project.windowWidth + ";\n");
		out.add("\tpublic static inline final HEIGHT = " + project.windowHeight + ";\n");
		out.add("\tpublic static inline final LEAST_WIDTH = " + project.leastWidth + ";\n");
		out.add("\tpublic static inline final LEAST_HEIGHT = " + project.leastHeight + ";\n");
		out.add("\tpublic static inline final VSYNC = " + project.vsync + ";\n");
		out.add("\tpublic static inline final RESIZABLE = " + project.resizable + ";\n");
		out.add("\tpublic static inline final HIGH_DPI = " + project.highDpi + ";\n");
		out.add("\tpublic static inline final SPOKEN = \"" + spoken.join(",") + "\";\n");
		out.add("	public static inline final SUFFIX = \"" + project.formatSuffix + "\";
");
		out.add("	public static inline final FORMAT = \"" + project.formatName + "\";
");
		out.add("	public static inline final MIME = \"" + project.formatMime + "\";
");
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

	static function nativeXml(root:String, project:Project):String {
		final into = root + "/" + project.output + "/build";
		tree(into);

		final flags = new StringBuf();
		for (path in project.includes) {
			flags.add("\t\t<compilerflag value=\"-I" + native(root + "/" + path) + "\" />\n");
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
					for (name in grown(root, grove)) {
						out.add("\t\t<file name=\"" + name + "\" />\n");
					}
				}

				if (script != "") out.add("\t\t<file name=\"" + script + "\" />\n");
			}

			out.add("\t</files>\n");
		}

		out.add("\t<target id=\"haxe\">\n");

		for (link in project.links) {
			out.add("\t\t<lib name=\""
				+ (loose(link) ? link : native(root + "/" + link))
				+ "\" />\n");
		}

		out.add("\t\t<files id=\"mdd_native\" />\n");
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
		out.add("      VALUE \"FileDescription\", \"" + project.description + "\"\n");
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
		Icons.named(project, root + "/" + project.generated);
		Icons.typefaces(project, root + "/" + project.generated);
		final xml = nativeXml(root, project);

		for (one in project.targets) {
			final name = one.id == project.targets[0].id
				? "completion.hxml" : "completion-" + one.id + ".hxml";

			final args = compiled(root, project, one.id, spoken, xml, false);
			args.push("--no-output");

			written(root, name, one.id, args, loud);
		}

		written(root, "completion-tools.hxml", "tools",
			["-main", "Run", "-cp", root + "/tools/src", "--interp", "--no-output"], loud);
	}

	static function written(root:String, name:String, target:String, args:Array<String>,
			loud:Bool):Void {
		final out = new StringBuf();

		out.add("# The " + target + " arguments the editor's Haxe language server reads.
");
		out.add("# Generated by mdd from mdd.xml. Edit that file: this one is written again.
");
		out.add("#
");
		out.add("# Nothing builds from here. mdd build reads the same options and adds the
");
		out.add("# resources and the output this file leaves out.

");

		var index = 0;

		while (index < args.length) {
			final flag = args[index++];
			out.add(flag);

			if (index < args.length && !StringTools.startsWith(args[index], "-")) {
				out.add(" ");
				out.add(relative(root, args[index++]));
			}

			out.add("
");
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

		return args;
	}

	static function built(root:String, project:Project, target:String, debug:Bool):Void {
		if (windows() && !FileSystem.exists(root + "/" + project.pathOf("SDL3PATH")
				+ "/lib/SDL3.lib")) {
			Sys.println("mdd: SDL3 is missing from vendor/. Run: mdd setup");
			Sys.exit(1);
		}

		final spoken = languages(root, project);

		configure(root, project, spoken);
		Icons.named(project, root + "/" + project.generated);
		Icons.typefaces(project, root + "/" + project.generated);
		Icons.built(root, project, root + "/" + project.output + "/icons", false);

		final xml = nativeXml(root, project);

		final args = compiled(root, project, target, spoken, xml, true);
		if (debug) args.push("-debug");

		display(root, read(root, false), false);

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

	static function gate(root:String, project:Project, args:Array<String>):Void {
		if (exeOf(root, project, "gate") == "") built(root, project, "gate", false);

		if (args.length == 0 || args[0] == "chip") opn2(root, project);

		final shipped = ship(root, project, "gate");
		if (shipped == "") {
			Sys.println("mdd: the gate is not built");
			Sys.exit(1);
		}

		Sys.exit(Sys.command(shipped, args.concat(["--root", root])));
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

	static function staged(root:String, project:Project, into:String):String {
		if (FileSystem.exists(into)) remove(into);
		tree(into);

		final bin = root + "/" + project.output + "/bin";

		for (entry in FileSystem.readDirectory(bin)) {
			final from = bin + "/" + entry;
			if (FileSystem.isDirectory(from)) continue;

			final held = entry.toLowerCase();
			if (StringTools.endsWith(held, ".pdb") || StringTools.endsWith(held, ".ilk")) continue;
			if (StringTools.startsWith(held, "gate")) continue;
			if (StringTools.startsWith(held, "opn2")) continue;

			copyFile(from, into + "/" + entry);
		}

		final appIcon = root + "/" + project.appIcon;

		if (FileSystem.exists(appIcon)) {
			tree(into + "/appicon");

			for (entry in FileSystem.readDirectory(appIcon)) {
				if (entry == "sheet.png") continue;
				if (!StringTools.endsWith(entry, ".png") && !StringTools.endsWith(entry, ".ico"))
					continue;

				copyFile(appIcon + "/" + entry, into + "/appicon/" + entry);
			}
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

		final fonts = root + "/" + project.pathOf("FONTPATH");
		tree(into + "/fonts");

		for (entry in FileSystem.readDirectory(fonts)) {
			final held = entry.toLowerCase();

			if (!StringTools.endsWith(held, ".ttf") && !StringTools.endsWith(held, ".txt")
				&& entry != "LICENSE") {
				continue;
			}

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
		final name = project.short + "-" + project.version + "-" + system() + "-portable";
		final into = root + "/" + project.output + "/package/" + name;

		staged(root, project, into);

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

	static function inno(root:String, project:Project):Void {
		final into = root + "/" + project.output + "/package/windows";
		staged(root, project, into);

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
		out.add("OutputBaseFilename=" + project.short + "-" + project.version
			+ "-windows-setup\n");
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

		out.add("WizardStyle=modern\n");
		out.add("DisableProgramGroupPage=yes\n\n");

		out.add("[Files]\n");
		out.add("Source: \"" + StringTools.replace(into, "/", "\\")
			+ "\\*\"; DestDir: \"{app}\"; Flags: recursesubdirs ignoreversion\n\n");

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
		out.add("function InitializeSetup(): Boolean;\n");
		out.add("begin\n");
		out.add("  Result := Alone();\n");
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

		Sys.println("  " + pad("installer") + project.output + "/package/" + project.short + "-"
			+ project.version + "-windows-setup.exe");
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

		staged(root, project, inside + "/MacOS");

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

		out.add("\t<key>CFBundleDocumentTypes</key>\n\t<array>\n\t\t<dict>\n");
		out.add("\t\t\t<key>CFBundleTypeName</key><string>" + project.formatName
			+ "</string>\n");
		out.add("\t\t\t<key>CFBundleTypeRole</key><string>Editor</string>\n");
		out.add("\t\t\t<key>LSHandlerRank</key><string>Owner</string>\n");
		out.add("\t\t\t<key>CFBundleTypeIconFile</key><string>" + project.short
			+ "</string>\n");
		out.add("\t\t\t<key>LSItemContentTypes</key>\n\t\t\t<array><string>com."
			+ project.company + "." + project.short + "." + project.formatSuffix
			+ "</string></array>\n");
		out.add("\t\t</dict>\n\t</array>\n");

		out.add("\t<key>UTExportedTypeDeclarations</key>\n\t<array>\n\t\t<dict>\n");
		out.add("\t\t\t<key>UTTypeIdentifier</key><string>com." + project.company + "."
			+ project.short + "." + project.formatSuffix + "</string>\n");
		out.add("\t\t\t<key>UTTypeDescription</key><string>" + project.formatName
			+ "</string>\n");
		out.add("\t\t\t<key>UTTypeConformsTo</key>\n\t\t\t<array>"
			+ "<string>public.data</string><string>public.zip-archive</string></array>\n");
		out.add("\t\t\t<key>UTTypeTagSpecification</key>\n\t\t\t<dict>\n");
		out.add("\t\t\t\t<key>public.filename-extension</key>\n\t\t\t\t<array><string>"
			+ project.formatSuffix + "</string></array>\n");
		out.add("\t\t\t\t<key>public.mime-type</key>\n\t\t\t\t<array><string>"
			+ project.formatMime + "</string></array>\n");
		out.add("\t\t\t</dict>\n\t\t</dict>\n\t</array>\n");

		out.add("</dict>\n</plist>\n");

		File.saveContent(inside + "/Info.plist", out.toString());

		final image = root + "/" + project.output + "/package/" + project.short + "-"
			+ project.version + ".dmg";

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

	static function desktop(root:String, project:Project):Void {
		final into = root + "/" + project.output + "/package/" + project.short + "-"
			+ project.version;

		staged(root, project, into);

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
		for (size in [16, 24, 32, 48, 64, 128, 256, 512]) {
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

		final held = project.short + "-" + project.version;
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

		out.add("#ifndef __CONFIG_TYPES_H__
");
		out.add("#define __CONFIG_TYPES_H__

");
		out.add("#include <stdint.h>

");
		out.add("typedef int16_t ogg_int16_t;
");
		out.add("typedef uint16_t ogg_uint16_t;
");
		out.add("typedef int32_t ogg_int32_t;
");
		out.add("typedef uint32_t ogg_uint32_t;
");
		out.add("typedef int64_t ogg_int64_t;
");
		out.add("typedef uint64_t ogg_uint64_t;

");
		out.add("#endif
");

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

			if (!download(ofl + encoded(tail), held)) {
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
