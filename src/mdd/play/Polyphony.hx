package mdd.play;

enum abstract Polyphony(Int) from Int to Int {
	var Strict = 0;
	var Stealing = 1;
	var Arpeggio = 2;

	public function name():String {
		return switch (cast this : Polyphony) {
			case Strict: "strict";
			case Stealing: "stealing";
			case Arpeggio: "arpeggio";
		}
	}
}
