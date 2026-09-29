package mdd.host;

@:include("installer.h")

/**
	What the Windows installer recorded about a copy it installed.

	Who a copy was installed for decides how it is updated: one installed for every account can only
	be replaced by an administrator, and the installer has to be told which of the two to update or it
	puts a second copy beside the first. Where the copy sits does not say which it is, because the
	folder is whatever was chosen when it was installed, so this reads the installer's own entry.
**/
extern class Installer {
	/**
		@param identity The installer's application identity, `mdd.Config.IDENTITY`.
		@param where The folder the running copy sits in.
		@return Nonzero where the installer put that folder there for every account. Nought for a copy
			installed for the current account alone, for one the installer did not put there, and
			away from Windows.
	**/
	@:native("mdd_installer_everyone")
	public static function everyone(identity:cpp.ConstCharStar, where:cpp.ConstCharStar):Int;
}
