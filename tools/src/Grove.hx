class Grove {
	public var path(default, null):String;
	public var suffix(default, null):String;
	public var skip(default, null):Array<String>;
	public var include(default, null):String;

	public function new(path:String, suffix:String, skip:String, include:String = "") {
		this.path = path;
		this.suffix = suffix;
		this.skip = skip == "" ? [] : skip.split(",");
		this.include = include;
	}

	public function wanted(name:String):Bool {
		if (!StringTools.endsWith(name, suffix)) return false;

		final stem = name.substr(0, name.length - suffix.length);
		for (held in skip) if (StringTools.trim(held) == stem) return false;

		return true;
	}
}
