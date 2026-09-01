/*
 * opn2 <samples>                 one script on standard input, samples on standard output
 * opn2 <samples> <jobs>          many, where each line of <jobs> is "<script> <output>"
 * opn2 <samples> <jobs> ladder   the same, as the discrete YM2612 rather than the YM3438
 *
 * A script is a list of writes, one a line: <samples to run first> <port 0..3> <value>.
 * What comes out is signed sixteen bit samples, two channels interleaved.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
#include "ym3438.h"

#define PER_SAMPLE 24

static void emit(ym3438_t *chip, FILE *out) {
	Bit16s buffer[2];
	long left = 0, right = 0;
	Bit16s pair[2];
	int i;

	for (i = 0; i < PER_SAMPLE; i++) {
		OPN2_Clock(chip, buffer);
		left += buffer[0];
		right += buffer[1];
	}

	left /= 3;
	right /= 3;

	if (left > 32767) left = 32767;
	if (left < -32768) left = -32768;
	if (right > 32767) right = 32767;
	if (right < -32768) right = -32768;

	pair[0] = (Bit16s)left;
	pair[1] = (Bit16s)right;
	fwrite(pair, sizeof(Bit16s), 2, out);
}

static void render(FILE *script, FILE *out, long total) {
	ym3438_t chip;
	long produced = 0;
	char line[256];

	OPN2_Reset(&chip);

	while (fgets(line, sizeof(line), script)) {
		long wait, i;
		unsigned port, value;
		if (sscanf(line, "%ld %u %u", &wait, &port, &value) != 3) continue;

		for (i = 0; i < wait && produced < total; i++) {
			emit(&chip, out);
			produced++;
		}

		OPN2_Write(&chip, port, (Bit8u)value);
	}

	while (produced < total) {
		emit(&chip, out);
		produced++;
	}
}

static int batch(const char *jobs, long total) {
	FILE *list = fopen(jobs, "r");
	char line[1024];
	int done = 0;

	if (!list) {
		fprintf(stderr, "cannot read %s\n", jobs);
		return 1;
	}

	while (fgets(line, sizeof(line), list)) {
		char *split = strchr(line, ' ');
		FILE *script, *out;

		if (!split) continue;
		*split = '\0';
		split++;
		split[strcspn(split, "\r\n")] = '\0';

		script = fopen(line, "r");
		if (!script) {
			fprintf(stderr, "cannot read %s\n", line);
			fclose(list);
			return 1;
		}

		out = fopen(split, "wb");
		if (!out) {
			fprintf(stderr, "cannot write %s\n", split);
			fclose(script);
			fclose(list);
			return 1;
		}

		render(script, out, total);
		fclose(script);
		fclose(out);
		done++;
	}

	fclose(list);
	return 0;
}

int main(int argc, char **argv) {
	long total = argc > 1 ? atol(argv[1]) : 44100;
	int ladder = argc > 3 && argv[3][0] == 'l';

	OPN2_SetChipType(ym3438_mode_readmode | (ladder ? ym3438_mode_ym2612 : 0));

	if (argc > 2) return batch(argv[2], total);

#ifdef _WIN32
	_setmode(_fileno(stdout), _O_BINARY);
#endif

	render(stdin, stdout, total);
	return 0;
}
