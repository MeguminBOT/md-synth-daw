/*
	MD Synth DAW
	https://github.com/MeguminBOT/md-synth-daw

	MIT License

	Copyright (c) 2026 MeguminBOT and the md-synth-daw contributors

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

	SPDX-License-Identifier: MIT
*/

/**
 * The resampler's kernels, eight products at a time.
 *
 * Two lanes of four registers on x86-64 and on arm64, which is SSE2 and NEON, both of
 * which every processor of either kind has. Anything else sums the same eight lanes one
 * at a time and adds them in the same order, so all three give the same answer.
 */
#include "filter.h"

#if defined(__x86_64__) || defined(_M_X64)

#include <emmintrin.h>

extern "C" void mdd_filter_pair(const double *left, const double *right, const double *weights,
		int taps, double *sums) {
	__m128d left0 = _mm_setzero_pd();
	__m128d left1 = _mm_setzero_pd();
	__m128d left2 = _mm_setzero_pd();
	__m128d left3 = _mm_setzero_pd();
	__m128d right0 = _mm_setzero_pd();
	__m128d right1 = _mm_setzero_pd();
	__m128d right2 = _mm_setzero_pd();
	__m128d right3 = _mm_setzero_pd();

	for (int at = 0; at < taps; at += 8) {
		const __m128d weight0 = _mm_loadu_pd(weights + at);
		const __m128d weight1 = _mm_loadu_pd(weights + at + 2);
		const __m128d weight2 = _mm_loadu_pd(weights + at + 4);
		const __m128d weight3 = _mm_loadu_pd(weights + at + 6);

		left0 = _mm_add_pd(left0, _mm_mul_pd(_mm_loadu_pd(left + at), weight0));
		left1 = _mm_add_pd(left1, _mm_mul_pd(_mm_loadu_pd(left + at + 2), weight1));
		left2 = _mm_add_pd(left2, _mm_mul_pd(_mm_loadu_pd(left + at + 4), weight2));
		left3 = _mm_add_pd(left3, _mm_mul_pd(_mm_loadu_pd(left + at + 6), weight3));

		right0 = _mm_add_pd(right0, _mm_mul_pd(_mm_loadu_pd(right + at), weight0));
		right1 = _mm_add_pd(right1, _mm_mul_pd(_mm_loadu_pd(right + at + 2), weight1));
		right2 = _mm_add_pd(right2, _mm_mul_pd(_mm_loadu_pd(right + at + 4), weight2));
		right3 = _mm_add_pd(right3, _mm_mul_pd(_mm_loadu_pd(right + at + 6), weight3));
	}

	const __m128d leftAll = _mm_add_pd(_mm_add_pd(left0, left1), _mm_add_pd(left2, left3));
	const __m128d rightAll = _mm_add_pd(_mm_add_pd(right0, right1), _mm_add_pd(right2, right3));

	sums[0] = _mm_cvtsd_f64(leftAll) + _mm_cvtsd_f64(_mm_unpackhi_pd(leftAll, leftAll));
	sums[1] = _mm_cvtsd_f64(rightAll) + _mm_cvtsd_f64(_mm_unpackhi_pd(rightAll, rightAll));
}

extern "C" double mdd_filter(const double *values, const double *weights, int taps) {
	__m128d sum0 = _mm_setzero_pd();
	__m128d sum1 = _mm_setzero_pd();
	__m128d sum2 = _mm_setzero_pd();
	__m128d sum3 = _mm_setzero_pd();

	for (int at = 0; at < taps; at += 8) {
		sum0 = _mm_add_pd(sum0, _mm_mul_pd(_mm_loadu_pd(values + at), _mm_loadu_pd(weights + at)));
		sum1 = _mm_add_pd(sum1, _mm_mul_pd(_mm_loadu_pd(values + at + 2),
			_mm_loadu_pd(weights + at + 2)));
		sum2 = _mm_add_pd(sum2, _mm_mul_pd(_mm_loadu_pd(values + at + 4),
			_mm_loadu_pd(weights + at + 4)));
		sum3 = _mm_add_pd(sum3, _mm_mul_pd(_mm_loadu_pd(values + at + 6),
			_mm_loadu_pd(weights + at + 6)));
	}

	const __m128d all = _mm_add_pd(_mm_add_pd(sum0, sum1), _mm_add_pd(sum2, sum3));
	return _mm_cvtsd_f64(all) + _mm_cvtsd_f64(_mm_unpackhi_pd(all, all));
}

#elif defined(__aarch64__) || defined(_M_ARM64)

#include <arm_neon.h>

