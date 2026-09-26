package mdd.app;

import mdd.host.Shell;

@:unreflective

/**
	Registering what this application writes with the desktop, and taking it back: a project and
	a preset, each with the name the build gives it.

	It is the shell binding with the names filled in from the build, so nothing else
	has to know what the application calls itself.
**/
final class Associations {

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
	public static function takes():Bool {
		final project = Shell.associate(suffix(), identity(), mdd.Config.FORMAT, mdd.Config.MIME,
			mdd.Config.TITLE, mdd.Config.DESCRIPTION) != 0;

		final preset = Shell.associate(presetSuffix(), presetIdentity(), mdd.Config.PRESET_FORMAT,
			mdd.Config.PRESET_MIME, mdd.Config.TITLE, mdd.Config.DESCRIPTION) != 0;

		final bank = Shell.associate(bankSuffix(), bankIdentity(), mdd.Config.BANK_FORMAT,
			mdd.Config.BANK_MIME, mdd.Config.TITLE, mdd.Config.DESCRIPTION) != 0;

		return project && preset && bank;
	}

	/**
		Unregisters it, taking back everything that was written.

		@return Whether it was taken back.
	**/
	public static function drops():Bool {
		final project = Shell.forget(suffix(), identity()) != 0;
		final preset = Shell.forget(presetSuffix(), presetIdentity()) != 0;
		final bank = Shell.forget(bankSuffix(), bankIdentity()) != 0;

		return project && preset && bank;
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

	static inline function presetSuffix():String {
		return "." + mdd.Config.PRESET;
	}

	static inline function presetIdentity():String {
		#if windows
		return mdd.Config.SHORT + ".preset";
		#else
		return mdd.Config.SHORT;
		#end
	}

	static inline function bankSuffix():String {
		return "." + mdd.Config.BANK;
	}

	static inline function bankIdentity():String {
		#if windows
		return mdd.Config.SHORT + ".bank";
		#else
		return mdd.Config.SHORT;
		#end
	}
}
