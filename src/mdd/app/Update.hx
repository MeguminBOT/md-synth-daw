package mdd.app;

import haxe.atomic.AtomicInt;
import mdd.format.Json;
import mdd.format.Node;
import mdd.host.Paths;

@:unreflective
final class Update {
	public static inline final IDLE = 0;
	public static inline final LOOKING = 1;
	public static inline final CURRENT = 2;
	public static inline final WAITING = 3;
	public static inline final UNREACHABLE = 4;
	public static inline final FETCHING = 5;
	public static inline final FETCHED = 6;

	static inline final API = "https://api.github.com/repos/";
	static inline final LATEST = "/releases/latest";

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
	var weighs(default, null):Int = 0;

	final held:AtomicInt = new AtomicInt(IDLE);

	public function new(repository:String, running:String, platform:String = "",
			machine:String = "", portable:Null<Bool> = null) {
		this.repository = repository;
		this.running = running;
		this.platform = platform == "" ? Paths.platform() : platform;
		this.machine = machine == "" ? Paths.machine() : machine;
		this.portable = portable == null ? Paths.portable() : portable;
	}

	public inline function state():Int {
		return held.load();
	}

	public inline function possible():Bool {
		return repository != "";
	}

	public inline function checkAt():String {
		return possible() ? API + repository + LATEST : "";
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

		final held = node.get("assets");
		assets = held.length();

		var fallback = "";
		var best = 0;

		for (i in 0...held.length()) {
			final asset = held.at(i);
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

	static function trimmed(said:String):String {
		final held = StringTools.trim(said);
		return StringTools.startsWith(held, "v") ? held.substr(1) : held;
	}

	static function firstLine(said:String):String {
		final held = StringTools.trim(said.split("\n")[0]);
		return held.length > 96 ? held.substr(0, 93) + "..." : held;
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
		if (weighs <= 0 || into == "" || !sys.FileSystem.exists(into)) return -1;

		final held = sys.FileSystem.stat(into).size / weighs;
		return held < 0 ? 0 : (held > 1 ? 1 : held);
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
		final held = said.split(".");

		for (i in 0...3) {
			if (i >= held.length) break;

			final read = Std.parseInt(digits(held[i]));
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

		final held = out.toString();
		return held == "" ? "0" : held;
	}
}
