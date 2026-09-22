package mdd;

/**
	Putting names in the order a person reads them, so `Hit 2` comes before `Hit 10` and
	`bass` sits beside `Bass`. Every list of names the application orders goes through it: the hits
	of a kit, the presets in a bank and the banks in the browser.
**/
@:unreflective
final class Names {
	/**
		Compares two names the way a person reads them.

		A run of digits is compared as the number it spells and everything else letter by
		letter regardless of case. Names that differ only in case or in leading noughts are
		told apart afterwards, so no two different names ever compare equal. Nothing is
		allocated for a name in plain ASCII, so a sort of a thousand of them costs no garbage; a
		letter past it is lowered through a string of its own.

		@param one A name.
		@param two Another.
		@return Below nought where the first comes first, above nought where the second does.
	**/
	public static function inOrder(one:String, two:String):Int {
		var atLeft = 0;
		var atRight = 0;

		while (atLeft < one.length && atRight < two.length) {
			final codeLeft = folded(StringTools.fastCodeAt(one, atLeft));
			final codeRight = folded(StringTools.fastCodeAt(two, atRight));

			if (!digit(codeLeft) || !digit(codeRight)) {
				if (codeLeft != codeRight) return codeLeft - codeRight;

				atLeft++;
				atRight++;
				continue;
			}

			var endLeft = atLeft;
			while (endLeft < one.length && digit(StringTools.fastCodeAt(one, endLeft))) endLeft++;

			var endRight = atRight;
			while (endRight < two.length && digit(StringTools.fastCodeAt(two, endRight))) endRight++;

			while (atLeft < endLeft - 1 && StringTools.fastCodeAt(one, atLeft) == "0".code) atLeft++;
			while (atRight < endRight - 1 && StringTools.fastCodeAt(two, atRight) == "0".code) atRight++;

			final wideLeft = endLeft - atLeft;
			final wideRight = endRight - atRight;

			if (wideLeft != wideRight) return wideLeft - wideRight;

			for (step in 0...wideLeft) {
				final apart = StringTools.fastCodeAt(one, atLeft + step)
					- StringTools.fastCodeAt(two, atRight + step);

				if (apart != 0) return apart;
			}

			atLeft = endLeft;
			atRight = endRight;
		}

		final restLeft = one.length - atLeft;
		final restRight = two.length - atRight;

		if (restLeft != restRight) return restLeft - restRight;

		return one < two ? -1 : (one > two ? 1 : 0);
	}

	/**
		@param code A character code.
		@return It in lower case, where it is a letter that has one.
	**/
	static inline function folded(code:Int):Int {
		if (code >= "A".code && code <= "Z".code) return code + 32;
		if (code < 0xC0) return code;

		return String.fromCharCode(code).toLowerCase().charCodeAt(0);
	}

	static inline function digit(code:Int):Bool {
		return code >= "0".code && code <= "9".code;
	}
}
