package mdd.song.edit;

/**
	Several commands that undo as one step.

	A drag is the usual case: it produces a command a frame while it runs, and the
	person who dragged expects one undo to put it back rather than a hundred.
**/
final class Together implements Command {
	final said:String;
	final parts:Array<Command> = [];

	/**
		Builds an empty group.

		@param said The label the whole group answers with.
	**/
	public function new(said:String) {
		this.said = said;
	}

	/**
		@return How many commands are in it.
	**/
	public inline function count():Int {
		return parts.length;
	}

	/**
		Adds one to the end of the group.

		@param command What to add.
	**/
	public function also(command:Command):Void {
		parts.push(command);
	}

	/**
		Applies every command in order.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		for (command in parts) command.apply(song);
	}

	/**
		Reverts every command in the opposite order, which is the only order that puts
		the song back where the commands overlapped.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		var index = parts.length;
		while (index-- > 0) parts[index].revert(song);
	}

	/**
		@return The label the group was built with.
	**/
	public function label():String {
		return said;
	}
}
