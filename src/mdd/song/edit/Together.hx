package mdd.song.edit;

final class Together implements Command {
	final said:String;
	final parts:Array<Command> = [];

	public function new(said:String) {
		this.said = said;
	}

	public inline function count():Int {
		return parts.length;
	}

	public function also(command:Command):Void {
		parts.push(command);
	}

	public function apply(song:Song):Void {
		for (command in parts) command.apply(song);
	}

	public function revert(song:Song):Void {
		var index = parts.length;
		while (index-- > 0) parts[index].revert(song);
	}

	public function label():String {
		return said;
	}
}
