package mdd.app;

import haxe.atomic.AtomicInt;
import mdd.format.Json;
import mdd.format.Node;
import mdd.host.Paths;
import sys.FileSystem;
import sys.io.File;

/**
	The self updater: looking for a newer release, downloading it, and putting it in
	place.

	Nothing reaches the network until the reader asks for it. What is offered depends
	on the copy that is asking: a portable copy is offered the archive and an installed
	one the installer, for the right platform and the right architecture, so neither
	gets the other.

	The swap itself is a small script the application launches and then closes, because
	a running program cannot replace its own files. On Windows the script waits for a
	lock this process holds open, which the operating system releases whatever way the
	process ends; elsewhere it sleeps and then unlinks, which is allowed while a binary
	runs.
**/
@:unreflective
final class Update {
	/**
		State: nothing is happening.
	**/
	public static inline final IDLE = 0;

	/**
		State: asking the releases page.
	**/
	public static inline final LOOKING = 1;

	/**
		State: this is the newest there is.
	**/
	public static inline final CURRENT = 2;

	/**
		State: something newer was found and the reader has not answered yet.
	**/
	public static inline final WAITING = 3;

	/**
		State: the address would not answer.
	**/
	public static inline final UNREACHABLE = 4;

	/**
		State: downloading.
	**/
	public static inline final FETCHING = 5;

	/**
		State: downloaded and not yet applied.
	**/
	public static inline final FETCHED = 6;

	/**
		State: unpacking it and writing the handover script.
	**/
	public static inline final APPLYING = 7;

	/**
		State: ready. The application should launch the handover and close.
	**/
	public static inline final APPLIED = 8;

	/**
		State: it could not be applied, and `wrong` says why.
	**/
	public static inline final BROKEN = 9;

	static inline final API = "https://api.github.com/repos/";
	static inline final LATEST = "/releases/latest";

	static inline final STAGED = "staged";
	static inline final LOCK = "handover.lock";

	/**
		Which repository to look at, or an empty string to never look.
	**/
	public var repository(default, null):String;

	/**
		Which version is running.
	**/
	public var running(default, null):String;

	/**
		Which platform to ask for.
	**/
	public var platform(default, null):String;

	/**
		Which architecture to ask for.
	**/
	public var machine(default, null):String;

	/**
		Whether this copy is portable, which decides between an archive and an installer.
	**/
	public var portable(default, null):Bool;

	/**
		Which version was found.
	**/
	public var offered(default, null):String = "";

	/**
		Where to download it from.
	**/
	public var saidAt(default, null):String = "";

	/**
		The first line of the release notes, for the notice.
	**/
	public var notes(default, null):String = "";

	/**
		Where the download went.
	**/
	public var into(default, null):String = "";

	/**
		How many files the release carries.
	**/
	public var assets(default, null):Int = 0;

	/**
		Where the new copy was unpacked, before it is swapped in.
	**/
	public var staged(default, null):String = "";

	/**
		The script that does the swap once this process has closed.
	**/
	public var handover(default, null):String = "";

	/**
		What went wrong, where anything did.
	**/
	public var wrong(default, null):String = "";

	var endpoint:String = API;
	var weighs:Int = 0;
	var lock:Null<sys.io.FileOutput> = null;

	final held:AtomicInt = new AtomicInt(IDLE);

	/**
		Builds an updater. Anything left empty is worked out from the running copy.

		@param repository Which repository to look at.
		@param running Which version is running.
		@param platform Which platform to ask for.
		@param machine Which architecture to ask for.
		@param portable Whether this copy is portable, or null to work it out.
	**/
	public function new(repository:String, running:String, platform:String = "",
			machine:String = "", portable:Null<Bool> = null) {
		this.repository = repository;
		this.running = running;
		this.platform = platform == "" ? Paths.platform() : platform;
		this.machine = machine == "" ? Paths.machine() : machine;
		this.portable = portable == null ? Paths.portable() : portable;
	}

	/**
		Points the updater at another address. Nothing in the application calls this;
		it is how a check drives the whole path against a local server.

		@param where The address to ask, ending in a slash.
	**/
	public function looksAt(where:String):Void {
		endpoint = where;
	}

