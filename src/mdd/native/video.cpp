/**
 * The scope video writer: RGBA frames through the VP9 encoder, audio through Opus, and both
 * muxed into WebM by libwebm.
 *
 * Encoding runs on a thread of its own. A frame or a run of audio is copied into a queue and the
 * call returns, so the caller, which draws the frames on the thread that owns the window, is
 * held up only when frames are already waiting. The thread touches nothing but what was copied,
 * so no memory it reads can be moved or collected underneath it.
 *
 * WebM carries Opus as raw packets rather than in ogg pages. The identification header goes in
 * the track's codec private data and the encoder's lookahead goes in as the codec delay, which
 * is what a player trims from the start. The VP9 encoder is built realtime only, so it keeps no
 * frames back and every packet can be muxed the moment it is made.
 *
 * The frames are converted to I420 with BT.709 weights at studio range, and the bitstream says
 * so, because a decoder that guesses picks BT.601 below 720 lines and shifts every colour.
 */
#include "video.h"

#include <algorithm>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <mutex>
#include <thread>
#include <vector>

#include <opus.h>
#include <vpx/vp8cx.h>
#include <vpx/vpx_encoder.h>

#include <mkvmuxer/mkvmuxer.h>
#include <mkvmuxer/mkvwriter.h>

#ifdef _WIN32
#include <windows.h>
#endif

#define MDD_VIDEO_PACKET 4000
#define MDD_VIDEO_ROLL 80000000ULL
#define MDD_VIDEO_WAITING 4

struct MddVideoJob {
	bool picture;
	std::vector<unsigned char> pixels;
	std::vector<float> sound;
};

struct MddVideo {
	FILE *file;
	mkvmuxer::MkvWriter *writer;
	mkvmuxer::Segment *segment;
	uint64_t pictures;
	uint64_t sounds;

	vpx_codec_ctx_t codec;
	vpx_image_t image;
	int encoding;
	int imaged;
	int width;
	int height;
	int fps;
	int64_t frame;

	OpusEncoder *opus;
	int rate;
	int channels;
	int span;
	int ahead;
	int64_t sent;
	std::vector<float> pending;

	std::thread worker;
	std::mutex lock;
	std::condition_variable woken;
	std::condition_variable room;
	std::deque<MddVideoJob> jobs;
	int waiting;
	bool closing;
	bool faulted;
};

static FILE *mdd_video_file(const char *path) {
#ifdef _WIN32
	const int wide = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
	if (wide <= 0) return NULL;

	std::vector<wchar_t> named((size_t) wide);
	MultiByteToWideChar(CP_UTF8, 0, path, -1, named.data(), wide);

	return _wfopen(named.data(), L"wb");
#else
	return fopen(path, "wb");
#endif
}

static void mdd_video_stop(MddVideo *video) {
	if (!video->worker.joinable()) return;

	{
		std::lock_guard<std::mutex> held(video->lock);
		video->closing = true;
	}

	video->woken.notify_all();
	video->worker.join();
}

static void mdd_video_free(MddVideo *video) {
	mdd_video_stop(video);

	if (video->imaged) vpx_img_free(&video->image);
	if (video->encoding) vpx_codec_destroy(&video->codec);
	if (video->opus != NULL) opus_encoder_destroy(video->opus);

	delete video->segment;
	delete video->writer;

	if (video->file != NULL) fclose(video->file);

	delete video;
}

static inline unsigned char mdd_video_clamp(int value) {
	return (unsigned char) (value < 0 ? 0 : (value > 255 ? 255 : value));
}

