package mdd.gate;

import mdd.Config;
import mdd.app.Presence;
import mdd.app.Session;
import mdd.host.Discord;
import mdd.song.Note;
import mdd.song.Part;

typedef Shelf = {
	var large_text:String;
	var ?large_image:String;
	var ?small_image:String;
	var ?small_text:String;
}

typedef Clocked = {
	var start:Float;
	var ?end:Float;
}

typedef Party = {
	var id:String;
	var size:Array<Int>;
}

typedef Pressed = {
	var label:String;
	var url:String;
}

typedef Activity = {
	var details:String;
	var state:String;
	var assets:Shelf;
	var timestamps:Clocked;
	var instance:Bool;
	var ?party:Party;
	var ?buttons:Array<Pressed>;
}

@:unreflective
class PresenceCheck {
	static var ran = 0;
	static var failed = 0;

	public static function run(args:Array<String>):Int {
		ran = 0;
		failed = 0;

		Sys.println("  presence");

		var at = 0;

		while (at < args.length) {
			if (args[at] == "--dial" && at + 1 < args.length) return dialled(args[at + 1]);
			at++;
		}

		shaped();
		escaped();
		clamped();
		levelled();
		censused();
		played();
		nameless();
		paced();
		stamped();
		hosted();

		Sys.println("    " + ran + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    " + failed + " FAILED");

		return failed == 0 ? 0 : 1;
	}

	static function dialled(application:String):Int {
		final held = new Presence();
		held.follows(Session.started(mdd.song.Library.embedded()));

		held.application = application;

		Sys.println("    dialling discord as " + application);

		final began = haxe.Timer.stamp();
		var wrote = 0;

		while (haxe.Timer.stamp() - began < 8) {
			held.tick(0.05);

			if (held.sent != wrote) {
				wrote = held.sent;
				Sys.println("    sent " + held.activity());
			}

			Sys.sleep(0.05);
		}

		Sys.println("    socket discord-ipc-" + Discord.socket());
		Sys.println("    " + held.said());
		Sys.println("    " + Discord.took() + " frames read, " + Discord.sent() + " written");

		held.shut();

		return Discord.took() > 0 ? 0 : 1;
	}

	static function halved(text:String):Bool {
		var index = 0;

		while (index < text.length) {
			final one = StringTools.fastCodeAt(text, index);
			index++;

			if (one < 0xD800 || one > 0xDFFF) continue;
			if (one > 0xDBFF) return true;
			if (index >= text.length) return true;

			final two = StringTools.fastCodeAt(text, index);
			if (two < 0xDC00 || two > 0xDFFF) return true;

			index++;
		}

		return false;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 50) + said + (ok ? "" : "   FAILED"));
	}

	static function made():Presence {
		final held = new Presence();
		held.follows(Session.started(mdd.song.Library.embedded()));

		held.cover = "cover";
		held.badgePlaying = "playing";
		held.badgeStopped = "stopped";
		held.badgeWorking = "working";

		return held;
	}

	static function within(held:Presence):Session {
		final out = held.session;
		return out == null ? Session.started(mdd.song.Library.embedded()) : out;
	}

	static function named(held:Presence, what:String):Void {
		within(held).song.name = what;
	}

	static function read(held:Presence):Activity {
		final out:Activity = haxe.Json.parse(held.activity());
		return out;
	}

	static function shaped():Void {
		final held = made();
		final said = read(held);

		says("an activity is well formed json", said.details == "untitled",
			"details " + said.details);

		says("and it says what is being edited",
			said.state == "Editing FM1, pattern 1 of 1", said.state);

		says("and it carries a large image and a badge",
			said.assets.large_image == held.cover
				&& said.assets.small_image == held.badgeStopped,
			said.assets.large_image + ", " + said.assets.small_image);

		says("and an elapsed clock with no end while stopped",
			said.timestamps.start > 0 && said.timestamps.end == null,
			Presence.whole(said.timestamps.start));

		final buttons = said.buttons;

		says("and a button to the repository",
			Config.GITHUB == "" ? buttons == null
				: buttons != null && buttons.length == 1
					&& buttons[0].url == "https://github.com/" + Config.GITHUB,
			buttons == null ? "none" : buttons[0].label);
	}

	static function escaped():Void {
		final held = made();
		final want = "he said \"hi\" \\ then\nstopped";

		named(held, want);

		final said = read(held);

		says("a quote, a backslash and a newline survive", said.details == want,
			said.details.length + " characters back");

		final treble = "\u{1D11E}";

		named(held, "AB" + treble + "CD");

		says("an astral character survives the payload whole",
			read(held).details == "AB" + treble + "CD",
			read(held).details.length + " units back");

		named(held, StringTools.rpad("", "a", Presence.MOST - 1) + treble + "tail");

		says("and a cut never leaves half of one behind", !halved(read(held).details),
			read(held).details.length + " characters, no stray surrogate");

		named(held, "AB" + String.fromCharCode(0xD834) + "CD");

		says("and a stray surrogate never reaches the payload", !halved(read(held).details),
			read(held).details);

		named(held, want);

		says("and the control character is escaped",
			held.activity().indexOf("\\u000a") >= 0
				|| held.activity().indexOf("\\u000A") >= 0,
			"escaped");
	}

	static function clamped():Void {
		final held = made();
		named(held, StringTools.rpad("", "a", 400));

		final said = read(held);

		says("a name longer than discord takes is cut",
			said.details.length <= Presence.MOST, said.details.length + " of " + Presence.MOST);

		final tooltip = said.assets.small_text;

		says("and every field stays within the limit",
			said.state.length <= Presence.MOST && said.assets.large_text.length <= Presence.MOST
				&& tooltip != null && tooltip.length <= Presence.MOST,
			said.assets.large_text.length + " the longest");
	}

	static function levelled():Void {
		final held = made();
		named(held, "Green Hill Zone");
		held.level = Presence.PLAIN;

		final text = held.activity();
		final said = read(held);

		says("the plain level names nothing of the song",
			text.indexOf("Green Hill") < 0 && said.party == null,
			said.details + ", " + said.state);

		held.level = Presence.FULL;

		says("and the full level does", read(held).details == "Green Hill Zone",
			read(held).details);

		held.level = Presence.HIDDEN;
		held.tick(60);

		says("and off never connects", !Discord.live() && held.sent == 0,
			held.dials + " dials, " + held.sent + " sent");
	}

	static function censused():Void {
		final held = made();
		final song = within(held).song;
		final pattern = song.patterns[0];

		for (index in [Part.Fm1.index(), Part.Fm3.index(), Part.Fm4.index(),
				Part.Psg2.index()]) {
			final part:Part = index;
			pattern.lane(part).add(new Note(0, 96, 60));
		}

		final said = read(held);
		final party = said.party;

		says("the party is the channels a song uses",
			party != null && party.size[0] == 4 && party.size[1] == Part.COUNT,
			party == null ? "none" : party.size[0] + " of " + party.size[1]);

		says("and the census counts them by family",
			StringTools.startsWith(said.assets.large_text, "3 FM, 1 PSG"),
			said.assets.large_text);
	}

	static function played():Void {
		final held = made();
		final session = within(held);

		session.song.patterns[0].lane(Part.Fm1).add(new Note(0, 96, 60));
		session.song.tracks[0].add(new mdd.song.Clip(0, 0, 384));

		session.transport.play();

		final said = read(held);

		says("playing says the bar it is on",
			StringTools.startsWith(said.state, "Playing bar 1."), said.state);

		says("and the badge changes with it", said.assets.small_image == held.badgePlaying,
			said.assets.small_image);

		says("and a song with an end gets a countdown", said.timestamps.end != null,
			said.timestamps.end == null ? "none"
				: Presence.whole(said.timestamps.end - said.timestamps.start) + " ms long");

		held.busy = "Exporting";

		says("and work in hand takes the line over",
			read(held).state == "Exporting"
				&& read(held).assets.small_image == held.badgeWorking,
			read(held).state);

		held.busy = "";
		held.level = Presence.PLAIN;

		says("and the plain level keeps the song's length back",
			read(held).timestamps.end == null && read(held).timestamps.start > 0,
			"start only");
	}

	static function nameless():Void {
		final held = made();

		held.cover = "";
		held.badgePlaying = "";
		held.badgeStopped = "";
		held.badgeWorking = "";

		final said = read(held);

		says("an asset with no name is left out entirely",
			said.assets.large_image == null && said.assets.small_image == null
				&& said.assets.small_text == null,
			"large text only");

		says("and what is left is still well formed",
			said.assets.large_text != "" && said.details == "untitled",
			said.assets.large_text);
	}

	static function paced():Void {
		final held = made();

		var sends = 0;
		for (index in 0...20) if (held.due(1.0)) sends++;

		says("an update waits out discord's rate limit", sends == 4,
			sends + " in 20 seconds, one every " + Presence.SEND_EVERY);

		final fresh = made();

		var dials = 0;
		for (index in 0...120) if (fresh.redials(1.0)) dials++;

		says("and a retry waits before dialling again", dials == 10,
			dials + " in 120 seconds, one every " + Presence.DIAL_EVERY);
	}

	static function stamped():Void {
		final now = Presence.whole(1759400000000.0);

		says("an epoch stamp is written out in full",
			now == "1759400000000" && now.indexOf("e") < 0, now);

		says("and a clock reads as minutes and seconds",
			Presence.clock(125) == "2:05" && Presence.clock(0) == "0:00"
				&& Presence.clock(-4) == "0:00", Presence.clock(125));
	}

	static function hosted():Void {
		says("an empty application id never opens a socket",
			!Discord.open("") && !Discord.live() && !Discord.ready(),
			Std.string(Discord.fault()));

		says("and polling a closed connection does nothing", Discord.poll() == 0,
			Discord.took() + " frames ever");

		says("and the process id is what discord is told", Discord.pid() > 0,
			Std.string(Discord.pid()));

		Discord.shut();

		says("and shutting one that was never open is safe", !Discord.live(),
			"closed");
	}
}
