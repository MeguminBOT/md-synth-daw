package mdd.format;

/**
	Writes JSON, and reads it back through `parse`.

	It is written here rather than taken from the standard library because a project
	file has to be byte identical between two saves of the same song, which means the
	writer decides the key order rather than a map deciding it.
**/
class Json {
	final out:StringBuf = new StringBuf();
	final filled:Array<Bool> = [];
	var keyed:Bool = false;

	/**
		Builds an empty writer.
	**/
	public function new() {}

	/**
		@return Everything written so far.
	**/
	public function toString():String {
		return out.toString();
	}

	/**
		Writes the comma and the indentation before the next value.
	**/
	function lead():Void {
		if (keyed) {
			keyed = false;
			return;
		}

		if (filled.length == 0) return;

		if (filled[filled.length - 1]) out.add(",");
		filled[filled.length - 1] = true;

		out.add("\n");
		for (i in 0...filled.length) out.add("  ");
	}

	/**
		Closes a table or a list.

		@param mark The closing bracket to write.
	**/
	function shut(mark:String):Void {
		final had = filled.pop();

		if (had) {
			out.add("\n");
			for (i in 0...filled.length) out.add("  ");
		}

		out.add(mark);
	}

	/**
		Opens a table.
	**/
	public function open():Void {
		lead();
		out.add("{");
		filled.push(false);
	}

	/**
		Closes a table.
	**/
	public function close():Void {
		shut("}");
	}

	/**
		Opens a list.
	**/
	public function list():Void {
		lead();
		out.add("[");
		filled.push(false);
	}

	/**
		Closes a list.
	**/
	public function ends():Void {
		shut("]");
	}

	/**
		Writes a key. The value comes next.

		@param name The key.
	**/
	public function key(name:String):Void {
		lead();
		out.add(quoted(name));
		out.add(": ");

		if (filled.length > 0) filled[filled.length - 1] = true;
		keyed = true;
	}

	/**
		Writes a value already in its written form.

		@param text The value as it should appear.
	**/
	function value(text:String):Void {
		lead();
		out.add(text);
	}

	/**
		Writes a string, escaped.

		@param said The text.
	**/
	public function text(said:String):Void {
		value(quoted(said));
	}

	/**
		Writes a whole number.

		@param said The number.
	**/
	public function whole(said:Int):Void {
		value(Std.string(said));
	}

	/**
		Writes a number, with no trailing nought where it is whole, so two saves of the
		same song give the same bytes.

		@param said The number.
	**/
	public function number(said:Float):Void {
		value(said == Std.int(said) ? Std.string(Std.int(said)) : Std.string(said));
	}

	/**
		Writes true or false.

		@param said The flag.
	**/
	public function flag(said:Bool):Void {
		value(said ? "true" : "false");
	}

	/**
		Writes null.
	**/
	public function nothing():Void {
		value("null");
	}

	/**
		Writes a list of whole numbers on one line, which is what a long run of sample
		bytes wants.

		@param said The numbers.
	**/
	public function wholes(said:Array<Int>):Void {
		list();
		for (one in said) whole(one);
		ends();
	}

	/**
		@param said Some text.
		@return It as a JSON string, quotes and escapes included.
	**/
	public static function quoted(said:String):String {
		final out = new StringBuf();
		out.add("\"");

		for (i in 0...said.length) {
			final code = said.charCodeAt(i);

			switch (code) {
				case 34: out.add("\\\"");
				case 92: out.add("\\\\");
				case 8: out.add("\\b");
				case 12: out.add("\\f");
				case 10: out.add("\\n");
				case 13: out.add("\\r");
				case 9: out.add("\\t");
				case _:
					if (code < 32) out.add("\\u" + StringTools.hex(code, 4).toLowerCase());
					else out.addChar(code);
			}
		}

		out.add("\"");
		return out.toString();
	}

	/**
		Reads a document.

		@param text The document.
		@return Its root node.
	**/
	public static function parse(text:String):Node {
		final reader = new Reader(text);
		final node = reader.value();
		return node;
	}
}

