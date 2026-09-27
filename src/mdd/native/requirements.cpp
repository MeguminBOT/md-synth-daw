/**
 * What this machine offers the interface, for the Windows installer to hold against what the
 * application needs before it installs anything.
 *
 * Every renderer is tried the way the application makes one, on a hidden window of its own, so
 * one counted here is one the application can start on. Where a renderer has a level of its own
 * that the interface needs, that is asked of the driver as well: the Direct3D 11 feature level,
 * the Direct3D 9 pixel shader model and the OpenGL version. The graphics libraries are loaded as
 * they are needed rather than linked, so a machine missing one answers nought for it instead of
 * refusing to start.
 *
 * Each line is flushed as it is written, so a driver that brings the process down part way still
 * leaves everything found before it.
 */
#include "requirements.h"

#include <SDL3/SDL.h>

#include <cstdio>
#include <cstring>

#ifdef _WIN32
#include <windows.h>
#include <d3d9.h>
#include <d3d11.h>
#include <d3d12.h>
#include <dxgi.h>
#endif

namespace {
	SDL_IOStream *out = nullptr;

	/**
	 * GL_VERSION, which glGetString answers with the version string.
	 */
	constexpr unsigned int GL_VERSION_NAME = 0x1F02;

	/**
	 * glGetString, looked up through SDL rather than linked.
	 */
	typedef const unsigned char *(SDLCALL *GetString)(unsigned int name);

	/**
	 * Writes one fact.
	 *
	 * @param name What it is.
	 * @param value What the machine has.
	 */
	void said(const char *name, const char *value) {
		SDL_IOprintf(out, "%s %s\n", name, value);
		SDL_FlushIO(out);
	}

	/**
	 * Reads the first `major.minor` out of a version string, past whatever it opens with:
	 * `4.6.0 NVIDIA 560.94` and `OpenGL ES 3.2 NVIDIA` both have one.
	 *
	 * @param text The string, or null.
	 * @param into Where the version goes, `0` where there is none.
	 * @param room How large `into` is.
	 */
	void versioned(const char *text, char *into, size_t room) {
		SDL_snprintf(into, room, "0");
		if (text == nullptr) return;

		while (*text != 0 && (*text < '0' || *text > '9')) text++;

		int major = 0;
		int minor = 0;

		if (SDL_sscanf(text, "%d.%d", &major, &minor) == 2) {
			SDL_snprintf(into, room, "%d.%d", major, minor);
		}
	}

	/**
	 * Makes a renderer by name on a hidden window, and reads the OpenGL version out of it where it
	 * is one of the two OpenGL renderers.
	 *
	 * @param driver The renderer's name, as SDL has it.
	 * @param into `1` where it was made, the OpenGL version for those, and `0` where it was not.
	 * @param room How large `into` is.
	 * @return Whether it was made.
	 */
	bool made(const char *driver, char *into, size_t room) {
		SDL_snprintf(into, room, "0");

		SDL_Window *window = SDL_CreateWindow("mdd requirements", 64, 64, SDL_WINDOW_HIDDEN);
		if (window == nullptr) return false;

		SDL_Renderer *renderer = SDL_CreateRenderer(window, driver);

		if (renderer == nullptr) {
			SDL_DestroyWindow(window);
			return false;
		}

		SDL_snprintf(into, room, "1");

		if (SDL_strcmp(driver, "opengl") == 0 || SDL_strcmp(driver, "opengles2") == 0) {
			const GetString asked = (GetString)SDL_GL_GetProcAddress("glGetString");
			versioned(asked == nullptr ? nullptr : (const char *)asked(GL_VERSION_NAME), into, room);
		}

		SDL_DestroyRenderer(renderer);
		SDL_DestroyWindow(window);
		return true;
	}

#ifdef _WIN32
	/**
	 * @return The highest feature level Direct3D 11 reaches on the default adapter, or nought
	 * 	where it will not make a device there at all.
	 */
	unsigned int featureLevel() {
		HMODULE library = LoadLibraryA("d3d11.dll");
		if (library == nullptr) return 0;

		const PFN_D3D11_CREATE_DEVICE create =
			(PFN_D3D11_CREATE_DEVICE)(void *)GetProcAddress(library, "D3D11CreateDevice");

		const D3D_FEATURE_LEVEL levels[] = {
			D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_11_1,
			D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0,
			D3D_FEATURE_LEVEL_9_3, D3D_FEATURE_LEVEL_9_2, D3D_FEATURE_LEVEL_9_1
		};

		D3D_FEATURE_LEVEL reached = (D3D_FEATURE_LEVEL)0;
		HRESULT result = E_FAIL;

		if (create != nullptr) {
			result = create(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, levels,
				sizeof(levels) / sizeof(levels[0]), D3D11_SDK_VERSION, nullptr, &reached, nullptr);

			if (result == E_INVALIDARG) {
				result = create(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, levels + 3,
					sizeof(levels) / sizeof(levels[0]) - 3, D3D11_SDK_VERSION, nullptr, &reached,
					nullptr);
			}
		}

		FreeLibrary(library);
		return SUCCEEDED(result) ? (unsigned int)reached : 0;
	}

