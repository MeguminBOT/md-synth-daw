package mdd.app;

import haxe.atomic.AtomicInt;
import mdd.format.Json;
import mdd.format.Node;
import mdd.host.Paths;
import sys.FileSystem;
import sys.io.File;

@:unreflective
final class Update {
	public static inline final IDLE = 0;
	public static inline final LOOKING = 1;
	public static inline final CURRENT = 2;
	public static inline final WAITING = 3;
	public static inline final UNREACHABLE = 4;
	public static inline final FETCHING = 5;
	public static inline final FETCHED = 6;
	public static inline final APPLYING = 7;
	public static inline final APPLIED = 8;
	public static inline final BROKEN = 9;

	static inline final API = "https://api.github.com/repos/";
	static inline final LATEST = "/releases/latest";

	static inline final STAGED = "staged";
	static inline final LOCK = "handover.lock";

	public var repository(default, null):String;
	public var running(default, null):String;
	public var platform(default, null):String;
	public var machine(default, null):String;
	public var portable(default, null):Bool;

	public var offered(default, null):String = "";
	public var saidAt(default, null):String = "";
	public var notes(default, null):String = "";
	public var into(default, null):String = "";
	public var assets(default, null):Int = 0;

	public var staged(default, null):String = "";
	public var handover(default, null):String = "";
	public var wrong(default, null):String = "";

	var endpoint:String = API;
	var weighs:Int = 0;
	var lock:Null<sys.io.FileOutput> = null;

	final held:AtomicInt = new AtomicInt(IDLE);

	public function new(repository:String, running:String, platform:String = "",
			machine:String = "", portable:Null<Bool> = null) {
		this.repository = repository;
		this.running = running;
		this.platform = platform == "" ? Paths.platform() : platform;
		this.machine = machine == "" ? Paths.machine() : machine;
		this.portable = portable == null ? Paths.portable() : portable;
	}

	public function looksAt(where:String):Void {
		endpoint = where;
	}

	public inline function state():Int {
		return held.load();
	}

	public inline function possible():Bool {
		return repository != "";
	}

	public inline function checkAt():String {
		return possible() ? endpoint + repository + LATEST : "";
	}

	public function look():Bool {
		if (!possible() || held.load() != IDLE) return false;

		held.store(LOOKING);
		sys.thread.Thread.create(function():Void asked());

		return true;
	}

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

	public function named():String {
		if (saidAt == "") return "";

		final cut = saidAt.split("?")[0].split("/");
		final last = cut.length == 0 ? "" : cut[cut.length - 1];

		return last == "" ? mdd.Config.SHORT + "-" + offered : last;
	}

	static function trimmed(said:String):String {
		final kept = StringTools.trim(said);
		return StringTools.startsWith(kept, "v") ? kept.substr(1) : kept;
	}

	static function firstLine(said:String):String {
		final kept = StringTools.trim(said.split("\n")[0]);
		return kept.length > 96 ? kept.substr(0, 93) + "..." : kept;
	}

	public function take(where:String):Bool {
		if (held.load() != WAITING || saidAt == "") return false;

		into = where;
		held.store(FETCHING);

		sys.thread.Thread.create(function():Void pulled());
		return true;
	}

	function pulled():Void {
		final code = Sys.command("curl", ["-sL", "--fail", "-o", into, saidAt]);
		held.store(code == 0 ? FETCHED : UNREACHABLE);
	}

	public function pulling():Float {
		if (weighs <= 0 || into == "" || !FileSystem.exists(into)) return -1;

		final part = FileSystem.stat(into).size / weighs;
		return part < 0 ? 0 : (part > 1 ? 1 : part);
	}

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

	function swapped(where:String, restart:Bool, guarded:Bool):Void {
		try {
			if (portable) carried(where, restart, guarded);
			else installs(where, restart, guarded);
		} catch (e:Dynamic) {
			wrong = Std.string(e);
		}

		held.store(handover == "" ? BROKEN : APPLIED);
	}

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

	static function beneath(where:String):String {
		final lib = haxe.io.Path.directory(where);
		final prefix = haxe.io.Path.directory(lib);

		return prefix == "" ? where : prefix;
	}

	function ending():String {
		return platform == "windows" ? ".exe" : "";
	}

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

	public function hands():Bool {
		if (held.load() != APPLIED || handover == "") return false;

		if (platform == "windows") {
			return Sys.command("cmd", ["/c", "start", "", "/min", handover]) == 0;
		}

		return Sys.command("sh", ["-c", "sh " + quoted(handover) + " >/dev/null 2>&1 &"]) == 0;
	}

	function opened(archive:String, into:String):Bool {
		if (platform == "windows" && StringTools.endsWith(archive.toLowerCase(), ".zip")) {
			return Sys.command("powershell", ["-NoProfile", "-NonInteractive", "-Command",
				"Expand-Archive -LiteralPath '" + archive + "' -DestinationPath '" + into
				+ "' -Force"]) == 0;
		}

		return Sys.command("tar", ["-xf", archive, "-C", into]) == 0;
	}

	static function only(where:String):String {
		final entries = FileSystem.readDirectory(where);
		if (entries.length != 1) return where;

		final one = where + "/" + entries[0];
		return FileSystem.isDirectory(one) ? one : where;
	}

	static function quoted(path:String):String {
		return "'" + StringTools.replace(path, "'", "'\\''") + "'";
	}

	static function backslashed(path:String):String {
		return "\"" + StringTools.replace(path, "/", "\\") + "\"";
	}

	public function refuse():Void {
		held.store(CURRENT);
	}

	public function forget():Void {
		held.store(IDLE);
	}

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

	public static function newer(offered:String, running:String):Bool {
		final left = parts(offered);
		final right = parts(running);

		for (i in 0...3) {
			if (left[i] > right[i]) return true;
			if (left[i] < right[i]) return false;
		}

		return false;
	}

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
