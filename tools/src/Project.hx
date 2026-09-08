import sys.io.File;

typedef Target = {
	final id:String;
	final main:String;
	final sources:Array<String>;
}

typedef Vendor = {
	final name:String;
	final present:String;
	final system:String;
	final flag:String;
	final size:String;
	final about:String;
}

typedef Named = {
	final name:String;
	final value:String;
}

typedef Icon = {
	final name:String;
	final from:String;
	final group:String;
}

typedef Toolchain = {
	var name:String;
	var probe:String;
	var about:String;
}

typedef Face = {
	final name:String;
	final from:String;
}

typedef Typeface = {
	final name:String;
	final sans:String;
	final mono:String;
}

class Project {
	public var title(default, null):String = "mdd";
	public var short(default, null):String = "mdd";
	public var company(default, null):String = "";
	public var github(default, null):String = "";
	public var discord(default, null):String = "";
	public var discordCover(default, null):String = "";
	public var discordPlaying(default, null):String = "";
	public var discordStopped(default, null):String = "";
	public var discordWorking(default, null):String = "";
	public var version(default, null):String = "0.0.0";
	public var description(default, null):String = "";

	public var formatSuffix(default, null):String = "";
	public var formatName(default, null):String = "";
	public var formatMime(default, null):String = "";

	public var windowWidth(default, null):Int = 1280;
	public var windowHeight(default, null):Int = 800;
	public var leastWidth(default, null):Int = 640;
	public var leastHeight(default, null):Int = 480;
	public var vsync(default, null):Bool = true;
	public var resizable(default, null):Bool = true;
	public var highDpi(default, null):Bool = true;

	public var sources(default, null):Array<String> = [];
	public var generated(default, null):String = "export/haxe";
	public var languages(default, null):String = "assets/lang";
	public var appIcon(default, null):String = "assets/icon";

	public var typefacePath(default, null):String = "vendor/fonts";
	public var faces(default, null):Array<Face> = [];
	public var typefaces(default, null):Array<Typeface> = [];
	public var fallbacks(default, null):Array<String> = [];

	public var iconPath(default, null):String = "assets/icons";
	public var iconSizes(default, null):Array<Int> = [];
	public var iconFrom(default, null):Array<Named> = [];
	public var icons(default, null):Array<Icon> = [];
	public var output(default, null):String = "export";

	public var targets(default, null):Array<Target> = [];
	public var defines(default, null):Array<String> = [];
	public var dce(default, null):String = "";
	public var libraries(default, null):Array<String> = [];
	public var vendors(default, null):Array<Vendor> = [];
	public var paths(default, null):Array<Named> = [];
	public var includes(default, null):Array<String> = [];
	public var links(default, null):Array<String> = [];
	public var ships(default, null):Array<String> = [];

	public var nativePath(default, null):String = "native";
	public var nativeFiles(default, null):Array<String> = [];
	public var nativeTrees(default, null):Array<Grove> = [];
	public var nativeFlags(default, null):Array<String> = [];

	public var toolchains(default, null):Array<Toolchain> = [];
	public var toolchain(default, null):String = "";

	final os:String;
	final debug:Bool;

	public function new(path:String, os:String, debug:Bool, toolchain:String = "") {
		this.os = os;
		this.debug = debug;
		this.toolchain = toolchain;

		final root = Xml.parse(File.getContent(path)).firstElement();
		if (root == null) throw "mdd.xml has no root element";

		for (node in root.elements()) {
			if (node.nodeName == "path" && allowed(node)) read(node);
		}

		for (node in root.elements()) {
			if (node.nodeName != "path") read(node);
		}

		for (i in 0...paths.length) {
			paths[i] = { name: paths[i].name, value: fill(paths[i].value) };
		}
		for (i in 0...includes.length) includes[i] = fill(includes[i]);
		for (i in 0...links.length) links[i] = fill(links[i]);
		for (i in 0...ships.length) ships[i] = fill(ships[i]);
	}

