import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

/**
	Rasterises the interface icons into atlases at build time.

	They are drawn from SVG here rather than at start, so the application only has to
	upload a texture.
**/
class Icons {
	public static inline final MARK = "MDDI";
	public static inline final VERSION = 1;
	public static inline final HEADER = 14;
	public static inline final ENTRY = 8;

	/**
		Rasterises every icon at every size the build asks for and packs each size into
		an atlas.

		@param root The repository root.
		@param project What the build file declares.
		@param into The folder the atlases go in.
		@param report Whether to print what was drawn.
		@return How many icons were drawn.
	**/
	public static function built(root:String, project:Project, into:String, report:Bool):Int {
		if (project.icons.length == 0 || project.iconSizes.length == 0) return 0;

		final missing:Array<String> = [];
		final shapes:Array<Svg> = [];

		for (icon in project.icons) {
			final where = sourced(root, project, icon.from);

			if (where == "" || !FileSystem.exists(where)) {
				missing.push(icon.name);
				shapes.push(null);
				continue;
			}

			shapes.push(Svg.read(File.getContent(where)));
		}

		if (missing.length > 0) {
			Sys.println("  " + pad("icons") + missing.length + " of " + project.icons.length
				+ " have no artwork: " + missing.slice(0, 6).join(", ")
				+ (missing.length > 6 ? ", and more" : ""));
		}

		tree(into);

		var wrote = 0;

		for (size in project.iconSizes) {
			File.saveBytes(into + "/icons-" + size + ".atlas", packed(shapes, size));
			wrote++;
		}

		if (report) {
			Sys.println("  " + pad("icons") + project.icons.length + " icons at "
				+ project.iconSizes.join(", ") + " px");
		}

		return wrote;
	}

	static function sourced(root:String, project:Project, from:String):String {
		final at = from.indexOf(":");

		if (at < 0) return root + "/" + project.iconPath + "/" + from + ".svg";

		final name = from.substr(0, at);
		final tail = from.substr(at + 1);

		for (held in project.iconFrom) {
			if (held.name == name) return root + "/" + held.value + "/" + tail + ".svg";
		}

		return "";
	}

	static function packed(shapes:Array<Svg>, size:Int):Bytes {
		final count = shapes.length;

		var columns = 1;
		while (columns * columns < count) columns++;

		final rows = Math.ceil(count / columns);

		var wide = 32;
		while (wide < columns * size) wide <<= 1;

		var tall = 32;
		while (tall < rows * size) tall <<= 1;

		final coverage = Bytes.alloc(wide * tall);
		final header = HEADER + count * ENTRY;
		final out = Bytes.alloc(header + wide * tall);

		out.set(0, MARK.charCodeAt(0));
		out.set(1, MARK.charCodeAt(1));
		out.set(2, MARK.charCodeAt(2));
		out.set(3, MARK.charCodeAt(3));

		out.setUInt16(4, VERSION);
		out.setUInt16(6, size);
		out.setUInt16(8, count);
		out.setUInt16(10, wide);
		out.setUInt16(12, tall);

		for (index in 0...count) {
			final left = (index % columns) * size;
			final top = Std.int(index / columns) * size;

			out.setUInt16(HEADER + index * ENTRY, left);
			out.setUInt16(HEADER + index * ENTRY + 2, top);
			out.setUInt16(HEADER + index * ENTRY + 4, size);
			out.setUInt16(HEADER + index * ENTRY + 6, size);

			final svg = shapes[index];
			if (svg == null) continue;

			final cell = Raster.fill(svg, size);

			for (row in 0...size) {
				coverage.blit((top + row) * wide + left, cell, row * size, size);
			}
		}

		out.blit(header, coverage, 0, coverage.length);
		return out;
	}

	/**
		Writes the generated names the code refers to icons by.

		@param project What the build file declares.
		@param into The folder the generated file goes in.
	**/
	public static function named(project:Project, into:String):Void {
		final out = new StringBuf();

		out.add("package mdd;\n\n");
		out.add("class Icon {\n");

		for (index in 0...project.icons.length) {
			out.add("\tpublic static inline final " + constant(project.icons[index].name)
				+ " = " + index + ";\n");
		}

		out.add("\n\tpublic static inline final COUNT = " + project.icons.length + ";\n\n");
		out.add("\tpublic static final NAMES:Array<String> = [\n");

		var line = "\t\t";

		for (index in 0...project.icons.length) {
			final said = "\"" + project.icons[index].name + "\""
				+ (index == project.icons.length - 1 ? "" : ",");

			if (line.length + said.length > 100) {
				out.add(line + "\n");
				line = "\t\t";
			}

			line += (line.length > 2 ? " " : "") + said;
		}

		out.add(line + "\n\t];\n\n");
		out.add("\tpublic static final GROUPS:Array<String> = [\n");

		line = "\t\t";

		for (index in 0...project.icons.length) {
			final said = "\"" + project.icons[index].group + "\""
				+ (index == project.icons.length - 1 ? "" : ",");

			if (line.length + said.length > 100) {
				out.add(line + "\n");
				line = "\t\t";
			}

			line += (line.length > 2 ? " " : "") + said;
		}

		out.add(line + "\n\t];\n}\n");

		tree(into + "/mdd");
		File.saveContent(into + "/mdd/Icon.hx", out.toString());
	}

	/**
		Writes the generated names the code refers to typeface pairings by.

		@param project What the build file declares.
		@param into The folder the generated file goes in.
	**/
	public static function typefaces(project:Project, into:String):Void {
		final out = new StringBuf();

		out.add("package mdd;\n\n");
		out.add("class Typeface {\n");
		out.add("\tpublic static inline final COUNT = " + project.typefaces.length + ";\n\n");

		out.add(listed("NAMES", [for (held in project.typefaces) held.name]));
		out.add("\n");
		out.add(listed("SANS", [for (held in project.typefaces) held.sans]));
		out.add("\n");
		out.add(listed("MONO", [for (held in project.typefaces) held.mono]));
		out.add("\n");
		out.add(listed("FALLBACK", project.fallbacks));
		out.add("}\n");

		tree(into + "/mdd");
		File.saveContent(into + "/mdd/Typeface.hx", out.toString());
	}

	static function listed(name:String, held:Array<String>):String {
		final out = new StringBuf();

		out.add("\tpublic static final " + name + ":Array<String> = [\n");

		var line = "\t\t";

		for (index in 0...held.length) {
			final said = "\"" + held[index] + "\"" + (index == held.length - 1 ? "" : ",");

			if (line.length + said.length > 100) {
				out.add(line + "\n");
				line = "\t\t";
			}

			line += (line.length > 2 ? " " : "") + said;
		}

		out.add(line + "\n\t];\n");
		return out.toString();
	}

	static function constant(name:String):String {
		final out = new StringBuf();

		for (index in 0...name.length) {
			final code = name.charCodeAt(index);

			if (code == "-".code) out.add("_");
			else out.add(name.charAt(index).toUpperCase());
		}

		return out.toString();
	}

	static function tree(where:String):Void {
		if (!FileSystem.exists(where)) FileSystem.createDirectory(where);
	}

	static function pad(said:String):String {
		return StringTools.rpad(said, " ", 14);
	}
}
