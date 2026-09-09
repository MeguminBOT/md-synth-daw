/**
	A directory of native sources named as a tree rather than one by one.

	Listing a hundred and thirty seven opus files by hand in the build file would be
	unreadable and would rot, so a tree names a folder, a suffix and the stems to skip,
	and the build walks it.
**/
class Grove {
	/**
		The folder to walk.
	**/
	public var path(default, null):String;

	/**
		Which files to take, by suffix.
	**/
	public var suffix(default, null):String;

	/**
		File stems to leave out, which is how a library demo program stays out of the
		build.
	**/
	public var skip(default, null):Array<String>;

	/**
		A folder to put on the include path along with the sources, or an empty string.
	**/
	public var include(default, null):String;

	/**
		Records a tree to walk.

		@param path The folder.
		@param suffix Which files to take.
		@param skip Stems to leave out, separated by commas.
		@param include A folder for the include path, or an empty string.
	**/
	public function new(path:String, suffix:String, skip:String, include:String = "") {
		this.path = path;
		this.suffix = suffix;
		this.skip = skip == "" ? [] : skip.split(",");
		this.include = include;
	}

	/**
		@param name A file name.
		@return Whether it should be compiled.
	**/
	public function wanted(name:String):Bool {
		if (!StringTools.endsWith(name, suffix)) return false;

		final stem = name.substr(0, name.length - suffix.length);
		for (held in skip) if (StringTools.trim(held) == stem) return false;

		return true;
	}
}
