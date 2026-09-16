import sys.io.File;

/**
	One thing that can be built: its identifier, its entry point, and any source paths
	it adds beyond the shared ones.
**/
typedef Target = {
	final id:String;
	final main:String;
	final sources:Array<String>;
}

/**
	One source fetched into the vendor folder, and how to tell whether it is there.
**/
typedef Vendor = {
	final name:String;
	final present:String;
	final system:String;
	final flag:String;
	final size:String;
	final about:String;
}

/**
	A name and a value, for a path or an icon mapping.
**/
typedef Named = {
	final name:String;
	final value:String;
}

/**
	One interface icon: what it is called and where it is fetched from.
**/
typedef Icon = {
	final name:String;
	final from:String;
	final group:String;
}

/**
	One compiler that could build this, and what to look for on the path to know it is
	installed.
**/
typedef Toolchain = {
	var name:String;
	var probe:String;
	var about:String;
}

/**
	One typeface file: its name and where it is fetched from.

	A face that one language needs and nothing else does also names that language, the
	commit it is fetched at and the SHA-256 of the file there. An installer may leave such a
	face out, and the application fetches it again from that commit when the language is
	picked, so the pin is what makes the face it downloads the face the build ships.
**/
typedef Face = {
	final name:String;
	final from:String;
	final language:String;
	final commit:String;
	final sha256:String;
}

/**
	One pairing offered in preferences: which faces it uses for body, small, mono and
	headings.
**/
typedef Typeface = {
	final name:String;
	final sans:String;
	final mono:String;
}

/**
	Everything the build file declares, read once.

	It is the one file a person edits to change how this builds: the window, the
	targets, the defines, the vendored sources, the native sources, the include paths
	and what each platform links against. Nothing else is written by hand, and none of
	what is generated from this is tracked.
**/
class Project {
	/**
		What the application is called, in a window title and an installer.
	**/
	public var title(default, null):String = "mdd";

	/**
		What the command, the executable and the settings folder are called.
	**/
	public var short(default, null):String = "mdd";
	public var company(default, null):String = "";
	public var github(default, null):String = "";
	public var discord(default, null):String = "";
	public var discordCover(default, null):String = "";
	public var discordPlaying(default, null):String = "";
	public var discordStopped(default, null):String = "";
	public var discordWorking(default, null):String = "";

	/**
		The version, which every packaged file name carries.
	**/
	public var version(default, null):String = "0.0.0";

	/**
		One line saying what the application is.
	**/
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

	/**
		The source paths every target compiles.
	**/
	public var sources(default, null):Array<String> = [];

	/**
		Where the generated Haxe goes.
	**/
	public var generated(default, null):String = "export/haxe";
	public var languages(default, null):String = "assets/lang";
	public var appIcon(default, null):String = "assets/icon";

	/**
		The terms the Windows installer shows before it installs anything, with `{title}`,
		`{releases}` and `{source}` left to be filled in.
	**/
	public var terms(default, null):String = "assets/installer/terms.txt";

	public var typefacePath(default, null):String = "vendor/fonts";
	public var faces(default, null):Array<Face> = [];
	public var typefaces(default, null):Array<Typeface> = [];
	public var fallbacks(default, null):Array<String> = [];

	/**
		The face a label too long for the chosen one is drawn in, or an empty string
		where none is declared.
	**/
	public var condensed(default, null):String = "";

	public var iconPath(default, null):String = "assets/icons";
	public var iconSizes(default, null):Array<Int> = [];
	public var iconFrom(default, null):Array<Named> = [];
	public var icons(default, null):Array<Icon> = [];

	/**
		Where everything built goes.
	**/
	public var output(default, null):String = "export";

	/**
		Everything that can be built.
	**/
	public var targets(default, null):Array<Target> = [];
	public var defines(default, null):Array<String> = [];
	public var dce(default, null):String = "";
	public var linkFlags(default, null):Array<String> = [];
	public var compileFlags(default, null):Array<String> = [];
	public var stripped(default, null):Array<String> = [];
	public var libraries(default, null):Array<String> = [];

	/**
		Everything `mdd setup` fetches.
	**/
	public var vendors(default, null):Array<Vendor> = [];
	public var paths(default, null):Array<Named> = [];
	public var includes(default, null):Array<String> = [];
	public var links(default, null):Array<String> = [];
	public var ships(default, null):Array<String> = [];

