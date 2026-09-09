import sys.FileSystem;
import sys.io.File;

/**
	Writes the release notes for a tag out of the commit log.

	It groups the subjects by the category prefix they carry, and puts the downloads
	table and the verification commands above them. The same command run locally writes
	the same file the release workflow uploads, so the notes can be read before
	anything is published.
**/
class Notes {
	static inline final WALL = 60;
	static inline final COLUMNS = 92;

	static final SECTIONS:Array<Section> = [
		{area: "Chip", title: "Sound chips", quiet: false},
		{area: "Song", title: "The song model", quiet: false},
		{area: "Play", title: "Playback and export", quiet: false},
		{area: "Format", title: "File formats", quiet: false},
		{area: "View", title: "Editors and panels", quiet: false},
		{area: "Ui", title: "The interface", quiet: false},
		{area: "App", title: "The application", quiet: false},
		{area: "Host", title: "Window, audio and system", quiet: false},
		{area: "Check", title: "Diagnostics", quiet: false},
		{area: "Build", title: "Building and packaging", quiet: false},
		{area: "General", title: "The repository", quiet: false},
		{area: "Docs", title: "Documentation", quiet: true},
		{area: "Test", title: "Checks", quiet: true}
	];

	static final PLATFORMS:Array<Machine> = [
		{title: "Windows x86-64", stamp: "windows-x86_64", installed: "-setup.exe"},
		{title: "Linux x86-64", stamp: "linux-x86_64", installed: "-installer.tar.gz"},
		{title: "Linux arm64", stamp: "linux-arm64", installed: "-installer.tar.gz"},
		{title: "macOS x86-64", stamp: "mac-x86_64", installed: ".dmg"},
		{title: "macOS arm64", stamp: "mac-arm64", installed: ".dmg"}
	];

	/**
		Writes the notes for a tag. A tag whose version is not the one the build file
		carries is refused, because every packaged file name carries that version and a
		release that disagrees with them is worse than no release.

		@param root The repository root.
		@param project What the build file declares.
		@param args The command arguments. The first that is not a flag is the tag.
		@return False where the tag is wrong or there is nothing to write.
	**/
	public static function write(root:String, project:Project, args:Array<String>):Bool {
		var tag = "";
		for (arg in args) {
			if (StringTools.startsWith(arg, "-")) continue;
			tag = arg;
			break;
		}

		if (tag == "") tag = "v" + project.version;

		final numbered = StringTools.startsWith(tag, "v") ? tag.substr(1) : tag;

		if (numbered != project.version) {
			Sys.println("");
			Sys.println("  mdd: " + tag + " asks for " + numbered + ", and mdd.xml carries "
				+ project.version);
			Sys.println("  the release name and the built file names would disagree.");
			Sys.println("  edit the version in mdd.xml, or pass the tag that matches it.");
			Sys.println("");
			return false;
		}

		if (git(["rev-parse", "--git-dir"]) == "") {
			Sys.println("mdd: not a git checkout, so there is no history to read");
			return false;
		}

		final tagged = git(["rev-parse", "--verify", "--quiet", tag + "^{commit}"]) != "";
		final head = tagged ? tag : "HEAD";

		final previous = StringTools.trim(git(["describe", "--tags", "--abbrev=0", "--match", "v*",
			"--exclude", tag, head]));

		final range = previous == "" ? head : previous + ".." + head;
		final entries = read(git(["log", range, "--no-merges", "--format=%s%x1e"]));

		if (entries.length == 0) {
			Sys.println("mdd: no commits between "
				+ (previous == "" ? "the first commit" : previous) + " and " + head);
			return false;
		}

		final into = root + "/" + project.output;
		if (!FileSystem.exists(into)) FileSystem.createDirectory(into);

		File.saveContent(into + "/NOTES.md", rendered(project, entries, tag, previous, tagged));

		Sys.println("");
		Sys.println("  notes for " + tag);
		Sys.println("  since     " + (previous == "" ? "the first commit" : previous));
		Sys.println("  commits   " + entries.length);
		Sys.println("  written   " + project.output + "/NOTES.md");

		if (!tagged) {
			Sys.println("");
			Sys.println("  " + tag + " is not a tag yet. To put it on the commit these notes"
				+ " describe:");
			Sys.println("");
			Sys.println("      git tag -a " + tag + " -m \"" + project.title + " " + numbered
				+ "\"");
			Sys.println("      git push origin " + tag);
		}

		Sys.println("");
		return true;
	}

	static function read(said:String):Array<Entry> {
		final out:Array<Entry> = [];

		for (record in said.split("\x1e")) {
			final subject = StringTools.trim(record);
			if (subject == "") continue;

			out.push(split(subject));
		}

		return out;
	}

	static function split(subject:String):Entry {
		if (StringTools.startsWith(subject, "[")) {
			final shut = subject.indexOf("]");

			if (shut > 1) {
				final inside = subject.substring(1, shut);
				final rest = StringTools.trim(subject.substr(shut + 1));
				final cut = inside.indexOf("/");

				if (rest != "") {
					return cut < 0
						? {area: inside, place: "", text: rest}
						: {area: inside.substr(0, cut), place: inside.substr(cut + 1), text: rest};
				}
			}
		}

		return {area: "General", place: "", text: subject};
	}

