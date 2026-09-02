class Grove {
	public var path(default, null):String;
	public var suffix(default, null):String;
	public var skip(default, null):Array<String>;

	public function new(path:String, suffix:String, skip:String) {
		this.path = path;
		this.suffix = suffix;
		this.skip = skip == "" ? [] : skip.split(",");
	}

	public function wanted(name:String):Bool {
		if (!StringTools.endsWith(name, suffix)) return false;

		final stem = name.substr(0, name.length - suffix.length);
		for (held in skip) if (StringTools.trim(held) == stem) return false;

		return true;
	}
}
