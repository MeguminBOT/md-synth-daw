package mdd.host;

/**
	What this copy was started with, read the way the platform keeps it.

	On Windows `Sys.args` is built from the narrow command line, which carries the system code page
	rather than UTF-8, so a project whose path had an accented letter in it never opened from a
	double click or a terminal. The wide command line is read instead there.
**/
class Arguments {
	/**
		@return Every argument after the program's own name, in UTF-8. Allocates a new array on
			every call.
	**/
	public static function all():Array<String> {
		final count = Instance.arguments();
		if (count < 0) return Sys.args();

		final out:Array<String> = [];
		for (index in 1...count) out.push((Instance.argument(index) : String));

		return out;
	}
}
