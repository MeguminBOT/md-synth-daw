package mdd.gate;

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

	public static function run(args:Array<String>):Int {
		ran = 0;
		failed = 0;

		Sys.println("  shell");

		if (Shell.supported() == 0) {
			Sys.println("    " + StringTools.rpad("associations", " ", 42)
				+ "this platform registers none, nothing to check");
			Sys.println("    passed");

			return 0;
		}

		round();
		guarded();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 42) + said + (ok ? "" : "   FAILED"));
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
