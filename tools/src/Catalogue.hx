import sys.FileSystem;
import sys.io.File;

/**
	Generates the string keys the interface looks its text up by.

	A key is a number rather than a name at run time, so a lookup is an array index and
	not a search, and the numbers come from here so nothing can drift.
**/
class Catalogue {
	/**
		Reads the language files and writes the key list.

		@param project What the build file declares.
		@param root The repository root.
		@param into The folder the generated file goes in.
		@return How many keys there are.
	**/
	public static function named(project:Project, root:String, into:String):Int {
		final from = root + "/" + project.languages + "/" + reference(root, project);
		if (!FileSystem.exists(from)) return 0;

		var table:Dynamic = null;

		try {
			table = haxe.Json.parse(File.getContent(from));
		} catch (e:Dynamic) {
			Sys.println("mdd: the reference language would not read: " + e);
			return 0;
		}

		final keys = Reflect.fields(table);
		keys.sort(byName);

		final out = new StringBuf();

		out.add("package mdd.app;\n\n");
		out.add("enum abstract Locale(Int) from Int to Int {\n");
		out.add("\tpublic static inline final COUNT = " + keys.length + ";\n\n");

		for (index in 0...keys.length) {
			out.add("\tvar " + shouted(keys[index]) + " = " + index + ";\n");
		}

		out.add("}\n");

		tree(into + "/mdd/app");
		File.saveContent(into + "/mdd/app/Locale.hx", out.toString());

		return keys.length;
	}

	static function reference(root:String, project:Project):String {
		final where = root + "/" + project.languages;
		if (!FileSystem.exists(where)) return "";

		final held = FileSystem.readDirectory(where);
		held.sort(byName);

		for (name in held) if (name == "en-GB.json") return name;
		for (name in held) if (StringTools.endsWith(name, ".json")) return name;

		return "";
	}

	/**
		@param key A string key, as it appears in a language file.
		@return The name it is generated under.
	**/
	public static function shouted(key:String):String {
		final out = new StringBuf();

		for (index in 0...key.length) {
			final code = key.charCodeAt(index);
			if (code == null) continue;

			if (code == ".".code) {
				out.addChar("_".code);
				continue;
			}

			if (code >= "A".code && code <= "Z".code && index > 0) {
				final before = key.charCodeAt(index - 1);

				if (before != null && before != ".".code
					&& !(before >= "A".code && before <= "Z".code)) {
					out.addChar("_".code);
				}
			}

			out.addChar(code >= "a".code && code <= "z".code ? code - 32 : code);
		}

		return out.toString();
	}

	static function byName(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	static function tree(path:String):Void {
		if (FileSystem.exists(path)) return;
		FileSystem.createDirectory(path);
	}
}