static void mdd_video_yuv(MddVideo *video, const unsigned char *rgba) {
	const vpx_image_t *image = &video->image;
	const int width = video->width;
	const int height = video->height;

	for (int row = 0; row < height; row++) {
		const unsigned char *from = rgba + (size_t) row * (size_t) width * 4;
		unsigned char *luma = image->planes[VPX_PLANE_Y] + row * image->stride[VPX_PLANE_Y];

		for (int column = 0; column < width; column++) {
			const int red = from[column * 4];
			const int green = from[column * 4 + 1];
			const int blue = from[column * 4 + 2];

			luma[column] = mdd_video_clamp(16 + ((47 * red + 157 * green + 16 * blue + 128) >> 8));
		}
	}

	for (int row = 0; row < height / 2; row++) {
		const unsigned char *top = rgba + (size_t) (row * 2) * (size_t) width * 4;
		const unsigned char *under = top + (size_t) width * 4;

		unsigned char *blue_plane = image->planes[VPX_PLANE_U] + row * image->stride[VPX_PLANE_U];
		unsigned char *red_plane = image->planes[VPX_PLANE_V] + row * image->stride[VPX_PLANE_V];

		for (int column = 0; column < width / 2; column++) {
			const int at = column * 8;

			const int red = (top[at] + top[at + 4] + under[at] + under[at + 4] + 2) >> 2;
			const int green = (top[at + 1] + top[at + 5] + under[at + 1] + under[at + 5] + 2) >> 2;
			const int blue = (top[at + 2] + top[at + 6] + under[at + 2] + under[at + 6] + 2) >> 2;

			blue_plane[column] = mdd_video_clamp(128 + ((-26 * red - 87 * green + 112 * blue + 128) >> 8));
			red_plane[column] = mdd_video_clamp(128 + ((112 * red - 102 * green - 10 * blue + 128) >> 8));
		}
	}
}

static bool mdd_video_drain(MddVideo *video) {
	vpx_codec_iter_t iterator = NULL;
	const vpx_codec_cx_pkt_t *packet = NULL;

	while ((packet = vpx_codec_get_cx_data(&video->codec, &iterator)) != NULL) {
		if (packet->kind != VPX_CODEC_CX_FRAME_PKT) continue;

		const uint64_t when = (uint64_t) packet->data.frame.pts * 1000000000ULL
			/ (uint64_t) video->fps;
		const bool key = (packet->data.frame.flags & VPX_FRAME_IS_KEY) != 0;

		if (!video->segment->AddFrame((const uint8_t *) packet->data.frame.buf,
				(uint64_t) packet->data.frame.sz, video->pictures, when, key)) {
			return false;
		}
	}

	return true;
}

static bool mdd_video_encode(MddVideo *video, const unsigned char *rgba) {
	mdd_video_yuv(video, rgba);

	if (vpx_codec_encode(&video->codec, &video->image, video->frame, 1, 0,
			VPX_DL_REALTIME) != VPX_CODEC_OK) {
		return false;
	}

	video->frame++;
	return mdd_video_drain(video);
}

static bool mdd_video_pack(MddVideo *video, bool last) {
	const size_t whole = (size_t) video->span * (size_t) video->channels;
	const size_t held = video->pending.size();

	std::vector<float> padded(whole, 0.0f);
	unsigned char coded[MDD_VIDEO_PACKET];

	size_t at = 0;

	while (held - at >= whole || (last && at < held)) {
		const size_t take = held - at < whole ? held - at : whole;
		const float *from = video->pending.data() + at;

		if (take < whole) {
			std::fill(padded.begin(), padded.end(), 0.0f);
			memcpy(padded.data(), from, take * sizeof(float));
			from = padded.data();
		}

		const opus_int32 bytes = opus_encode_float(video->opus, from, video->span, coded,
			MDD_VIDEO_PACKET);

		if (bytes < 0) return false;

		const uint64_t when = (uint64_t) video->sent * 1000000000ULL / (uint64_t) video->rate;

		if (!video->segment->AddFrame(coded, (uint64_t) bytes, video->sounds, when, true)) {
			return false;
		}

		video->sent += video->span;
		at += take;
	}

	video->pending.erase(video->pending.begin(), video->pending.begin() + (std::ptrdiff_t) at);
	return true;
}

static void mdd_video_work(MddVideo *video) {
	for (;;) {
		MddVideoJob job;

		{
			std::unique_lock<std::mutex> held(video->lock);
			video->woken.wait(held, [video] { return !video->jobs.empty() || video->closing; });

			if (video->jobs.empty()) return;

			job = std::move(video->jobs.front());
			video->jobs.pop_front();
		}

		bool fine = true;

		if (job.picture) {
			fine = mdd_video_encode(video, job.pixels.data());
		} else {
			video->pending.insert(video->pending.end(), job.sound.begin(), job.sound.end());
			fine = mdd_video_pack(video, false);
		}

		{
			std::lock_guard<std::mutex> held(video->lock);

			if (job.picture) video->waiting--;
			if (!fine) video->faulted = true;
		}

		video->room.notify_all();
	}
}

