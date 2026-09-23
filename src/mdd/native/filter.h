#ifndef MDD_FILTER_H
#define MDD_FILTER_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Runs the FM part's left and right histories through one resampler kernel at once, so
 * each weight is read a single time for both sides.
 *
 * Each sample is multiplied by the weight at the same place and the products are summed
 * eight at a time into eight running sums, which are then added in one fixed order. The
 * order is the same on every processor this builds for, so the answer is too. Runs on
 * the render thread and allocates nothing.
 *
 * @param left The left history, newest first.
 * @param right The right history, newest first.
 * @param weights The kernel, one weight a sample.
 * @param taps How many samples and weights there are, a multiple of eight.
 * @param sums Where the two answers go, the left and then the right.
 */
void mdd_filter_pair(const double *left, const double *right, const double *weights, int taps,
	double *sums);

/**
 * The same for one history, which is the square part.
 *
 * @param values The history, newest first.
 * @param weights The kernel, one weight a sample.
 * @param taps How many samples and weights there are, a multiple of eight.
 * @return The sum of the products.
 */
double mdd_filter(const double *values, const double *weights, int taps);

#ifdef __cplusplus
}
#endif

#endif