	/**
		@return Which of the states above it is in. Safe from any thread.
	**/
	public inline function state():Int {
		return held.load();
	}

	/**
		@return Whether a repository is configured at all. Without one it never reaches the network.
	**/
	public inline function possible():Bool {
		return repository != "";
	}

	/**
		@return The address the newest release is asked for at.
	**/
	public inline function checkAt():String {
		return possible() ? endpoint + repository + LATEST : "";
	}

	/**
		Asks the releases page, on a thread of its own.

		@return False where there is no repository or something is already happening.
	**/
	public function look():Bool {
		if (!possible() || held.load() != IDLE) return false;

		held.store(LOOKING);
		sys.thread.Thread.create(function():Void asked());

		return true;
	}

	/**
		Fetches the release and reads it. This is the looking thread.
	**/
	function asked():Void {
		var said = "";

		try {
			said = fetched(checkAt());
		} catch (e:Dynamic) {
			said = "";
		}

		if (said == "") {
			held.store(UNREACHABLE);
			return;
		}

		try {
			read(said);
		} catch (e:Dynamic) {
			held.store(UNREACHABLE);
			return;
		}

		if (offered == "" || !newer(offered, running)) {
			held.store(CURRENT);
			return;
		}

		held.store(WAITING);
	}

	/**
		Reads a release document and chooses which of its files this copy wants.

		@param said The release as JSON.
	**/
	public function read(said:String):Void {
		offered = "";
		saidAt = "";
		notes = "";
		assets = 0;
		weighs = 0;

		final node = Json.parse(said);

		offered = trimmed(node.get("tag_name").saying(""));
		notes = firstLine(node.get("body").saying(""));

		final listed = node.get("assets");
		assets = listed.length();

		var fallback = "";
		var best = 0;

		for (i in 0...listed.length()) {
			final asset = listed.at(i);
			final name = asset.get("name").saying("").toLowerCase();
			final url = asset.get("browser_download_url").saying("");

			if (url == "") continue;
			if (fallback == "") fallback = url;

			final score = suits(name);
			if (score <= best) continue;

			best = score;
			saidAt = url;
			weighs = asset.get("size").whole(0);
		}

		if (saidAt == "") saidAt = fallback;
		if (saidAt == "") saidAt = node.get("html_url").saying("");
	}

	/**
		Scores one file by how well it suits this copy. The wrong architecture scores
		nothing at all, so it cannot win on any other part of its name.

		@param name The file name, in lower case.
		@return Its score. The highest wins.
	**/
	public function suits(name:String):Int {
		final installer = platform == "windows" ? "setup"
			: (platform == "mac" ? ".dmg" : "install");

		final ending = platform == "windows" ? ".exe"
			: (platform == "mac" ? ".dmg" : ".tar.gz");

		final other = machine == "arm64" ? "x86_64" : "arm64";
		if (name.indexOf(other) >= 0) return 0;

		var score = 0;

		if (name.indexOf(platform) >= 0) score += 2;
		if (name.indexOf(machine) >= 0) score += 2;
		if (StringTools.endsWith(name, ending)) score += 2;

		final carries = name.indexOf("portable") >= 0;
		final installs = name.indexOf(installer) >= 0;

		if (portable) {
			if (carries) score += 4;
			else if (installs) score -= 2;
		} else {
			if (installs) score += 4;
			else if (carries) score -= 2;
		}

		if (platform != "windows" && StringTools.endsWith(name, ".exe")) return 0;
		if (platform != "mac" && StringTools.endsWith(name, ".dmg")) return 0;

		return score;
	}

	/**
		@return What the chosen file is called, which is what the download is saved as. Saving it
			under a made up name loses the suffix the unpacker needs.
	**/
	public function named():String {
		if (saidAt == "") return "";

		final cut = saidAt.split("?")[0].split("/");
		final last = cut.length == 0 ? "" : cut[cut.length - 1];

		return last == "" ? mdd.Config.SHORT + "-" + offered : last;
	}