extern "C" MddVideo *mdd_video_open(const char *path, int width, int height, int fps,
	int kilobits, int rate, int channels, int audio_kilobits, int threads) {
	if (path == NULL || width < 2 || height < 2 || (width & 1) != 0 || (height & 1) != 0
			|| fps < 1 || channels < 1 || channels > 2) {
		return NULL;
	}

	MddVideo *video = new MddVideo();

	video->file = NULL;
	video->writer = NULL;
	video->segment = NULL;
	video->pictures = 0;
	video->sounds = 0;
	video->encoding = 0;
	video->imaged = 0;
	video->width = width;
	video->height = height;
	video->fps = fps;
	video->frame = 0;
	video->opus = NULL;
	video->rate = rate;
	video->channels = channels;
	video->span = rate / 50;
	video->ahead = 0;
	video->sent = 0;
	video->waiting = 0;
	video->closing = false;
	video->faulted = false;

	vpx_codec_iface_t *face = vpx_codec_vp9_cx();
	vpx_codec_enc_cfg_t config;

	if (vpx_codec_enc_config_default(face, &config, 0) != VPX_CODEC_OK) {
		mdd_video_free(video);
		return NULL;
	}

	const int found = (int) std::thread::hardware_concurrency();
	const int wanted = threads > 0 ? threads : (found > 1 ? found - 1 : 1);
	const int workers = wanted > 16 ? 16 : wanted;

	config.g_w = (unsigned int) width;
	config.g_h = (unsigned int) height;
	config.g_timebase.num = 1;
	config.g_timebase.den = fps;
	config.g_threads = (unsigned int) workers;
	config.g_lag_in_frames = 0;
	config.g_pass = VPX_RC_ONE_PASS;
	config.rc_end_usage = VPX_VBR;
	config.rc_target_bitrate = (unsigned int) (kilobits < 100 ? 100 : kilobits);
	config.kf_max_dist = (unsigned int) (fps * 5);

	if (vpx_codec_enc_init(&video->codec, face, &config, 0) != VPX_CODEC_OK) {
		mdd_video_free(video);
		return NULL;
	}

	video->encoding = 1;

	int tiles = 0;
	while ((1 << (tiles + 1)) <= workers && (width >> (tiles + 1)) >= 256) tiles++;

	vpx_codec_control(&video->codec, VP8E_SET_CPUUSED, 7);
	vpx_codec_control(&video->codec, VP9E_SET_ROW_MT, 1);
	vpx_codec_control(&video->codec, VP9E_SET_TILE_COLUMNS, tiles);
	vpx_codec_control(&video->codec, VP9E_SET_TUNE_CONTENT, VP9E_CONTENT_SCREEN);
	vpx_codec_control(&video->codec, VP9E_SET_COLOR_SPACE, VPX_CS_BT_709);
	vpx_codec_control(&video->codec, VP9E_SET_COLOR_RANGE, VPX_CR_STUDIO_RANGE);

	if (vpx_img_alloc(&video->image, VPX_IMG_FMT_I420, (unsigned int) width,
			(unsigned int) height, 16) == NULL) {
		mdd_video_free(video);
		return NULL;
	}

	video->imaged = 1;

	int fault = 0;
	video->opus = opus_encoder_create(rate, channels, OPUS_APPLICATION_AUDIO, &fault);

	if (video->opus == NULL || fault != OPUS_OK) {
		mdd_video_free(video);
		return NULL;
	}

	opus_encoder_ctl(video->opus, OPUS_SET_BITRATE(audio_kilobits * 1000));
	opus_encoder_ctl(video->opus, OPUS_SET_COMPLEXITY(10));
	opus_encoder_ctl(video->opus, OPUS_SET_SIGNAL(OPUS_SIGNAL_MUSIC));

	opus_int32 ahead = 0;
	opus_encoder_ctl(video->opus, OPUS_GET_LOOKAHEAD(&ahead));
	video->ahead = (int) ahead;

	video->file = mdd_video_file(path);

	if (video->file == NULL) {
		mdd_video_free(video);
		return NULL;
	}

	video->writer = new mkvmuxer::MkvWriter(video->file);
	video->segment = new mkvmuxer::Segment();

	if (!video->segment->Init(video->writer)) {
		mdd_video_free(video);
		return NULL;
	}

	video->segment->set_mode(mkvmuxer::Segment::kFile);
	video->segment->OutputCues(true);
	video->segment->GetSegmentInfo()->set_writing_app("md-synth-daw");

	video->pictures = video->segment->AddVideoTrack(width, height, 1);
	video->sounds = video->segment->AddAudioTrack(rate, channels, 2);

	mkvmuxer::VideoTrack *pictured = static_cast<mkvmuxer::VideoTrack *>(
		video->segment->GetTrackByNumber(video->pictures));
	mkvmuxer::AudioTrack *sounded = static_cast<mkvmuxer::AudioTrack *>(
		video->segment->GetTrackByNumber(video->sounds));

	if (pictured == NULL || sounded == NULL) {
		mdd_video_free(video);
		return NULL;
	}

	pictured->set_codec_id(mkvmuxer::Tracks::kVp9CodecId);
	pictured->set_frame_rate((double) fps);

	const uint64_t skip = (uint64_t) ahead * 48000ULL / (uint64_t) rate;

	unsigned char head[19];
	memcpy(head, "OpusHead", 8);

	head[8] = 1;
	head[9] = (unsigned char) channels;
	head[10] = (unsigned char) (skip & 0xFF);
	head[11] = (unsigned char) ((skip >> 8) & 0xFF);
	head[12] = (unsigned char) (rate & 0xFF);
	head[13] = (unsigned char) ((rate >> 8) & 0xFF);
	head[14] = (unsigned char) ((rate >> 16) & 0xFF);
	head[15] = (unsigned char) ((rate >> 24) & 0xFF);
	head[16] = 0;
	head[17] = 0;
	head[18] = 0;

	sounded->set_codec_id(mkvmuxer::Tracks::kOpusCodecId);
	sounded->SetCodecPrivate(head, sizeof(head));
	sounded->set_codec_delay(skip * 1000000000ULL / 48000ULL);
	sounded->set_seek_pre_roll(MDD_VIDEO_ROLL);

	video->segment->CuesTrack(video->pictures);

	video->worker = std::thread(mdd_video_work, video);

	return video;
}

