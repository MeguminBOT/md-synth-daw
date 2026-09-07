package mdd.app;

import mdd.host.Shell;

@:unreflective
final class Associations {
	public static inline function available():Bool {
		return Shell.supported() != 0;
	}

	public static inline function holds():Bool {
		return Shell.associated(suffix(), identity()) != 0;
	}

	public static inline function takes():Bool {
		return Shell.associate(suffix(), identity(), mdd.Config.FORMAT, mdd.Config.MIME,
			mdd.Config.TITLE, mdd.Config.DESCRIPTION) != 0;
	}

	public static inline function drops():Bool {
		return Shell.forget(suffix(), identity()) != 0;
	}

	static inline function suffix():String {
		return "." + mdd.Config.SUFFIX;
	}

	static inline function identity():String {
		#if windows
		return mdd.Config.SHORT + ".project";
		#else
		return mdd.Config.SHORT;
		#end
	}
}
