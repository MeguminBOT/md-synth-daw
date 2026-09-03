#include "encode.h"

#include <stdlib.h>
#include <string.h>

#include <ogg/ogg.h>
#include <vorbis/codec.h>
#include <vorbis/vorbisenc.h>
#include <opus.h>

#define MDD_ENCODE_SPAN 1024
#define MDD_ENCODE_TAGS 64

struct MddPile {
	unsigned char *into;
	int room;
	int filled;
	int spilled;
};

static void mdd_encode_put(MddPile *pile, const unsigned char *from, long many) {
	if (many <= 0) return;

	if (pile->filled + many > pile->room) {
		pile->spilled = 1;
		return;
	}

	memcpy(pile->into + pile->filled, from, (size_t) many);
	pile->filled += (int) many;
}

static void mdd_encode_page(MddPile *pile, ogg_page *page) {
	mdd_encode_put(pile, page->header, page->header_len);
	mdd_encode_put(pile, page->body, page->body_len);
}

static int mdd_encode_split(const char *tags, char *room, int most, char **found) {
	if (tags == NULL) return 0;

	strncpy(room, tags, (size_t) most - 1);
	room[most - 1] = 0;

	int many = 0;
	char *at = room;

	while (*at != 0 && many < MDD_ENCODE_TAGS) {
		found[many++] = at;

		while (*at != 0 && *at != '\n') at++;
		if (*at == 0) break;

		*at = 0;
		at++;
	}

	return many;
}

extern "C" int mdd_encode_vorbis(const float *samples, int frames, int channels, int rate,
	float quality, const char *tags, unsigned char *into, int room) {
	if (samples == NULL || into == NULL || frames <= 0 || channels < 1 || channels > 2) {
		return -1;
	}

	vorbis_info info;
	vorbis_info_init(&info);

	if (vorbis_encode_init_vbr(&info, channels, rate, quality) != 0) {
		vorbis_info_clear(&info);
		return -2;
	}

	vorbis_comment comment;
	vorbis_comment_init(&comment);

	char held[4096];
	char *lines[MDD_ENCODE_TAGS];
	const int many = mdd_encode_split(tags, held, sizeof(held), lines);

	for (int index = 0; index < many; index++) {
		char *split = strchr(lines[index], '=');
		if (split == NULL) continue;

		*split = 0;
		vorbis_comment_add_tag(&comment, lines[index], split + 1);
	}

	vorbis_dsp_state state;
	vorbis_block block;

	vorbis_analysis_init(&state, &info);
	vorbis_block_init(&state, &block);

	ogg_stream_state stream;
	ogg_stream_init(&stream, 0x4D444421);

	MddPile pile;
	pile.into = into;
	pile.room = room;
	pile.filled = 0;
	pile.spilled = 0;

	ogg_packet one;
	ogg_packet two;
	ogg_packet three;

	vorbis_analysis_headerout(&state, &comment, &one, &two, &three);

	ogg_stream_packetin(&stream, &one);
	ogg_stream_packetin(&stream, &two);
	ogg_stream_packetin(&stream, &three);

	ogg_page page;
	while (ogg_stream_flush(&stream, &page) != 0) mdd_encode_page(&pile, &page);

	int at = 0;

	while (true) {
		const int take = frames - at < MDD_ENCODE_SPAN ? frames - at : MDD_ENCODE_SPAN;

		if (take <= 0) {
			vorbis_analysis_wrote(&state, 0);
		} else {
			float **room2 = vorbis_analysis_buffer(&state, take);

			for (int index = 0; index < take; index++) {
				for (int side = 0; side < channels; side++) {
					room2[side][index] = samples[(at + index) * channels + side];
				}
			}

			vorbis_analysis_wrote(&state, take);
			at += take;
		}

		while (vorbis_analysis_blockout(&state, &block) == 1) {
			vorbis_analysis(&block, NULL);
			vorbis_bitrate_addblock(&block);

			ogg_packet packet;

			while (vorbis_bitrate_flushpacket(&state, &packet)) {
				ogg_stream_packetin(&stream, &packet);

				while (ogg_stream_pageout(&stream, &page) != 0) {
					mdd_encode_page(&pile, &page);
					if (ogg_page_eos(&page)) break;
				}
			}
		}

		if (take <= 0) break;
	}

	while (ogg_stream_flush(&stream, &page) != 0) mdd_encode_page(&pile, &page);

	ogg_stream_clear(&stream);
	vorbis_block_clear(&block);
	vorbis_dsp_clear(&state);
	vorbis_comment_clear(&comment);
	vorbis_info_clear(&info);

	return pile.spilled != 0 ? -3 : pile.filled;
}

static void mdd_encode_head(unsigned char *room, int channels, int rate, int ahead) {
	memcpy(room, "OpusHead", 8);

	room[8] = 1;
	room[9] = (unsigned char) channels;
	room[10] = (unsigned char) (ahead & 0xFF);
	room[11] = (unsigned char) ((ahead >> 8) & 0xFF);
	room[12] = (unsigned char) (rate & 0xFF);
	room[13] = (unsigned char) ((rate >> 8) & 0xFF);
	room[14] = (unsigned char) ((rate >> 16) & 0xFF);
	room[15] = (unsigned char) ((rate >> 24) & 0xFF);
	room[16] = 0;
	room[17] = 0;
	room[18] = 0;
}

