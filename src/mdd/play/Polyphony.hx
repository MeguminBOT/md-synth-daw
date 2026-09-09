package mdd.play;

/**
	What happens when more notes are asked for at once than a part has channels.

	`Strict` drops the note, which is what the hardware does and what a piece written
	for it should hear. `Stealing` gives the oldest voice away. `Arpeggio` cycles the
	extra notes through the channels there are.
**/
enum abstract Polyphony(Int) from Int to Int {
	var Strict = 0;
	var Stealing = 1;
	var Arpeggio = 2;

	/**
		@return The name of this behaviour in lower case, for a setting and for a report.
	**/
	public function name():String {
		return switch (cast this : Polyphony) {
			case Strict: "strict";
			case Stealing: "stealing";
			case Arpeggio: "arpeggio";
		}
	}
}