	function read(node:Xml):Void {
		if (!allowed(node)) return;

		switch (node.nodeName) {
			case "meta":
				title = has(node, "title") ? node.get("title") : title;
				short = has(node, "short") ? node.get("short") : short;
				company = has(node, "company") ? node.get("company") : company;
				version = has(node, "version") ? node.get("version") : version;
				description = has(node, "description") ? node.get("description") : description;

			case "format":
				formatSuffix = node.get("suffix");
				formatName = node.get("name");
				formatMime = node.get("mime");

			case "toolchains":
				for (held in node.elements()) {
					if (held.nodeName != "toolchain" || !allowed(held)) continue;

					toolchains.push({
						name: held.get("name"),
						probe: has(held, "probe") ? held.get("probe") : "",
						about: has(held, "about") ? held.get("about") : ""
					});
				}

			case "update":
				github = has(node, "github") ? node.get("github") : github;

			case "presence":
				discord = has(node, "discord") ? node.get("discord") : discord;
				discordCover = has(node, "cover") ? node.get("cover") : discordCover;
				discordPlaying = has(node, "playing") ? node.get("playing") : discordPlaying;
				discordStopped = has(node, "stopped") ? node.get("stopped") : discordStopped;
				discordWorking = has(node, "working") ? node.get("working") : discordWorking;

			case "window":
				windowWidth = number(node, "width", windowWidth);
				windowHeight = number(node, "height", windowHeight);
				leastWidth = number(node, "least-width", leastWidth);
				leastHeight = number(node, "least-height", leastHeight);
				vsync = flag(node, "vsync", vsync);
				resizable = flag(node, "resizable", resizable);
				highDpi = flag(node, "high-dpi", highDpi);

			case "source":
				sources.push(node.get("path"));

			case "generated":
				generated = node.get("path");

			case "languages":
				languages = node.get("path");

			case "appicon":
				appIcon = node.get("path");

			case "typefaces":
				typefacePath = node.get("path");

				for (held in node.elements()) {
					if (!allowed(held)) continue;

					switch (held.nodeName) {
						case "face":
							faces.push({name: held.get("name"), from: held.get("from")});

						case "typeface":
							typefaces.push({name: held.get("name"), sans: held.get("sans"),
								mono: held.get("mono")});

						case "fallback":
							fallbacks.push(held.get("name"));

						case _:
					}
				}

			case "icons":
				iconPath = node.get("path");

				for (part in node.get("sizes").split(",")) {
					final held = Std.parseInt(StringTools.trim(part));
					if (held != null && held > 0) iconSizes.push(held);
				}

				for (held in node.elements()) {
					if (!allowed(held)) continue;

					switch (held.nodeName) {
						case "from":
							iconFrom.push({name: held.get("name"), value: held.get("path")});

						case "group":
							for (one in held.elements()) {
								if (one.nodeName != "icon" || !allowed(one)) continue;
								drawn(one, held.get("name"));
							}

						case "icon":
							drawn(held, "");

						case _:
					}
				}

			case "output":
				output = node.get("path");

			case "target":
				final own:Array<String> = [];
				for (child in node.elements()) {
					if (child.nodeName == "source" && allowed(child)) own.push(child.get("path"));
				}
				targets.push({ id: node.get("id"), main: node.get("main"), sources: own });

			case "library":
				libraries.push(node.get("name"));

			case "dce":
				dce = node.get("value");

			case "define":
				defines.push(has(node, "value")
					? node.get("name") + "=" + node.get("value") : node.get("name"));

			case "vendor":
				vendors.push({
					name: node.get("name"),
					present: node.get("present"),
					system: has(node, "system") ? node.get("system") : "",
					flag: has(node, "flag") ? node.get("flag") : "",
					size: has(node, "size") ? node.get("size") : "",
					about: has(node, "about") ? node.get("about") : ""
				});

			case "path":
				paths.push({ name: node.get("name"), value: node.get("value") });

			case "include":
				includes.push(node.get("value"));

			case "link":
				links.push(node.get("value"));

			case "ship":
				ships.push(node.get("value"));

			case "native":
				nativePath = has(node, "path") ? node.get("path") : nativePath;

				for (file in node.elements()) {
					if (!allowed(file)) continue;

					switch (file.nodeName) {
						case "file": nativeFiles.push(file.get("name"));

						case "tree":
							nativeTrees.push(new Grove(fill(file.get("path")),
								has(file, "suffix") ? file.get("suffix") : ".c",
								has(file, "skip") ? file.get("skip") : "",
								has(file, "include") ? fill(file.get("include")) : ""));

						case "flag": nativeFlags.push(file.get("value"));
						case _:
					}
				}

			case _:
		}
	}

	function drawn(node:Xml, group:String):Void {
		final many = node.get("names");

		if (many == null || many == "") {
			icons.push({name: node.get("name"), from: node.get("from"), group: group});
			return;
		}

		final where = node.get("from");

		for (part in many.split(",")) {
			final name = StringTools.trim(part);
			if (name == "") continue;

			icons.push({name: name, from: where + "/" + name, group: group});
		}
	}

	function allowed(node:Xml):Bool {
		if (has(node, "if") && !holds(node.get("if"))) return false;
		if (has(node, "unless") && holds(node.get("unless"))) return false;
		return true;
	}

	function holds(term:String):Bool {
		return switch (term) {
			case "windows", "linux", "mac": os == term;
			case "desktop": true;
			case "debug": debug;
			case "release": !debug;
			case "llvm": toolchain == "clang-cl" || toolchain == "clang" || toolchain == "mingw";
			case _: toolchain == term;
		}
	}

	public function fill(value:String):String {
		var out = value;
		for (one in paths) out = StringTools.replace(out, "${" + one.name + "}", one.value);
		return out;
	}

	public function pathOf(name:String):String {
		for (one in paths) if (one.name == name) return one.value;
		return "";
	}

	public function targetOf(id:String):Null<Target> {
		for (one in targets) if (one.id == id) return one;
		return null;
	}

	public function sourcesOf(id:String):Array<String> {
		final one = targetOf(id);
		return one == null ? sources.copy() : sources.concat(one.sources);
	}

	public function names():Array<String> {
		return [for (one in targets) one.id];
	}

	static inline function has(node:Xml, name:String):Bool {
		return node.exists(name);
	}

	static function number(node:Xml, name:String, fallback:Int):Int {
		if (!has(node, name)) return fallback;
		final read = Std.parseInt(node.get(name));
		return read == null ? fallback : read;
	}

	static function flag(node:Xml, name:String, fallback:Bool):Bool {
		if (!has(node, name)) return fallback;
		final said = node.get(name).toLowerCase();
		return said == "true" || said == "1" || said == "yes";
	}
}
