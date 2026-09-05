package mdd.song.edit;

final class SetVelocity implements Command {
	final note:Note;
	final velocity:Int;

	var was:Int = 0;

	public function new(note:Note, velocity:Int) {
		this.note = note;
		this.velocity = velocity < 1 ? 1 : (velocity > 127 ? 127 : velocity);
	}

	public function apply(song:Song):Void {
		was = note.velocity;
		note.velocity = velocity;
	}

	public function revert(song:Song):Void {
		note.velocity = was;
	}

	public function label():String {
		return "set a velocity";
	}
}