extern "C" void mdd_filter_pair(const double *left, const double *right, const double *weights,
		int taps, double *sums) {
	float64x2_t left0 = vdupq_n_f64(0.0);
	float64x2_t left1 = vdupq_n_f64(0.0);
	float64x2_t left2 = vdupq_n_f64(0.0);
	float64x2_t left3 = vdupq_n_f64(0.0);
	float64x2_t right0 = vdupq_n_f64(0.0);
	float64x2_t right1 = vdupq_n_f64(0.0);
	float64x2_t right2 = vdupq_n_f64(0.0);
	float64x2_t right3 = vdupq_n_f64(0.0);

	for (int at = 0; at < taps; at += 8) {
		const float64x2_t weight0 = vld1q_f64(weights + at);
		const float64x2_t weight1 = vld1q_f64(weights + at + 2);
		const float64x2_t weight2 = vld1q_f64(weights + at + 4);
		const float64x2_t weight3 = vld1q_f64(weights + at + 6);

		left0 = vaddq_f64(left0, vmulq_f64(vld1q_f64(left + at), weight0));
		left1 = vaddq_f64(left1, vmulq_f64(vld1q_f64(left + at + 2), weight1));
		left2 = vaddq_f64(left2, vmulq_f64(vld1q_f64(left + at + 4), weight2));
		left3 = vaddq_f64(left3, vmulq_f64(vld1q_f64(left + at + 6), weight3));

		right0 = vaddq_f64(right0, vmulq_f64(vld1q_f64(right + at), weight0));
		right1 = vaddq_f64(right1, vmulq_f64(vld1q_f64(right + at + 2), weight1));
		right2 = vaddq_f64(right2, vmulq_f64(vld1q_f64(right + at + 4), weight2));
		right3 = vaddq_f64(right3, vmulq_f64(vld1q_f64(right + at + 6), weight3));
	}

	const float64x2_t leftAll = vaddq_f64(vaddq_f64(left0, left1), vaddq_f64(left2, left3));
	const float64x2_t rightAll = vaddq_f64(vaddq_f64(right0, right1), vaddq_f64(right2, right3));

	sums[0] = vgetq_lane_f64(leftAll, 0) + vgetq_lane_f64(leftAll, 1);
	sums[1] = vgetq_lane_f64(rightAll, 0) + vgetq_lane_f64(rightAll, 1);
}

extern "C" double mdd_filter(const double *values, const double *weights, int taps) {
	float64x2_t sum0 = vdupq_n_f64(0.0);
	float64x2_t sum1 = vdupq_n_f64(0.0);
	float64x2_t sum2 = vdupq_n_f64(0.0);
	float64x2_t sum3 = vdupq_n_f64(0.0);

	for (int at = 0; at < taps; at += 8) {
		sum0 = vaddq_f64(sum0, vmulq_f64(vld1q_f64(values + at), vld1q_f64(weights + at)));
		sum1 = vaddq_f64(sum1, vmulq_f64(vld1q_f64(values + at + 2), vld1q_f64(weights + at + 2)));
		sum2 = vaddq_f64(sum2, vmulq_f64(vld1q_f64(values + at + 4), vld1q_f64(weights + at + 4)));
		sum3 = vaddq_f64(sum3, vmulq_f64(vld1q_f64(values + at + 6), vld1q_f64(weights + at + 6)));
	}

	const float64x2_t all = vaddq_f64(vaddq_f64(sum0, sum1), vaddq_f64(sum2, sum3));
	return vgetq_lane_f64(all, 0) + vgetq_lane_f64(all, 1);
}

#else

/**
 * Sums eight lanes one at a time: lane `j` takes every product whose place leaves `j`
 * over when divided by eight, which is what the two lanes of four registers hold.
 *
 * @param values The history, newest first.
 * @param weights The kernel.
 * @param taps How many of each, a multiple of eight.
 * @return The sum, with the lanes added in the order the vector paths add them.
 */
static double mdd_filter_lanes(const double *values, const double *weights, int taps) {
	double lane[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };

	for (int at = 0; at < taps; at += 8) {
		for (int each = 0; each < 8; each++) {
			const double product = values[at + each] * weights[at + each];
			lane[each] = lane[each] + product;
		}
	}

	const double even = (lane[0] + lane[2]) + (lane[4] + lane[6]);
	const double odd = (lane[1] + lane[3]) + (lane[5] + lane[7]);
	return even + odd;
}

extern "C" void mdd_filter_pair(const double *left, const double *right, const double *weights,
		int taps, double *sums) {
	sums[0] = mdd_filter_lanes(left, weights, taps);
	sums[1] = mdd_filter_lanes(right, weights, taps);
}

extern "C" double mdd_filter(const double *values, const double *weights, int taps) {
	return mdd_filter_lanes(values, weights, taps);
}

#endif