	/**
		@param said A tag name.
		@return It without a leading v.
	**/
	static function trimmed(said:String):String {
		final kept = StringTools.trim(said);
		return StringTools.startsWith(kept, "v") ? kept.substr(1) : kept;
	}

	/**
		@param said The release notes.
		@return Their first line, cut to something a notice can show.
	**/
	static function firstLine(said:String):String {
		final kept = StringTools.trim(said.split("\n")[0]);
		return kept.length > 96 ? kept.substr(0, 93) + "..." : kept;
	}

	/**
		Downloads the chosen file, on a thread of its own.

		@param where Where to save it.
		@return False where nothing is waiting to be downloaded.
	**/
	public function take(where:String):Bool {
		if (held.load() != WAITING || saidAt == "") return false;

		into = where;
		held.store(FETCHING);

		sys.thread.Thread.create(function():Void pulled());
		return true;
	}

	/**
		Downloads the file. This is the download thread.
	**/
	function pulled():Void {
		final code = Sys.command("curl", ["-sL", "--fail", "-o", into, saidAt]);
		held.store(code == 0 ? FETCHED : UNREACHABLE);
	}

	/**
		@return How far through the download is, 0 to 1, or a negative number where the size is not
			known.
	**/
	public function pulling():Float {
		if (weighs <= 0 || into == "" || !FileSystem.exists(into)) return -1;

		final part = FileSystem.stat(into).size / weighs;
		return part < 0 ? 0 : (part > 1 ? 1 : part);
	}

	/**
		Unpacks the download and writes the handover script, on a thread of its own.
		Nothing is replaced here: the script does that once this process has closed.

		@param where The folder the running copy sits in.
		@param restart Whether the new copy should be started once the swap is done.
		@param guarded Whether the script should wait for this process to close first.
		@return False where there is nothing downloaded to apply.
	**/
	public function applies(where:String, restart:Bool = true, guarded:Bool = true):Bool {
		if (held.load() != FETCHED || into == "" || where == "") return false;
		if (!FileSystem.exists(into)) return false;

		staged = "";
		handover = "";
		wrong = "";

		held.store(APPLYING);
		sys.thread.Thread.create(function():Void swapped(where, restart, guarded));

		return true;
	}

	/**
		Applies the update. This is the applying thread.

		@param where The folder the running copy sits in.
		@param restart Whether the new copy should be started once the swap is done.
		@param guarded Whether the script should wait for this process to close first.
	**/
	function swapped(where:String, restart:Bool, guarded:Bool):Void {
		try {
			if (portable) carried(where, restart, guarded);
			else installs(where, restart, guarded);
		} catch (e:Dynamic) {
			wrong = Std.string(e);
		}

		held.store(handover == "" ? BROKEN : APPLIED);
	}

	/**
		Applies a portable update: unpack the archive, check it carries a program, and
		write a script that copies it over the running copy.

		@param where The folder the running copy sits in.
		@param restart Whether the new copy should be started once the swap is done.
		@param guarded Whether the script should wait for this process to close first.
	**/
	function carried(where:String, restart:Bool, guarded:Bool):Void {
		final beside = haxe.io.Path.directory(into);
		final unpacked = beside + "/" + STAGED;

		Paths.clear(unpacked);
		Paths.make(unpacked);

		if (!opened(into, unpacked)) {
			wrong = "the archive would not open";
			return;
		}

		final inside = only(unpacked);
		final program = inside + "/" + mdd.Config.SHORT + ending();

		if (!FileSystem.exists(program)) {
			wrong = "the new copy carries no program";
			return;
		}

		staged = inside;
		handover = writes(beside, inside, where, restart ? where + "/" + mdd.Config.SHORT
			+ ending() : "", guarded, "");
	}

