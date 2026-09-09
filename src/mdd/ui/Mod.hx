package mdd.ui;

/**
	Which modifier keys are held, as bits, so several can be at once.
**/
enum abstract Mod(Int) from Int to Int {
	var None = 0;
	var Shift = 1;
	var Ctrl = 2;
	var Alt = 4;
	var Gui = 8;
}
