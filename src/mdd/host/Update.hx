package mdd.host;

import haxe.atomic.AtomicInt;

@:unreflective
final class Update {
	public static inline final IDLE = 0;
	public static inline final LOOKING = 1;
	public static inline final CURRENT = 2;
	public static inline final WAITING = 3;
	public static inline final UNREACHABLE = 4;
	public static inline final FETCHING = 5;
	public static inline final FETCHED = 6;

	public var checkAt(default, null):String;
	public var downloadAt(default, null):String;
	public var running(default, null):String;

	public var offered(default, null):String = "";
	public var saidAt(default, null):String = "";
	public var notes(default, null):String = "";
	public var into(default, null):String = "";

	final held:AtomicInt = new AtomicInt(IDLE);

	public function new(checkAt:String, downloadAt:String, running:String) {
		this.checkAt = checkAt;
		this.downloadAt = downloadAt;
		this.running = running;
	}

	public inline function state():Int {
		return held.load();
	}

	public inline function possible():Bool {
		return checkAt != "";
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
			said = fetched(checkAt);
		} catch (e:Dynamic) {
			said = "";
		}

		if (said == "") {
			held.store(UNREACHABLE);
			return;
		}

		read(said);

		if (offered == "" || !newer(offered, running)) {
			held.store(CURRENT);
			return;
		}

		held.store(WAITING);
	}

	function read(said:String):Void {
		offered = "";
		saidAt = "";
		notes = "";

		for (line in said.split("\n")) {
			final trimmed = StringTools.trim(line);
			final at = trimmed.indexOf("=");
			if (at <= 0) continue;

			final key = StringTools.trim(trimmed.substr(0, at));
			final value = StringTools.trim(trimmed.substr(at + 1));

			switch (key) {
				case "version": offered = value;
				case "url": saidAt = value;
				case "notes": notes = value;
				case _:
			}
		}

		if (saidAt == "" && downloadAt != "") {
			saidAt = StringTools.replace(downloadAt, "{version}", offered);
		}
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

	public function refuse():Void {
		held.store(CURRENT);
	}

	public function forget():Void {
		held.store(IDLE);
	}

	public static function fetched(url:String):String {
		final run = new sys.io.Process("curl", ["-sL", "--fail", "--max-time", "8", url]);
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