extern "C" int mdd_video_frame(MddVideo *video, const unsigned char *rgba) {
	if (video == NULL || rgba == NULL) return -1;

	MddVideoJob job;
	job.picture = true;
	job.pixels.assign(rgba, rgba + (size_t) video->width * (size_t) video->height * 4);

	std::unique_lock<std::mutex> held(video->lock);
	video->room.wait(held, [video] { return video->waiting < MDD_VIDEO_WAITING || video->faulted; });

	if (video->faulted) return -3;

	video->jobs.push_back(std::move(job));
	video->waiting++;

	held.unlock();
	video->woken.notify_one();

	return 0;
}

extern "C" int mdd_video_audio(MddVideo *video, const float *samples, int frames) {
	if (video == NULL || samples == NULL || frames < 0) return -1;

	MddVideoJob job;
	job.picture = false;
	job.sound.assign(samples, samples + (size_t) frames * (size_t) video->channels);

	{
		std::lock_guard<std::mutex> held(video->lock);

		if (video->faulted) return -2;

		video->jobs.push_back(std::move(job));
	}

	video->woken.notify_one();
	return 0;
}

extern "C" int mdd_video_close(MddVideo *video) {
	if (video == NULL) return -1;

	mdd_video_stop(video);

	bool fine = !video->faulted;

	if (vpx_codec_encode(&video->codec, NULL, -1, 1, 0, VPX_DL_REALTIME) != VPX_CODEC_OK
			|| !mdd_video_drain(video)) {
		fine = false;
	}

	video->pending.insert(video->pending.end(),
		(size_t) video->ahead * (size_t) video->channels, 0.0f);

	if (!mdd_video_pack(video, true)) fine = false;
	if (!video->segment->Finalize()) fine = false;

	mdd_video_free(video);
	return fine ? 0 : -2;
}
