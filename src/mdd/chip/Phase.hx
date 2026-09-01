package mdd.chip;

enum abstract Phase(Int) from Int to Int {
	var Attack = 0;
	var Decay = 1;
	var Sustain = 2;
	var Release = 3;
}