static int mdd_encode_tags(unsigned char *room, int most, char **lines, int many) {
	static const char maker[] = "md-synth-daw";

	int at = 0;

	memcpy(room, "OpusTags", 8);
	at = 8;

	const int named = (int) strlen(maker);

	room[at++] = (unsigned char) (named & 0xFF);
	room[at++] = (unsigned char) ((named >> 8) & 0xFF);
	room[at++] = (unsigned char) ((named >> 16) & 0xFF);
	room[at++] = (unsigned char) ((named >> 24) & 0xFF);

	memcpy(room + at, maker, (size_t) named);
	at += named;

	room[at++] = (unsigned char) (many & 0xFF);
	room[at++] = (unsigned char) ((many >> 8) & 0xFF);
	room[at++] = (unsigned char) ((many >> 16) & 0xFF);
	room[at++] = (unsigned char) ((many >> 24) & 0xFF);

	for (int index = 0; index < many; index++) {
		const int wide = (int) strlen(lines[index]);
		if (at + 4 + wide > most) break;

		room[at++] = (unsigned char) (wide & 0xFF);
		room[at++] = (unsigned char) ((wide >> 8) & 0xFF);
		room[at++] = (unsigned char) ((wide >> 16) & 0xFF);
		room[at++] = (unsigned char) ((wide >> 24) & 0xFF);

		memcpy(room + at, lines[index], (size_t) wide);
		at += wide;
	}

	return at;
}

extern "C" int mdd_encode_opus(const float *samples, int frames, int channels, int rate,
	int bitrate, const char *tags, unsigned char *into, int room) {
	if (samples == NULL || into == NULL || frames <= 0 || channels < 1 || channels > 2) {
		return -1;
	}

	int fault = 0;

	OpusEncoder *encoder = opus_encoder_create(rate, channels,
		OPUS_APPLICATION_AUDIO, &fault);

	if (encoder == NULL || fault != OPUS_OK) return -2;

	opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate * 1000));
	opus_encoder_ctl(encoder, OPUS_SET_VBR(1));
	opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(10));

	opus_int32 ahead = 0;
	opus_encoder_ctl(encoder, OPUS_GET_LOOKAHEAD(&ahead));

	ogg_stream_state stream;
	ogg_stream_init(&stream, 0x4D444422);

	MddPile pile;
	pile.into = into;
	pile.room = room;
	pile.filled = 0;
	pile.spilled = 0;

	unsigned char header[19];
	mdd_encode_head(header, channels, rate, (int) ahead);

	ogg_packet packet;
	memset(&packet, 0, sizeof(packet));

	packet.packet = header;
	packet.bytes = 19;
	packet.b_o_s = 1;
	packet.granulepos = 0;
	packet.packetno = 0;

	ogg_stream_packetin(&stream, &packet);

	ogg_page page;
	while (ogg_stream_flush(&stream, &page) != 0) mdd_encode_page(&pile, &page);

	char held[4096];
	char *lines[MDD_ENCODE_TAGS];
	const int many = mdd_encode_split(tags, held, sizeof(held), lines);

	unsigned char *comments = (unsigned char *) malloc(8192);
	if (comments == NULL) {
		ogg_stream_clear(&stream);
		opus_encoder_destroy(encoder);
		return -4;
	}

	const int wide = mdd_encode_tags(comments, 8192, lines, many);

	memset(&packet, 0, sizeof(packet));
	packet.packet = comments;
	packet.bytes = wide;
	packet.granulepos = 0;
	packet.packetno = 1;

	ogg_stream_packetin(&stream, &packet);
	while (ogg_stream_flush(&stream, &page) != 0) mdd_encode_page(&pile, &page);

	free(comments);

	const int span = rate / 50;
	float *block = (float *) calloc((size_t) (span * channels), sizeof(float));
	unsigned char *coded = (unsigned char *) malloc(4096);

	if (block == NULL || coded == NULL) {
		if (block != NULL) free(block);
		if (coded != NULL) free(coded);

		ogg_stream_clear(&stream);
		opus_encoder_destroy(encoder);
		return -4;
	}

	int at = 0;
	long number = 2;
	ogg_int64_t granule = 0;

	while (at < frames) {
		const int take = frames - at < span ? frames - at : span;

		for (int index = 0; index < span * channels; index++) block[index] = 0;

		for (int index = 0; index < take * channels; index++) {
			block[index] = samples[at * channels + index];
		}

		const int wrote = opus_encode_float(encoder, block, span, coded, 4096);
		at += take;

		if (wrote < 0) break;

		granule += span;

		memset(&packet, 0, sizeof(packet));
		packet.packet = coded;
		packet.bytes = wrote;
		packet.granulepos = granule + ahead;
		packet.packetno = number++;
		packet.e_o_s = at >= frames ? 1 : 0;

		ogg_stream_packetin(&stream, &packet);

		while (ogg_stream_pageout(&stream, &page) != 0) mdd_encode_page(&pile, &page);
	}

	while (ogg_stream_flush(&stream, &page) != 0) mdd_encode_page(&pile, &page);

	free(block);
	free(coded);

	ogg_stream_clear(&stream);
	opus_encoder_destroy(encoder);

	return pile.spilled != 0 ? -3 : pile.filled;
}
