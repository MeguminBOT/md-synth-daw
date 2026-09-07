package mdd.app;

import mdd.Config;
import mdd.host.Discord;
import mdd.song.Part;
import mdd.song.Song;

@:unreflective
final class Presence {
	public static inline final HIDDEN = 0;
	public static inline final PLAIN = 1;
	public static inline final FULL = 2;

	public static inline final DIAL_EVERY = 12.0;
	public static inline final SEND_EVERY = 5.0;
	public static inline final LOOK_EVERY = 1.0;

	public static inline final MOST = 118;
	public static inline final LABEL = 30;

	public var level:Int = FULL;
	public var busy:String = "";

	public var application:String = Config.DISCORD;
	public var cover:String = Config.DISCORD_COVER;
	public var badgePlaying:String = Config.DISCORD_PLAYING;
	public var badgeStopped:String = Config.DISCORD_STOPPED;
	public var badgeWorking:String = Config.DISCORD_WORKING;

	public var sent(default, null):Int = 0;
	public var dials(default, null):Int = 0;
	public var wanted(default, null):String = "";

	public var session(default, null):Null<Session> = null;

	var looked:Float = 0;
	var waited:Float = 0;
	var dialled:Float = DIAL_EVERY;

	var began:Float = 0;
	var nonce:Int = 0;

	public function new() {
		began = Date.now().getTime();
	}

	public function follows(held:Session):Void {
		session = held;

		began = Date.now().getTime();
		wanted = "";
		waited = SEND_EVERY;
	}

	public inline function possible():Bool {
		return application != "";
	}

	public inline function live():Bool {
		return Discord.ready();
	}

	public function user():String {
		return Std.string(Discord.user());
	}

	public function fault():String {
		return Std.string(Discord.fault());
	}

	public function said():String {
		if (!possible()) return "no application id, never connects";
		if (level == HIDDEN) return "off";

		if (!Discord.live()) {
			final held = fault();
			return held == "" ? "not connected" : "not connected, " + held;
		}

		if (!Discord.ready()) return "connected, waiting for discord";

		final who = user();
		return (who == "" ? "connected" : "connected as " + who) + ", " + sent + " sent";
	}

	public function shut():Void {
		if (Discord.live()) Discord.shut();

		wanted = "";
	}

	public function tick(seconds:Float):Void {
		if (level == HIDDEN || !possible()) {
			shut();
			return;
		}

		if (!Discord.live()) {
			if (!redials(seconds)) return;

			dials++;

			if (!Discord.open(application)) return;

			sent = 0;
			wanted = "";
			waited = SEND_EVERY;
		}

		if (looks(seconds)) Discord.poll();

		if (!Discord.ready()) return;
		if (!due(seconds)) return;

		final held = activity();
		if (held == wanted) return;

		nonce++;

		final out = new StringBuf();

		out.add("{\"cmd\":\"SET_ACTIVITY\",\"nonce\":\"mdd-");
		out.add(nonce);
		out.add("\",\"args\":{\"pid\":");
		out.add(Discord.pid());
		out.add(",\"activity\":");
		out.add(held);
		out.add("}}");

		if (!Discord.write(Discord.FRAME, out.toString())) return;

		wanted = held;
		sent++;
	}

	public function redials(seconds:Float):Bool {
		dialled += seconds;
		if (dialled < DIAL_EVERY) return false;

		dialled = 0;
		return true;
	}

	public function looks(seconds:Float):Bool {
		looked += seconds;
		if (looked < LOOK_EVERY) return false;

		looked = 0;
		return true;
	}

	public function due(seconds:Float):Bool {
		waited += seconds;
		if (waited < SEND_EVERY) return false;

		waited = 0;
		return true;
	}

	public function activity():String {
		final out = new StringBuf();

		out.add("{\"details\":");
		out.add(quoted(details(), MOST));
		out.add(",\"state\":");
		out.add(quoted(state(), MOST));

		timed(out);
		parted(out);

		shelved(out);

		if (Config.GITHUB != "") {
			out.add(",\"buttons\":[{\"label\":");
			out.add(quoted("Get " + Config.TITLE, LABEL));
			out.add(",\"url\":\"https://github.com/" + Config.GITHUB + "\"}]");
		}

		out.add(",\"instance\":false}");

		return out.toString();
	}

	function shelved(out:StringBuf):Void {
		out.add(",\"assets\":{\"large_text\":");
		out.add(quoted(shelf(), MOST));

		if (cover != "") {
			out.add(",\"large_image\":");
			out.add(quoted(cover, MOST));
		}

		final mark = badge();

		if (mark != "") {
			out.add(",\"small_image\":");
			out.add(quoted(mark, MOST));
			out.add(",\"small_text\":");
			out.add(quoted(pace(), MOST));
		}

		out.add("}");
	}

	function details():String {
		final held = session;
		if (held == null || level < FULL) return "Making Mega Drive music";

		final name = held.song.name == "" ? "untitled" : held.song.name;
		return held.song.author == "" ? name : name + ", by " + held.song.author;
	}

	function state():String {
		if (busy != "") return busy;

		final held = session;
		if (held == null) return "Starting up";

		final playing = held.transport.playing;

		if (level < FULL) return playing ? "Playing" : "In the editor";
		if (playing) return "Playing " + bar(held, held.transport.tick());

		return "Editing " + held.part.name() + ", pattern " + (held.pattern + 1) + " of "
			+ held.song.patterns.length;
	}