	/**
		Applies an installed update, which means running whatever the platform installs
		with rather than copying files.

		@param where The folder the running copy sits in.
		@param restart Whether the new copy should be started once the swap is done.
		@param guarded Whether the script should wait for this process to close first.
	**/
	function installs(where:String, restart:Bool, guarded:Bool):Void {
		final beside = haxe.io.Path.directory(into);

		if (platform == "windows") {
			handover = writes(beside, "", "", "", guarded, quoted(into) + " /SILENT /NORESTART");
			return;
		}

		if (platform == "mac") {
			handover = writes(beside, "", "", "", guarded, "open " + quoted(into));
			return;
		}

		final unpacked = beside + "/" + STAGED;

		Paths.clear(unpacked);
		Paths.make(unpacked);

		if (!opened(into, unpacked)) {
			wrong = "the archive would not open";
			return;
		}

		final inside = only(unpacked);
		final script = inside + "/install.sh";

		if (!FileSystem.exists(script)) {
			wrong = "the archive carries no install.sh";
			return;
		}

		staged = inside;

		final prefix = beneath(where);
		final after = restart ? prefix + "/bin/" + mdd.Config.SHORT : "";

		handover = writes(beside, "", "", after, guarded,
			"PREFIX=" + quoted(prefix) + " sh " + quoted(script));
	}

	/**
		@param where Where the running copy sits.
		@return The prefix it was installed under, which is two folders up.
	**/
	static function beneath(where:String):String {
		final lib = haxe.io.Path.directory(where);
		final prefix = haxe.io.Path.directory(lib);

		return prefix == "" ? where : prefix;
	}

	/**
		@return What an executable is called on the platform being updated.
	**/
	function ending():String {
		return platform == "windows" ? ".exe" : "";
	}

	/**
		Writes the handover script.

		@param beside The folder the script and the download sit in.
		@param from The unpacked new copy, or an empty string for an installer.
		@param where The folder to copy it over.
		@param after What to start when it is done, or an empty string for nothing.
		@param guarded Whether the script should wait for this process to close first.
		@param instead A command to run instead of copying, for an installer.
		@return Where the script was written.
	**/
	function writes(beside:String, from:String, where:String, after:String, guarded:Bool,
			instead:String):String {
		final path = beside + "/handover" + (platform == "windows" ? ".cmd" : ".sh");
		final out = new StringBuf();

		if (platform == "windows") {
			final guard = beside + "/" + LOCK;

			out.add("@echo off\r\n");
			out.add("setlocal\r\n");

			if (guarded) {
				locks();

				out.add(":wait\r\n");
				out.add("ping -n 2 127.0.0.1 >nul\r\n");
				out.add("del /q " + backslashed(guard) + " >nul 2>&1\r\n");
				out.add("if exist " + backslashed(guard) + " goto wait\r\n");
			}

			if (instead != "") out.add(instead + "\r\n");
			else {
				out.add("robocopy " + backslashed(from) + " " + backslashed(where)
					+ " /E /IS /IT /NJH /NJS /NFL /NDL /R:3 /W:2 >nul\r\n");
				out.add("if errorlevel 8 exit /b 1\r\n");
			}

			if (from != "") out.add("rmdir /s /q " + backslashed(from) + " >nul 2>&1\r\n");
			out.add("del /q " + backslashed(into) + " >nul 2>&1\r\n");

			if (after != "") out.add("start \"\" " + backslashed(after) + "\r\n");

			out.add("exit /b 0\r\n");
		} else {
			out.add("#!/usr/bin/env sh\n");

			if (guarded) out.add("sleep 3\n");

			if (instead != "") out.add(instead + " || exit 1\n");
			else {
				out.add("rm -f " + quoted(where + "/" + mdd.Config.SHORT) + "\n");
				out.add("cp -R " + quoted(from + "/.") + " " + quoted(where + "/") + " || exit 1\n");
				out.add("chmod +x " + quoted(where + "/" + mdd.Config.SHORT) + "\n");
			}

			if (from != "") out.add("rm -rf " + quoted(from) + "\n");
			out.add("rm -f " + quoted(into) + "\n");

			if (after != "") out.add("chmod +x " + quoted(after) + " 2>/dev/null\n");
			if (after != "") out.add(quoted(after) + " >/dev/null 2>&1 &\n");

			out.add("exit 0\n");
		}

		File.saveContent(path, out.toString());
		return path;
	}

	/**
		Opens a file and keeps it open, so the handover script can tell when this process
		has closed by waiting for the file to become deletable.
	**/
	function locks():Void {
		if (lock != null) return;

		try {
			lock = File.write(haxe.io.Path.directory(into) + "/" + LOCK, true);
			lock.writeString(running);
			lock.flush();
		} catch (e:Dynamic) {
			lock = null;
		}
	}