	/**
	 * @return The pixel shader model Direct3D 9 reports for the default adapter, as `major << 8 |
	 * 	minor`, or nought where it reports none.
	 */
	unsigned int shaderModel() {
		HMODULE library = LoadLibraryA("d3d9.dll");
		if (library == nullptr) return 0;

		typedef IDirect3D9 *(WINAPI *Create)(UINT version);
		const Create create = (Create)(void *)GetProcAddress(library, "Direct3DCreate9");

		unsigned int model = 0;
		IDirect3D9 *direct = create == nullptr ? nullptr : create(D3D_SDK_VERSION);

		if (direct != nullptr) {
			D3DCAPS9 caps;

			if (SUCCEEDED(direct->GetDeviceCaps(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, &caps))) {
				model = (D3DSHADER_VERSION_MAJOR(caps.PixelShaderVersion) << 8)
					| D3DSHADER_VERSION_MINOR(caps.PixelShaderVersion);
			}

			direct->Release();
		}

		FreeLibrary(library);
		return model;
	}

	/**
	 * @param adapter An adapter.
	 * @param vendor Its vendor's identifier.
	 * @return Whether it shares the system's memory rather than having its own, which is what
	 * 	integrated graphics does. Direct3D 12 is what says so; without it, an Intel adapter is
	 * 	taken to be integrated, since every Intel part that lacks Direct3D 12 is.
	 */
	bool unified(IDXGIAdapter1 *adapter, UINT vendor) {
		HMODULE library = LoadLibraryA("d3d12.dll");
		bool found = vendor == 0x8086;

		if (library == nullptr) return found;

		const PFN_D3D12_CREATE_DEVICE create =
			(PFN_D3D12_CREATE_DEVICE)(void *)GetProcAddress(library, "D3D12CreateDevice");

		ID3D12Device *device = nullptr;

		if (create != nullptr && SUCCEEDED(create(adapter, D3D_FEATURE_LEVEL_11_0,
				__uuidof(ID3D12Device), (void **)&device)) && device != nullptr) {
			D3D12_FEATURE_DATA_ARCHITECTURE architecture = {};

			if (SUCCEEDED(device->CheckFeatureSupport(D3D12_FEATURE_ARCHITECTURE, &architecture,
					sizeof(architecture)))) {
				found = architecture.UMA != FALSE;
			}

			device->Release();
		}

		FreeLibrary(library);
		return found;
	}

