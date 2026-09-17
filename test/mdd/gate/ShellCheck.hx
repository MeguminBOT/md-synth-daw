package mdd.gate;

import mdd.host.Instance;
import mdd.host.Shell;

@:unreflective
class ShellCheck {
	static var ran = 0;
	static var failed = 0;

	static inline final SUFFIX = ".mddgate";
	static inline final IDENTITY = "mdd-gate";
	static inline final LABEL = "MD Synth Gate File";
	static inline final MIME = "application/x-mddgate";
	static inline final NAME = "MD Synth Gate";
	static inline final ABOUT = "A file the gate registers and takes back";

	/**
		The flag that makes this program hand its last argument to the lock its second last argument
		names, and do nothing else: once as `Arguments` reads it and once, after a line break, as the
		runtime's own list does. That is how a check reads back what a child process received.
	**/
	static inline final HAND = "--hand";

	/**
		A path with letters from outside ASCII in three scripts, which is what a project name is free
		to hold.
	**/
	static inline final WORDED = "R:/projects/Für Elise ♫ 曲.mdsyn";

	public static function run(args:Array<String>):Int {
		if (args.indexOf(HAND) >= 0) {
			final given = mdd.host.Arguments.all();
			final plain = Sys.args();

			if (given.length < 2) return 1;

			final said = given[given.length - 1] + "\n" + plain[plain.length - 1];
			return Instance.hand(given[given.length - 2], said, 2000) != 0 ? 0 : 1;
		}

		ran = 0;
		failed = 0;

		Sys.println("  shell");

		handed();
		argued();

		if (Shell.supported() == 0) {
			Sys.println("    " + StringTools.rpad("associations", " ", 42)
				+ "this platform registers none, nothing to check");
			costing();

			Sys.println("    " + (ran - failed) + " of " + ran + " checks");
			Sys.println(failed == 0 ? "    passed" : "    failed");

			return failed == 0 ? 0 : 1;
		}

		round();
		guarded();
		costing();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	/**
		Reads what the process is costing twice, with work between the readings and
		then nothing. A reading is the span between two samples, so it only means
		anything if it is taken again regularly.
	**/
	static function costing():Void {
		mdd.host.Usage.start();
		mdd.host.Usage.cpu();

		final began = mdd.host.Sdl.ticks();
		var sum = 0.0;

		while (mdd.host.Sdl.ticks() - began < 0.30) {
			for (index in 0...20000) sum += Math.sqrt(index + sum % 7);
		}

		final busy = mdd.host.Usage.cpu();
		final ram = mdd.host.Usage.ram();

		says("a busy stretch reads as busy", busy > 0 && sum > 0,
			"0.3 s of work reads " + Math.round(busy * 100) / 100
			+ " per cent of the whole processor");

		says("and the memory it holds is a real number", ram > 1,
			"holding " + Math.round(ram) + " MB");

		final idleFrom = mdd.host.Sdl.ticks();
		while (mdd.host.Sdl.ticks() - idleFrom < 0.30) mdd.host.Sdl.sleep(0.01);

		final quiet = mdd.host.Usage.cpu();

		says("and a quiet one reads as quiet", quiet < busy,
			"0.3 s of sleeping reads " + Math.round(quiet * 100) / 100 + " against the "
			+ Math.round(busy * 100) / 100 + " the work read, so a reading is the span between two"
			+ " samples rather than the life of the process");

		mdd.host.Usage.stop();
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 42) + said + (ok ? "" : "   FAILED"));
	}

	/**
		A second copy hands what it was opened with to the copy holding the lock, which is what lets
		opening a project while the application runs open it in that window rather than stopping
		at a message. The lock is claimed under a name of the gate's own, so a copy of the
		application running beside the gate is left alone.
	**/
	static function handed():Void {
		final name = "mdd-gate-" + Std.random(0x7FFFFFFF);
		final worded = WORDED;

		final claimed = Instance.claim(name) != 0;
		final early = Instance.take();
		final listening = Instance.listen(name) != 0;
		final nothing = Instance.take();

		final gave = Instance.hand(name, worded, 1000) != 0;
		final took = Instance.take();
		final text = took < 0 ? "" : (Instance.taken() : String);

		says("a second copy hands its file over", claimed && early < 0 && listening && nothing < 0
			&& gave && text == worded,
			"the lock taken, nothing to read before listening or before a handover, and '" + text
			+ "' read back whole, " + took + " bytes");

		final knocked = Instance.hand(name, "", 1000) != 0;
		final empty = Instance.take();
		final again = Instance.hand(name, "again", 1000) != 0;
		final twice = Instance.take();
		final second = twice < 0 ? "" : (Instance.taken() : String);

		says("and one with no file only knocks", knocked && empty == 0 && again && twice == 5
			&& second == "again",
			"an empty handover reads as " + empty + " bytes, and the channel takes another after it, '"
			+ second + "'");

		Instance.release();

		final began = mdd.host.Sdl.ticks();
		final refused = Instance.hand(name, worded, 100) == 0;
		final waited = mdd.host.Sdl.ticks() - began;

		says("and a lock nobody holds refuses it", refused && waited < 1.0,
			"handing over with nothing listening gave up after " + Math.round(waited * 1000) + " ms,"
			+ " which is when the message that a copy is running goes up instead");
	}

	/**
		A second copy started as its own process hands a path outside ASCII over whole. The runtime
		builds its argument list from the narrow command line, which on Windows carries the system code
		page, so a project named with an accented letter never opened from a double click.
	**/
	static function argued():Void {
		final name = "mdd-gate-" + Std.random(0x7FFFFFFF);

		Instance.claim(name);
		Instance.listen(name);

		var took = -1;
		var code = -1;

		try {
			final child = new sys.io.Process(Sys.programPath(), ["shell", HAND, name, WORDED]);
			final began = mdd.host.Sdl.ticks();

			while (took < 0 && mdd.host.Sdl.ticks() - began < 5.0) {
				took = Instance.take();
				if (took < 0) mdd.host.Sdl.sleep(0.01);
			}

			code = child.exitCode();
			child.close();
		} catch (e:Dynamic) {
			Sys.println("    " + e);
		}

		final parts:Array<String> = took < 0 ? [] : (Instance.taken() : String).split("\n");
		final given = parts.length > 0 ? parts[0] : "";
		final plain = parts.length > 1 ? parts[1] : "";

		Instance.release();

		says("and from another process, whole", code == 0 && given == WORDED,
			"a child started with '" + WORDED + "' handed back '" + given + "', where the runtime's own"
			+ " list read '" + plain + "'");
	}

	static function round():Void {
		Shell.forget(SUFFIX, IDENTITY);

		says("nothing is registered to begin with", Shell.associated(SUFFIX, IDENTITY) == 0,
			"the suffix opens with nothing this binary wrote");

		final took = Shell.associate(SUFFIX, IDENTITY, LABEL, MIME, NAME, ABOUT) != 0;

		says("registering says it worked", took, took ? "every key written" : "a key refused");

		says("and the suffix reads back as this binary", Shell.associated(SUFFIX, IDENTITY) == 1,
			"the handler names the running executable");

		says("and registering twice is the same answer",
			Shell.associate(SUFFIX, IDENTITY, LABEL, MIME, NAME, ABOUT) != 0
			&& Shell.associated(SUFFIX, IDENTITY) == 1, "written again with nothing left over");

		final dropped = Shell.forget(SUFFIX, IDENTITY) != 0;

		says("unregistering says it worked", dropped,
			dropped ? "every key taken back" : "a key would not go");

		says("and the suffix reads back as nothing", Shell.associated(SUFFIX, IDENTITY) == 0,
			"the handler is gone");

		says("and unregistering twice is safe", Shell.forget(SUFFIX, IDENTITY) != 0
			&& Shell.associated(SUFFIX, IDENTITY) == 0, "nothing to take back and it said so");

		says("and it leaves no key behind", Shell.leftovers(SUFFIX, IDENTITY) == 0,
			"the suffix, the identity and the application entry are all gone");
	}

	static function guarded():Void {
		says("another identity is not this one",
			Shell.associated(SUFFIX, "mdd-gate-other") == 0,
			"a suffix registered elsewhere does not read as ours");

		says("and the shipped suffix is left alone",
			Shell.associated("." + mdd.Config.SUFFIX, IDENTITY) == 0,
			"." + mdd.Config.SUFFIX + " was never touched by this program");
	}
}