	/**
		Launches the handover script, detached, and returns at once. The caller should
		close the application immediately after.

		@return False where nothing is ready to hand over to.
	**/
	public function hands():Bool {
		if (held.load() != APPLIED || handover == "") return false;

		if (platform == "windows") {
			return Sys.command("cmd", ["/c", "start", "", "/min", handover]) == 0;
		}

		return Sys.command("sh", ["-c", "sh " + quoted(handover) + " >/dev/null 2>&1 &"]) == 0;
	}

	/**
		Unpacks an archive.

		@param archive The file to unpack.
		@param into The folder to unpack into.
		@return False where it would not unpack.
	**/
	function opened(archive:String, into:String):Bool {
		if (platform == "windows" && StringTools.endsWith(archive.toLowerCase(), ".zip")) {
			return Sys.command("powershell", ["-NoProfile", "-NonInteractive", "-Command",
				"Expand-Archive -LiteralPath '" + archive + "' -DestinationPath '" + into
				+ "' -Force"]) == 0;
		}

		return Sys.command("tar", ["-xf", archive, "-C", into]) == 0;
	}

	/**
		@param where A folder.
		@return The one folder inside it, where there is exactly one, and otherwise the folder
			itself. An archive usually carries one folder at the top.
	**/
	static function only(where:String):String {
		final entries = FileSystem.readDirectory(where);
		if (entries.length != 1) return where;

		final one = where + "/" + entries[0];
		return FileSystem.isDirectory(one) ? one : where;
	}

	/**
		@param path A path.
		@return It quoted for a shell script.
	**/
	static function quoted(path:String):String {
		return "'" + StringTools.replace(path, "'", "'\\''") + "'";
	}

	/**
		@param path A path.
		@return It quoted with backslashes, which the Windows command interpreter wants.
	**/
	static function backslashed(path:String):String {
		return "\"" + StringTools.replace(path, "/", "\\") + "\"";
	}

	/**
		Leaves the update, so nothing asks again until the next look.
	**/
	public function refuse():Void {
		held.store(CURRENT);
	}

	/**
		Puts the updater back to idle.
	**/
	public function forget():Void {
		held.store(IDLE);
	}

	/**
		Fetches an address, with a short timeout so a slow answer cannot hold a thread.

		@param url The address.
		@return What came back, or an empty string.
	**/
	static function fetched(url:String):String {
		final run = new sys.io.Process("curl", [
			"-sL", "--fail", "--max-time", "10",
			"-H", "Accept: application/vnd.github+json",
			"-H", "User-Agent: " + mdd.Config.SHORT + "/" + mdd.Config.VERSION,
			url
		]);

		final said = run.stdout.readAll().toString();
		final code = run.exitCode();

		run.close();
		return code == 0 ? said : "";
	}

	/**
		@param offered A version.
		@param running Another.
		@return Whether the first is newer, comparing in parts. String order gets 0.1.10 and 0.9.9
			wrong in opposite directions.
	**/
	public static function newer(offered:String, running:String):Bool {
		final left = parts(offered);
		final right = parts(running);

		for (i in 0...3) {
			if (left[i] > right[i]) return true;
			if (left[i] < right[i]) return false;
		}

		return false;
	}

	/**
		@param said A version.
		@return Its three numbers.
	**/
	static function parts(said:String):Array<Int> {
		final out = [0, 0, 0];
		final kept = said.split(".");

		for (i in 0...3) {
			if (i >= kept.length) break;

			final read = Std.parseInt(digits(kept[i]));
			out[i] = read == null ? 0 : read;
		}

		return out;
	}

	/**
		@param said One part of a version.
		@return The digits at the start of it, or nought where there are none.
	**/
	static function digits(said:String):String {
		final out = new StringBuf();

		for (i in 0...said.length) {
			final code = said.charCodeAt(i);
			if (code >= 48 && code <= 57) out.addChar(code);
			else break;
		}

		final kept = out.toString();
		return kept == "" ? "0" : kept;
	}
}