	/**
	 * Writes the default adapter's name and the graphics memory it can use: its own, and the
	 * system's as well where it shares that, which is how integrated graphics is fine.
	 */
	void memory() {
		HMODULE library = LoadLibraryA("dxgi.dll");

		if (library == nullptr) {
			said("graphics", "0");
			return;
		}

		typedef HRESULT (WINAPI *Create)(REFIID riid, void **factory);
		const Create create = (Create)(void *)GetProcAddress(library, "CreateDXGIFactory1");

		IDXGIFactory1 *factory = nullptr;
		IDXGIAdapter1 *adapter = nullptr;
		char held[64];

		SDL_snprintf(held, sizeof(held), "0");

		if (create != nullptr && SUCCEEDED(create(__uuidof(IDXGIFactory1), (void **)&factory))
				&& SUCCEEDED(factory->EnumAdapters1(0, &adapter))) {
			DXGI_ADAPTER_DESC1 description;

			if (SUCCEEDED(adapter->GetDesc1(&description))) {
				char name[256];

				if (WideCharToMultiByte(CP_UTF8, 0, description.Description, -1, name,
						sizeof(name), nullptr, nullptr) > 0) {
					said("adapter", name);
				}

				const unsigned long long own = description.DedicatedVideoMemory >> 20;
				const unsigned long long shared = description.SharedSystemMemory >> 20;

				SDL_snprintf(held, sizeof(held), "%llu", unified(adapter, description.VendorId)
					? own + shared : own);
			}
		}

		if (adapter != nullptr) adapter->Release();
		if (factory != nullptr) factory->Release();
		FreeLibrary(library);

		said("graphics", held);
	}
#endif
}

extern "C" int mdd_requirements_reached(SDL_Renderer *renderer) {
	if (renderer == nullptr) return 0;

	const char *name = SDL_GetRendererName(renderer);
	if (name == nullptr) return 0;

	if (SDL_strcmp(name, "opengl") == 0 || SDL_strcmp(name, "opengles2") == 0) {
		const GetString asked = (GetString)SDL_GL_GetProcAddress("glGetString");
		char version[32];

		versioned(asked == nullptr ? nullptr : (const char *)asked(GL_VERSION_NAME), version,
			sizeof(version));

		int major = 0;
		int minor = 0;

		return SDL_sscanf(version, "%d.%d", &major, &minor) == 2 ? (major << 8) | minor : 0;
	}

#ifdef _WIN32
	const SDL_PropertiesID held = SDL_GetRendererProperties(renderer);

	if (SDL_strcmp(name, "direct3d11") == 0) {
		ID3D11Device *device = (ID3D11Device *)SDL_GetPointerProperty(held,
			SDL_PROP_RENDERER_D3D11_DEVICE_POINTER, nullptr);
		if (device == nullptr) return 0;

		const unsigned int level = (unsigned int)device->GetFeatureLevel();
		return (int)((((level >> 12) & 0xF) << 8) | ((level >> 8) & 0xF));
	}

	if (SDL_strcmp(name, "direct3d") == 0) {
		IDirect3DDevice9 *device = (IDirect3DDevice9 *)SDL_GetPointerProperty(held,
			SDL_PROP_RENDERER_D3D9_DEVICE_POINTER, nullptr);
		if (device == nullptr) return 0;

		D3DCAPS9 caps;
		if (FAILED(device->GetDeviceCaps(&caps))) return 0;

		return (int)((D3DSHADER_VERSION_MAJOR(caps.PixelShaderVersion) << 8)
			| D3DSHADER_VERSION_MINOR(caps.PixelShaderVersion));
	}
#endif

	return 0;
}

extern "C" int mdd_requirements_write(const char *path) {
	out = SDL_IOFromFile(path, "w");
	if (out == nullptr) return 1;

	if (!SDL_Init(SDL_INIT_VIDEO)) {
		said("video", "0");
		SDL_CloseIO(out);
		return 0;
	}

#ifdef _WIN32
	memory();
#endif

	char level[32];

	for (int index = 0; index < SDL_GetNumRenderDrivers(); index++) {
		const char *driver = SDL_GetRenderDriver(index);
		if (driver == nullptr || SDL_strcmp(driver, "software") == 0) continue;
		if (SDL_strcmp(driver, "gpu") == 0) continue;

		if (!made(driver, level, sizeof(level))) {
			said(driver, level);
			continue;
		}

#ifdef _WIN32
		if (SDL_strcmp(driver, "direct3d11") == 0) {
			const unsigned int reached = featureLevel();
			SDL_snprintf(level, sizeof(level), "%u.%u", (reached >> 12) & 0xF,
				(reached >> 8) & 0xF);
		}

		if (SDL_strcmp(driver, "direct3d") == 0) {
			const unsigned int model = shaderModel();
			SDL_snprintf(level, sizeof(level), "%u.%u", model >> 8, model & 0xFF);
		}
#endif

		said(driver, level);
	}

	SDL_Quit();
	SDL_CloseIO(out);
	return 0;
}
