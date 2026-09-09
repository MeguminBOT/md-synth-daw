package mdd.ui;

/**
	What an input event is.
**/
enum abstract Kind(Int) from Int to Int {
	var None = 0;
	var PointerDown;
	var PointerUp;
	var PointerMove;
	var Wheel;
	var KeyDown;
	var KeyUp;
	var Text;
	var Enter;
	var Leave;
}