	static function rendered(project:Project, entries:Array<Entry>, tag:String, previous:String,
			tagged:Bool):String {
		final out = new StringBuf();

		out.add(project.description + ".\n\n");

		out.add(previous == ""
			? "The first release, built from " + entries.length + " commits.\n\n"
			: entries.length + " changes since " + previous + ".\n\n");

		downloads(out, project);
		checking(out, project);

		final folded = entries.length > WALL;

		out.add("## What changed\n\n");

		if (folded) {
			out.add("<details>\n");
			out.add("<summary>" + entries.length
				+ " changes, grouped by the part of the application they moved</summary>\n\n");

			for (section in SECTIONS) listed(out, entries, section);

			out.add("</details>\n\n");
		} else {
			for (section in SECTIONS) {
				if (section.quiet) continue;
				listed(out, entries, section);
			}

			var quiet = 0;
			for (section in SECTIONS) if (section.quiet) quiet += counted(entries, section.area);

			if (quiet > 0) {
				out.add("<details>\n");
				out.add("<summary>Documentation and checks (" + quiet + ")</summary>\n\n");

				for (section in SECTIONS) {
					if (!section.quiet) continue;
					listed(out, entries, section);
				}

				out.add("</details>\n\n");
			}
		}

		final where = "https://github.com/" + project.github;

		out.add("**Every commit**: "
			+ (previous == "" ? where + "/commits/" + (tagged ? tag : "main")
				: where + "/compare/" + previous + "..." + tag)
			+ "\n");

		return out.toString();
	}

	static function counted(entries:Array<Entry>, area:String):Int {
		var found = 0;
		for (entry in entries) if (entry.area == area) found++;

		return found;
	}

	static function listed(out:StringBuf, entries:Array<Entry>, section:Section):Void {
		final mine:Array<Entry> = [];
		for (entry in entries) if (entry.area == section.area) mine.push(entry);

		if (mine.length == 0) return;

		final places:Array<String> = [];
		for (entry in mine) if (places.indexOf(entry.place) < 0) places.push(entry.place);

		places.sort(function(left:String, right:String):Int {
			if (left == right) return 0;
			if (left == "") return -1;
			if (right == "") return 1;

			return left < right ? -1 : 1;
		});

		out.add("### " + section.title + " (" + mine.length + ")\n\n");

		for (place in places) {
			for (entry in mine) {
				if (entry.place != place) continue;

				out.add("- " + (place == "" ? "" : "**" + place + "** ") + opened(entry.text)
					+ "\n");
			}
		}

		out.add("\n");
	}

	static function downloads(out:StringBuf, project:Project):Void {
		out.add("## Downloads\n\n");
		out.add("| platform | portable | installed |\n");
		out.add("| --- | --- | --- |\n");

		for (machine in PLATFORMS) {
			final base = project.short + "-" + project.version + "-" + machine.stamp;
			final carried = machine.stamp == "windows-x86_64" ? ".zip" : ".tar.gz";

			out.add("| " + machine.title
				+ " | `" + base + "-portable" + carried + "`"
				+ " | `" + base + machine.installed + "` |\n");
		}

		out.add("\n");
		out.add(wrapped("A portable copy keeps its settings, projects and banks in a `userdata`"
			+ " folder beside the executable, so it can live on a memory stick and leaves nothing"
			+ " behind. An installed copy keeps them under your documents. Both are the same"
			+ " application, and the updater offers whichever kind you already have."));
		out.add("\n");
	}

	static function checking(out:StringBuf, project:Project):Void {
		final base = project.short + "-" + project.version + "-windows-x86_64-portable.zip";

		out.add("## Checking a download\n\n");
		out.add(wrapped("`SHA256SUMS` lists every file, and each file has a `.sigstore` bundle"
			+ " beside it, `SHA256SUMS` included. The signature is what proves a download came from"
			+ " this repository: a checksum on its own only proves the file matches whichever list"
			+ " you read it from."));
		out.add("\n");

		out.add("```sh\n");
		out.add("sha256sum -c SHA256SUMS --ignore-missing\n\n");
		out.add("cosign verify-blob --bundle SHA256SUMS.sigstore \\\n");
		out.add("  --certificate-identity-regexp '^https://github.com/" + project.github
			+ "/' \\\n");
		out.add("  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\\n");
		out.add("  SHA256SUMS\n");
		out.add("```\n\n");

		out.add(wrapped("The same workflow records build provenance, which the GitHub CLI reads:"));
		out.add("\n");
		out.add("```sh\n");
		out.add("gh attestation verify " + base + " --repo " + project.github + "\n");
		out.add("```\n\n");
	}

	static function wrapped(said:String):String {
		final out = new StringBuf();
		var wide = 0;

		for (word in said.split(" ")) {
			if (word == "") continue;

			if (wide > 0 && wide + 1 + word.length > COLUMNS) {
				out.add("\n");
				wide = 0;
			} else if (wide > 0) {
				out.add(" ");
				wide++;
			}

			out.add(word);
			wide += word.length;
		}

		out.add("\n");
		return out.toString();
	}

	static function opened(text:String):String {
		if (text == "") return text;

		return text.charAt(0).toUpperCase() + text.substr(1);
	}

	static function git(args:Array<String>):String {
		try {
			final run = new sys.io.Process("git", args);
			final said = run.stdout.readAll().toString();

			run.stderr.readAll();

			final code = run.exitCode();
			run.close();

			return code == 0 ? said : "";
		} catch (e:Dynamic) {
			return "";
		}
	}
}

private typedef Section = {
	final area:String;
	final title:String;
	final quiet:Bool;
}

private typedef Machine = {
	final title:String;
	final stamp:String;
	final installed:String;
}

private typedef Entry = {
	final area:String;
	final place:String;
	final text:String;
}
