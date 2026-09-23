package mdd.host;

@:include("filter.h")

/**
	The resampler's kernels, run eight products at a time where the processor can, which
	both kinds this builds for can. Every call runs on the render thread and allocates
	nothing, and the answer is the same whichever processor gives it.
**/
extern class Filter {
	/**
		Runs a left and a right history through one kernel at once, writing the two sums
		into `sums`, the left first.
	**/
	@:native("mdd_filter_pair")
	public static function pair(left:cpp.RawConstPointer<Float>, right:cpp.RawConstPointer<Float>,
		weights:cpp.RawConstPointer<Float>, taps:Int, sums:cpp.RawPointer<Float>):Void;

	/**
		Runs one history through a kernel and answers with the sum. `taps` is a multiple of
		eight, as it is for `pair`.
	**/
	@:native("mdd_filter")
	public static function one(values:cpp.RawConstPointer<Float>,
		weights:cpp.RawConstPointer<Float>, taps:Int):Float;
}