	function shelf():String {
		if (level < FULL) return Config.TITLE + " " + Config.VERSION;

		final held = session;
		if (held == null) return Config.TITLE + " " + Config.VERSION;

		final song = held.song;

		var notes = 0;
		for (pattern in song.patterns) notes += pattern.notes();

		final out = new StringBuf();

		out.add(family(song, 0, 6, "FM"));
		out.add(family(song, 6, 9, "PSG"));
		out.add(family(song, 9, 10, "noise"));
		out.add(family(song, 10, 11, "DAC"));

		final census = out.toString();

		final span = song.tempo.ppqn * 4;
		final bars = span < 1 ? 0 : Math.ceil(song.ends() / span);

		return (census == "" ? "no channels used" : census.substr(2)) + ", "
			+ song.patterns.length + counted(song.patterns.length, " pattern", " patterns")
			+ ", " + notes + counted(notes, " note", " notes")
			+ ", " + bars + counted(bars, " bar", " bars");
	}

	function pace():String {
		final held = session;
		if (held == null) return Config.TITLE + " " + Config.VERSION;

		if (level < FULL) return held.transport.playing ? "Playing" : "Stopped";

		final song = held.song;
		final beats = Math.round(song.tempo.beatsAt(0));

		final out = new StringBuf();

		out.add(beats);
		out.add(" BPM, ");
		out.add(clock(held.transport.seconds()));
		out.add(" of ");
		out.add(clock(ending(held)));

		if (held.transport.looping) out.add(", looping");
		if (song.driving) out.add(", through a driver");

		return out.toString();
	}

	function badge():String {
		final held = session;

		if (busy != "") return badgeWorking;
		return held != null && held.transport.playing ? badgePlaying : badgeStopped;
	}

	function timed(out:StringBuf):Void {
		final held = session;
		final now = Date.now().getTime();

		if (held == null || !held.transport.playing) {
			out.add(",\"timestamps\":{\"start\":");
			out.add(whole(began));
			out.add("}");

			return;
		}

		final at = held.transport.seconds();
		final ends = ending(held);

		out.add(",\"timestamps\":{\"start\":");
		out.add(whole(now - at * 1000));

		if (level >= FULL && !held.transport.looping && ends > at) {
			out.add(",\"end\":");
			out.add(whole(now + (ends - at) * 1000));
		}

		out.add("}");
	}

	function parted(out:StringBuf):Void {
		final held = session;
		if (held == null || level < FULL) return;

		final used = voices(held.song);
		if (used < 1) return;

		out.add(",\"party\":{\"id\":\"mdd-");
		out.add(Discord.pid());
		out.add("\",\"size\":[");
		out.add(used);
		out.add(",");
		out.add(Part.COUNT);
		out.add("]}");
	}

	function ending(held:Session):Float {
		final last = held.song.ends();
		if (last < 1) return 0;

		return held.song.tempo.samplesAt(last) / mdd.song.Tempo.TICKS;
	}

	static function voices(song:Song):Int {
		var used = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;

			for (pattern in song.patterns) {
				if (!pattern.used(part)) continue;

				used++;
				break;
			}
		}

		return used;
	}

	static function family(song:Song, from:Int, to:Int, called:String):String {
		var used = 0;

		for (index in from...to) {
			final part:Part = index;

			for (pattern in song.patterns) {
				if (!pattern.used(part)) continue;

				used++;
				break;
			}
		}

		return used < 1 ? "" : ", " + used + " " + called;
	}

	static function counted(many:Int, one:String, more:String):String {
		return many == 1 ? one : more;
	}

	static function bar(held:Session, tick:Int):String {
		final beat = held.song.tempo.ppqn;
		final span = beat * 4;

		final which = Std.int(tick / span) + 1;
		final within = Std.int((tick % span) / beat) + 1;

		return "bar " + which + "." + within + " of "
			+ (Std.int(held.song.ends() / span) + 1);
	}

	public static function clock(seconds:Float):String {
		if (seconds < 0) return "0:00";

		final total = Std.int(seconds);
		final minutes = Std.int(total / 60);

		return minutes + ":" + StringTools.lpad(Std.string(total % 60), "0", 2);
	}

	public static function whole(value:Float):String {
		if (value < 1) return "0";

		var held = Math.ffloor(value);
		final digits:Array<Int> = [];

		while (held >= 1) {
			final next = Math.ffloor(held / 10);

			digits.push(Std.int(held - next * 10));
			held = next;
		}

		final out = new StringBuf();

		var index = digits.length - 1;
		while (index >= 0) {
			out.addChar(48 + digits[index]);
			index--;
		}

		return out.toString();
	}

	public static function quoted(from:String, most:Int):String {
		final out = new StringBuf();
		out.addChar(34);

		var held = 0;
		var index = 0;

		while (index < from.length && held < most) {
			final code = StringTools.fastCodeAt(from, index);
			index++;
			held++;

			if (code >= 0xD800 && code <= 0xDFFF) {
				if (code > 0xDBFF || index >= from.length) continue;

				final tail = StringTools.fastCodeAt(from, index);
				if (tail < 0xDC00 || tail > 0xDFFF) continue;

				index++;

				out.addChar(code);
				out.addChar(tail);

				continue;
			}

			if (code == 34 || code == 92) {
				out.addChar(92);
				out.addChar(code);

				continue;
			}

			if (code >= 32) {
				out.addChar(code);
				continue;
			}

			out.add("\\u");
			out.add(StringTools.lpad(StringTools.hex(code, 4), "0", 4));
		}

		out.addChar(34);
		return out.toString();
	}
}
