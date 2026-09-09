package mdd.app;

import mdd.host.Shell;

@:unreflective

/**
	Registering the project suffix with the desktop, and taking it back.

	It is the shell binding with the names filled in from the build, so nothing else
	has to know what the application calls itself.
**/
final class Associations {
	/**
		@return Whether this platform can register a suffix at all.
	**/
	public static inline function available():Bool {
		return Shell.supported() != 0;
	}

	/**
		@return Whether the suffix is registered to this application.
	**/
	public static inline function holds():Bool {
		return Shell.associated(suffix(), identity()) != 0;
	}

	/**
		Registers the suffix.

		@return Whether every key was written.
	**/
	public static inline function takes():Bool {
		return Shell.associate(suffix(), identity(), mdd.Config.FORMAT, mdd.Config.MIME,
			mdd.Config.TITLE, mdd.Config.DESCRIPTION) != 0;
	}

	/**
		Unregisters it, taking back everything that was written.

		@return Whether it was taken back.
	**/
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