	/**
		The name of the shared library a build links from the system rather than from
		`vendor/`, which the packaging carries beside the binary. Empty where every library
		is either vendored or part of the operating system.
	**/
	public var carry(default, null):String = "";

	public var nativePath(default, null):String = "native";
	public var nativeFiles(default, null):Array<String> = [];

	/**
		Folders of native sources named as trees.
	**/
	public var nativeTrees(default, null):Array<Grove> = [];
	public var nativeFlags(default, null):Array<String> = [];

	/**
		The compilers that could build this, in preference order. The first whose probe is found on the path is used.
	**/
	public var toolchains(default, null):Array<Toolchain> = [];

	/**
		Which one was chosen.
	**/
	public var toolchain(default, null):String = "";

	final os:String;
	final debug:Bool;

	/**
		Which architecture is being built for.
	**/
	public final arch:String;

	/**
		Reads the build file, keeping only the elements whose conditions hold.

		@param path The build file.
		@param os Which platform is being built for.
		@param debug Whether this is a debug build.
		@param toolchain Which compiler to use, or an empty string to choose.
		@param arch Which architecture is being built for.
	**/
	public function new(path:String, os:String, debug:Bool, toolchain:String = "",
			arch:String = "x86_64") {
		this.os = os;
		this.arch = arch;
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

			case "terms":
				terms = node.get("path");

			case "typefaces":
				typefacePath = node.get("path");

				for (held in node.elements()) {
					if (!allowed(held)) continue;

					switch (held.nodeName) {
						case "face":
							faces.push({name: held.get("name"), from: held.get("from"),
								language: attribute(held, "language"),
								commit: attribute(held, "commit"),
								sha256: attribute(held, "sha256").toLowerCase()});

						case "typeface":
							typefaces.push({name: held.get("name"), sans: held.get("sans"),
								mono: held.get("mono")});

						case "fallback":
							fallbacks.push(held.get("name"));

						case "condensed":
							condensed = held.get("name");

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

			case "linkflag":
				linkFlags.push(node.get("value"));

			case "compileflag":
				compileFlags.push(node.get("value"));

			case "strip":
				for (part in node.get("sections").split(",")) {
					final held = StringTools.trim(part);
					if (held != "") stripped.push(held);
				}

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

			case "carry":
				carry = node.get("value");

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
		if (has(node, "if") && !any(node.get("if"))) return false;
		if (has(node, "unless") && any(node.get("unless"))) return false;
		return true;
	}

	function any(terms:String):Bool {
		for (term in terms.split(",")) {
			if (holds(StringTools.trim(term))) return true;
		}

		return false;
	}

	function holds(term:String):Bool {
		return switch (term) {
			case "windows", "linux", "mac": os == term;
			case "x86_64", "arm64": arch == term;
			case "desktop": true;
			case "debug": debug;
			case "release": !debug;
			case "llvm": toolchain == "clang-cl" || toolchain == "clang" || toolchain == "mingw";
			case _: toolchain == term;
		}
	}

	/**
		Puts the declared values into a string, so a path can name the version or the
		output folder without repeating them.

		@param value A string with placeholders in it.
		@return It with every placeholder filled in.
	**/
	public function fill(value:String):String {
		var out = value;
		for (one in paths) out = StringTools.replace(out, "${" + one.name + "}", one.value);
		return out;
	}

	/**
		@param name A named path.
		@return Where it points, or an empty string where nothing declares it.
	**/
	public function pathOf(name:String):String {
		for (one in paths) if (one.name == name) return one.value;
		return "";
	}

	/**
		@param id A target identifier.
		@return That target, or null where nothing declares it.
	**/
	public function targetOf(id:String):Null<Target> {
		for (one in targets) if (one.id == id) return one;
		return null;
	}

	/**
		@param id A target identifier.
		@return Every source path it compiles, the shared ones included.
	**/
	public function sourcesOf(id:String):Array<String> {
		final one = targetOf(id);
		return one == null ? sources.copy() : sources.concat(one.sources);
	}

	/**
		@return What every target is called, for a usage line.
	**/
	public function names():Array<String> {
		return [for (one in targets) one.id];
	}

	static inline function has(node:Xml, name:String):Bool {
		return node.exists(name);
	}

	/**
		@param node An element.
		@param name An attribute.
		@return Its value, or an empty string where the element does not carry it.
	**/
	static function attribute(node:Xml, name:String):String {
		return has(node, name) ? node.get(name) : "";
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