/**
	Walks a document once, left to right, holding the position it has reached.

	One reader reads one document. A malformed document stops the walk where it
	stops rather than throwing, so a truncated file reads as the nodes that were
	whole.
**/
private class Reader {
	/**
		How many tables and lists may be open at once.

		A document nests as deep as it likes and each level costs a pair of stack frames,
		so without a ceiling a file of nothing but opening brackets runs the stack out and
		takes the process down before a single value is read. The deepest a project, a
		preset library or a release document actually reaches is six.
	**/
	static inline final DEEPEST = 128;

	final said:String;
	var at:Int = 0;
	var deep:Int = 0;

	public function new(said:String) {
		this.said = said;
	}

	function skip():Void {
		while (at < said.length) {
			final code = StringTools.fastCodeAt(said, at);
			if (code == 32 || code == 9 || code == 10 || code == 13) at++;
			else break;
		}
	}

	public function value():Node {
		skip();
		if (at >= said.length) return Node.EMPTY;

		return switch (StringTools.fastCodeAt(said, at)) {
			case 123: deep >= DEEPEST ? Node.EMPTY : table();
			case 91: deep >= DEEPEST ? Node.EMPTY : list();
			case 34: Node.words(string());
			case 116: word("true", Node.flag(true));
			case 102: word("false", Node.flag(false));
			case 110: word("null", new Node(Node.NOTHING));
			case _: Node.counted(digits());
		}
	}

	function word(spelling:String, node:Node):Node {
		at += spelling.length;
		return node;
	}

	function table():Node {
		final node = new Node(Node.TABLE);

		at++;
		deep++;

		while (true) {
			skip();
			if (at >= said.length) break;

			if (StringTools.fastCodeAt(said, at) == 125) {
				at++;
				break;
			}

			if (StringTools.fastCodeAt(said, at) == 44) {
				at++;
				continue;
			}

			final began = at;
			final key = string();

			skip();
			if (at < said.length && StringTools.fastCodeAt(said, at) == 58) at++;

			node.put(key, value());

			if (at <= began) break;
		}

		deep--;
		return node;
	}

	function list():Node {
		final node = new Node(Node.LIST);

		at++;
		deep++;

		while (true) {
			skip();
			if (at >= said.length) break;

			if (StringTools.fastCodeAt(said, at) == 93) {
				at++;
				break;
			}

			if (StringTools.fastCodeAt(said, at) == 44) {
				at++;
				continue;
			}

			final began = at;
			node.push(value());

			if (at <= began) break;
		}

		deep--;
		return node;
	}

	function string():String {
		skip();
		if (at >= said.length || StringTools.fastCodeAt(said, at) != 34) return "";

		at++;

		final from = at;

		while (at < said.length) {
			final code = StringTools.fastCodeAt(said, at);

			if (code == 34) {
				final plain = said.substr(from, at - from);
				at++;

				return plain;
			}

			if (code == 92) break;

			at++;
		}

		final out = new StringBuf();
		out.addSub(said, from, at - from);

		while (at < said.length) {
			final code = StringTools.fastCodeAt(said, at);

			if (code == 34) {
				at++;
				break;
			}

			if (code != 92) {
				out.addChar(code);
				at++;
				continue;
			}

			at++;
			final marked = StringTools.fastCodeAt(said, at);
			at++;

			switch (marked) {
				case 34: out.addChar(34);
				case 92: out.addChar(92);
				case 47: out.addChar(47);
				case 98: out.addChar(8);
				case 102: out.addChar(12);
				case 110: out.addChar(10);
				case 114: out.addChar(13);
				case 116: out.addChar(9);
				case 117:
					final hex = said.substr(at, 4);
					at += 4;

					final code = Std.parseInt("0x" + hex);
					out.addChar(code == null ? 63 : code);
				case _:
					out.addChar(marked);
			}
		}

		return out.toString();
	}

	function digits():Float {
		final from = at;

		while (at < said.length) {
			final code = StringTools.fastCodeAt(said, at);
			final part = (code >= 48 && code <= 57) || code == 45 || code == 43 || code == 46
				|| code == 101 || code == 69;

			if (!part) break;
			at++;
		}

		final read = Std.parseFloat(said.substring(from, at));
		return Math.isNaN(read) ? 0 : read;
	}
}
