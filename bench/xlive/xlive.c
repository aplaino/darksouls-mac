// xlive.dll for running DATA.exe under Wine/CrossOver in benchmarks: the
// runtime's xlive HLE (vendor/x86recomp/src/runtime/hle/xlive.cpp) as a
// native 32-bit DLL, so both sides run the game against the same offline
// GFWL answers. Ordinals the game imports but never calls return 0.

#include <winsock2.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define X(ret, name) __declspec(dllexport) ret __stdcall name

enum {
  kErrorSuccess = 0,
  kErrorInvalidParameter = 87,
  kErrorInsufficientBuffer = 122,
  kErrorNoMoreFiles = 18,
  kErrorIoPending = 997,
  kErrorFunctionFailed = 1627,
  kErrorNoSuchUser = 1317,
  kErrorNotFound = 1168,
};

static const unsigned long long kXuid = 0xEE000000DEADC0DEull;
static const char kUserName[] = "Player";

#define XNID(v, a, i) ((a) << 25 | (v) << 16 | (i))

// XOVERLAPPED: { InternalLow, InternalHigh, InternalContext, hEvent,
//   pCompletionRoutine, dwCompletionContext, dwExtendedError }
typedef struct {
  DWORD low, high, ctx;
  HANDLE event;
  void* routine;
  DWORD completion_ctx, ext_error;
} XOV;

static DWORD Complete(XOV* ov, DWORD result, DWORD count) {
  ov->low = result;
  ov->high = count;
  ov->ext_error = result;
  if (ov->event) SetEvent(ov->event);
  return kErrorIoPending;
}
static DWORD Finish(XOV* ov, DWORD result) { return ov ? Complete(ov, result, 0) : result; }
static HANDLE Dummy(void) { return CreateEventA(NULL, TRUE, FALSE, NULL); }

// ---- notifications ----------------------------------------------------------

static CRITICAL_SECTION g_mu;
typedef struct { HANDLE h; DWORD areas, n, ids[16], params[16]; } Listener;
static Listener g_listeners[8];

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID r) {
  if (reason == DLL_PROCESS_ATTACH) InitializeCriticalSection(&g_mu);
  return TRUE;
}

X(HANDLE, XNotifyCreateListener)(DWORD areas, DWORD areas_hi) {
  static const DWORD seq[][2] = {
      {XNID(0, 0, 0x09), 1}, {XNID(0, 0, 0x09), 0}, {XNID(0, 0, 0x0A), 1},
      {XNID(0, 0, 0x0B), 0}, {XNID(0, 0, 0x0E), 1}, {XNID(0, 0, 0x12), 0},
      {XNID(1, 0, 0x13), 1}, {XNID(0, 1, 0x01), 0}, {XNID(0, 1, 0x07), 0},
      {XNID(0, 1, 0x08), 0},
  };
  HANDLE h = CreateEventA(NULL, TRUE, TRUE, NULL);
  EnterCriticalSection(&g_mu);
  for (int i = 0; i < 8; i++) {
    Listener* l = &g_listeners[i];
    if (l->h) continue;
    l->h = h;
    l->areas = areas;
    l->n = 0;
    for (int k = 0; k < 10; k++)
      if (areas & (1u << ((seq[k][0] >> 25) & 0x3F))) {
        l->ids[l->n] = seq[k][0];
        l->params[l->n++] = seq[k][1];
      }
    if (!l->n) ResetEvent(h);
    break;
  }
  LeaveCriticalSection(&g_mu);
  return h;
}

X(BOOL, XNotifyGetNext)(HANDLE h, DWORD filter, DWORD* pid, DWORD* pparam) {
  BOOL got = FALSE;
  EnterCriticalSection(&g_mu);
  for (int i = 0; i < 8; i++) {
    Listener* l = &g_listeners[i];
    if (l->h != h) continue;
    for (DWORD k = 0; k < l->n; k++) {
      if (filter && l->ids[k] != filter) continue;
      if (pid) *pid = l->ids[k];
      if (pparam) *pparam = l->params[k];
      memmove(&l->ids[k], &l->ids[k + 1], (l->n - k - 1) * 4);
      memmove(&l->params[k], &l->params[k + 1], (l->n - k - 1) * 4);
      if (!--l->n) ResetEvent(h);
      got = TRUE;
      break;
    }
    break;
  }
  LeaveCriticalSection(&g_mu);
  return got;
}

X(DWORD, XCloseHandle)(HANDLE h) {
  if (!h) return 0;
  EnterCriticalSection(&g_mu);
  for (int i = 0; i < 8; i++)
    if (g_listeners[i].h == h) g_listeners[i].h = NULL;
  LeaveCriticalSection(&g_mu);
  return CloseHandle(h);
}

X(DWORD, XNotifyPositionUI)(DWORD p) { return 0; }
X(DWORD, XGetOverlappedExtendedError)(XOV* ov) { return ov ? ov->ext_error : kErrorInvalidParameter; }
X(DWORD, XGetOverlappedResult)(XOV* ov, DWORD* r, BOOL wait) {
  if (r) *r = ov->high;
  return ov->low;
}
X(DWORD, XCancelOverlapped)(XOV* ov) { return 0; }
X(DWORD, XEnumerate)(HANDLE h, void* buf, DWORD cb, DWORD* count, XOV* ov) {
  if (ov) return Complete(ov, kErrorNoMoreFiles, 0);
  if (!count) return kErrorInvalidParameter;
  *count = 0;
  return kErrorNoMoreFiles;
}

// ---- Winsock ------------------------------------------------------------------

X(int, XWSAStartup)(WORD v, WSADATA* d) { return WSAStartup(v, d); }
X(int, XWSACleanup)(void) { return WSACleanup(); }
X(SOCKET, XCreateSocket)(int af, int type, int proto) {
  if (proto == 254) proto = type == SOCK_DGRAM ? IPPROTO_UDP : 0;  // VDP
  return socket(af, type, proto);
}
X(int, XSocketClose)(SOCKET s) { return closesocket(s); }
X(int, XSocketIOCTLSocket)(SOCKET s, long cmd, u_long* a) { return ioctlsocket(s, cmd, a); }
X(int, XSocketSetSockOpt)(SOCKET s, int l, int o, const char* v, int n) { return setsockopt(s, l, o, v, n); }
X(int, XSocketGetSockOpt)(SOCKET s, int l, int o, char* v, int* n) { return getsockopt(s, l, o, v, n); }
X(int, XSocketGetSockName)(SOCKET s, struct sockaddr* a, int* n) { return getsockname(s, a, n); }
X(int, XSocketBind)(SOCKET s, const struct sockaddr* a, int n) { return bind(s, a, n); }
X(int, XSocketRecvFrom)(SOCKET s, char* b, int n, int f, struct sockaddr* a, int* an) {
  return recvfrom(s, b, n, f, a, an);
}
X(int, XSocketSendTo)(SOCKET s, const char* b, int n, int f, const struct sockaddr* a, int an) {
  return sendto(s, b, n, f, a, an);
}
X(int, XSocketWSAGetLastError)(void) { return WSAGetLastError(); }
X(WSAEVENT, XWSACreateEvent)(void) { return WSACreateEvent(); }
X(BOOL, XWSACloseEvent)(WSAEVENT e) { return WSACloseEvent(e); }
X(DWORD, XWSAWaitForMultipleEvents)(DWORD n, const WSAEVENT* e, BOOL all, DWORD t, BOOL a) {
  return WSAWaitForMultipleEvents(n, e, all, t, a);
}
X(int, XWSAEventSelect)(SOCKET s, WSAEVENT e, long m) { return WSAEventSelect(s, e, m); }

// ---- XNet ---------------------------------------------------------------------

X(int, XNetStartup)(void* p) { return 0; }
X(int, XNetCleanup)(void) { return 0; }
X(int, XNetCreateKey)(void* id, void* key) { return 0; }
X(int, XNetRegisterKey)(void* id, void* key) { return 0; }
X(int, XNetUnregisterKey)(void* id) { return 0; }
X(int, XNetXnAddrToInAddr)(void* xna, void* id, DWORD* ina) {
  if (ina) *ina = 0;
  return 0;
}
X(int, XNetInAddrToXnAddr)(DWORD ina, void* xna, void* id) { return 0; }
X(int, XNetUnregisterInAddr)(DWORD ina) { return 0; }
X(int, XNetQosListen)(void* id, void* d, DWORD n, DWORD bps, DWORD f) { return 0; }
X(int, XNetQosServiceLookup)(DWORD f, HANDLE e, void** pp) { return kErrorFunctionFailed; }
X(DWORD, XNetGetTitleXnAddr)(BYTE* xna) {
  if (xna) {
    memset(xna, 0, 36);
    *(DWORD*)xna = 0x0100007F;
  }
  return 4;  // XNET_GET_XNADDR_STATIC
}
X(DWORD, XNetGetEthernetLinkStatus)(void) { return 0x1 | 0x2 | 0x8; }

// ---- lifetime and rendering hooks -------------------------------------------

X(DWORD, XLiveInitializeEx)(void* p, DWORD v) { return 0; }
X(DWORD, XLiveUninitialize)(void) { return 0; }
X(DWORD, XLiveRender)(void) { return 0; }
X(DWORD, XLiveOnCreateDevice)(void* d, void* pp) { return 0; }
X(DWORD, XLiveOnDestroyDevice)(void) { return 0; }
X(DWORD, XLiveOnResetDevice)(void* pp) { return 0; }
X(DWORD, XLivePreTranslateMessage)(const MSG* m) { return 0; }
X(DWORD, XOnlineStartup)(void) { return 0; }
X(DWORD, XOnlineCleanup)(void) { return 0; }

// ---- guide UI: never shown ------------------------------------------------------

X(DWORD, XShowGuideUI)(DWORD u) { return 0; }
X(DWORD, XShowGamerCardUI)(DWORD u, DWORD lo, DWORD hi) { return 0; }
X(DWORD, XShowSigninUI)(DWORD n, DWORD f) { return 0; }
X(DWORD, XShowMessageBoxUI)(DWORD u, void* t, void* x, DWORD n, void* b, DWORD fb, DWORD f, void* r, XOV* ov) {
  return Finish(ov, kErrorFunctionFailed);
}
X(DWORD, XShowFriendsUI)(DWORD u) { return 0; }

// ---- protected data ----------------------------------------------------------

static DWORD CopyData(const BYTE* in, DWORD n, BYTE* out, DWORD* psize) {
  if (!psize) return HRESULT_FROM_WIN32(kErrorInvalidParameter);
  if (*psize < n || !out) {
    *psize = n;
    return HRESULT_FROM_WIN32(kErrorInsufficientBuffer);
  }
  memmove(out, in, n);
  *psize = n;
  return 0;
}
X(DWORD, XLiveProtectData)(BYTE* in, DWORD n, BYTE* out, DWORD* ps, HANDLE h) { return CopyData(in, n, out, ps); }
X(DWORD, XLiveUnprotectData)(BYTE* in, DWORD n, BYTE* out, DWORD* ps, HANDLE* h) { return CopyData(in, n, out, ps); }
X(DWORD, XLiveCreateProtectedDataContext)(void* info, HANDLE* ph) {
  if (!ph) return 1;
  *ph = Dummy();
  return 0;
}
X(DWORD, XLiveQueryProtectedDataInformation)(HANDLE h, void* info) { return 0; }
X(DWORD, XLiveCloseProtectedDataContext)(HANDLE h) {
  CloseHandle(h);
  return 0;
}

// ---- users ---------------------------------------------------------------------

X(DWORD, XUserGetXUID)(DWORD u, unsigned long long* x) {
  if (u) return kErrorNoSuchUser;
  if (x) *x = kXuid;
  return 0;
}
X(DWORD, XUserGetSigninState)(DWORD u) { return u == 0 ? 1 : 0; }
X(DWORD, XUserGetName)(DWORD u, char* buf, DWORD cap) {
  if (u || !buf) return kErrorNoSuchUser;
  lstrcpynA(buf, kUserName, cap);
  return 0;
}
X(DWORD, XUserGetSigninInfo)(DWORD u, DWORD f, BYTE* info) {
  if (!info) return kErrorInvalidParameter;
  memset(info, 0, 40);
  if (u) return kErrorNoSuchUser;
  *(unsigned long long*)info = kXuid;
  *(DWORD*)(info + 8) = 1;
  *(DWORD*)(info + 12) = 1;
  strcpy((char*)info + 24, kUserName);
  return 0;
}
X(DWORD, XUserCheckPrivilege)(DWORD u, DWORD p, BOOL* r) {
  if (r) *r = u == 0;
  return u == 0 ? 0 : kErrorNoSuchUser;
}
X(DWORD, XUserAreUsersFriends)(DWORD u, void* x, DWORD n, BOOL* r, XOV* ov) {
  if (r) *r = 0;
  return Finish(ov, 0);
}
X(DWORD, XUserMuteListQuery)(DWORD u, DWORD lo, DWORD hi, BOOL* r) {
  if (r) *r = 0;
  return 0;
}
X(DWORD, XUserSetContext)(DWORD u, DWORD id, DWORD v) { return 0; }
X(DWORD, XUserWriteAchievements)(DWORD n, void* a, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XUserCreateAchievementEnumerator)(DWORD t, DWORD u, DWORD lo, DWORD hi, DWORD f, DWORD s, DWORD n,
                                           DWORD* pcb, HANDLE* ph) {
  if (pcb) *pcb = n * 36;
  if (ph) *ph = Dummy();
  return 0;
}
X(DWORD, XUserFindUsers)(DWORD lo, DWORD hi, DWORD n, void* f, DWORD cb, void* r, XOV* ov) {
  return Finish(ov, kErrorFunctionFailed);
}

static void TitleSettingPath(DWORD sid, char* out) {
  DWORD id = sid & 0x3FFF;
  out[0] = 0;
  if (id < 0x3FFD) return;
  CreateDirectoryA("C:\\xlive", NULL);
  sprintf(out, "C:\\xlive\\Title%lu.dat", 0x3FFF - id + 1);
}

// XUSER_PROFILE_SETTING: 40 bytes (source @0, user @8, id @16, type @24,
// binary {cb @32, pb @36}).
X(DWORD, XUserReadProfileSettings)(DWORD t, DWORD u, DWORD n, DWORD* ids, DWORD* pcb, BYTE* res, XOV* ov) {
  if (!pcb || (n && !ids)) return Finish(ov, kErrorInvalidParameter);
  DWORD need = 8 + 40 * n;
  for (DWORD i = 0; i < n; i++) need += (ids[i] >> 16) & 0xFFF;
  if (*pcb < need || !res) {
    *pcb = need;
    return ov ? Complete(ov, kErrorInsufficientBuffer, need) : kErrorInsufficientBuffer;
  }
  memset(res, 0, need);
  BYTE* settings = res + 8;
  *(DWORD*)res = n;
  *(BYTE**)(res + 4) = settings;
  BYTE* data = settings + 40 * n;
  for (DWORD i = 0; i < n; i++) {
    DWORD sid = ids[i], type = sid >> 28, size = (sid >> 16) & 0xFFF;
    BYTE* s = settings + 40 * i;
    *(DWORD*)(s + 8) = u;
    *(DWORD*)(s + 16) = sid;
    s[24] = (BYTE)type;
    char path[64];
    TitleSettingPath(sid, path);
    FILE* f;
    if (type == 6 && path[0] && (f = fopen(path, "rb"))) {
      DWORD len = 0;
      if (fread(&len, 4, 1, f) == 1) {
        if (len > size) len = size;
        len = (DWORD)fread(data, 1, len, f);
        *(DWORD*)s = 2;  // XSOURCE_TITLE
        *(DWORD*)(s + 32) = len;
        *(BYTE**)(s + 36) = data;
      }
      fclose(f);
    }
    data += size;
  }
  return Finish(ov, 0);
}

X(DWORD, XUserWriteProfileSettings)(DWORD u, DWORD n, BYTE* settings, XOV* ov) {
  for (DWORD i = 0; i < n; i++) {
    BYTE* s = settings + 40 * i;
    DWORD sid = *(DWORD*)(s + 16);
    char path[64];
    TitleSettingPath(sid, path);
    if (sid >> 28 != 6 || !path[0]) continue;
    DWORD len = *(DWORD*)(s + 32);
    FILE* f = fopen(path, "wb");
    if (!f) continue;
    fwrite(&len, 4, 1, f);
    if (len) fwrite(*(BYTE**)(s + 36), 1, len, f);
    fclose(f);
  }
  return Finish(ov, 0);
}

// ---- sessions, invites, storage -----------------------------------------------

X(DWORD, XSessionCreate)(DWORD f, DWORD u, DWORD pub, DWORD priv, void* nonce, void* info, XOV* ov, HANDLE* ph) {
  if (ph) *ph = Dummy();
  return Finish(ov, 0);
}
X(DWORD, XSessionSearchEx)(DWORD a, DWORD b, DWORD c, DWORD d, DWORD e, DWORD f, void* g, void* h, DWORD* pcb,
                           void* res, XOV* ov) {
  return Finish(ov, kErrorFunctionFailed);
}
X(DWORD, XInviteGetAcceptedInfo)(DWORD u, void* info) { return kErrorFunctionFailed; }
X(DWORD, XStorageBuildServerPathByXuid)(DWORD lo, DWORD hi, DWORD t, DWORD x, void* n, void* out, DWORD* plen) {
  if (plen) *plen = 0;
  return kErrorFunctionFailed;
}
X(DWORD, XSessionStart)(HANDLE h, DWORD f, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionEnd)(HANDLE h, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionDelete)(HANDLE h, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionWriteStats)(HANDLE h, DWORD lo, DWORD hi, DWORD n, void* v, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionModify)(HANDLE h, DWORD f, DWORD pub, DWORD priv, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionMigrateHost)(HANDLE h, DWORD u, void* info, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionLeaveLocal)(HANDLE h, DWORD n, DWORD* u, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionLeaveRemote)(HANDLE h, DWORD n, void* x, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionJoinRemote)(HANDLE h, DWORD n, void* x, BOOL* p, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionJoinLocal)(HANDLE h, DWORD n, DWORD* u, BOOL* p, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XSessionArbitrationRegister)(HANDLE h, DWORD f, DWORD lo, DWORD hi, DWORD* pcb, void* r, XOV* ov) {
  return Finish(ov, kErrorFunctionFailed);
}
X(DWORD, XUserSetContextEx)(DWORD u, DWORD id, DWORD v, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XUserSetPropertyEx)(DWORD u, DWORD id, DWORD n, void* v, XOV* ov) { return Finish(ov, 0); }
X(DWORD, XUserReadStats)(DWORD t, DWORD n, void* x, DWORD ns, void* spec, DWORD* pcb, DWORD* res, XOV* ov) {
  if (pcb && *pcb == 0) {
    *pcb = 4;
    return Finish(ov, kErrorInsufficientBuffer);
  }
  if (res) *res = 0;
  return Finish(ov, 0);
}
X(DWORD, XUserCreateStatsEnumeratorByRank)(DWORD t, DWORD r, DWORD n, DWORD ns, void* spec, DWORD* pcb, HANDLE* ph) {
  if (pcb) *pcb = 0;
  if (ph) *ph = 0;
  return kErrorFunctionFailed;
}
X(int, XNetQosLookup)(DWORD a, void* b, void* c, void* d, DWORD e, void* f, void* g, DWORD h, DWORD i, DWORD j,
                      HANDLE k, void** l) {
  return kErrorFunctionFailed;
}
X(int, XNetQosRelease)(void* q) { return 0; }
X(DWORD, XStorageUploadFromMemory)(DWORD u, void* path, DWORD n, void* b, XOV* ov) {
  return Finish(ov, kErrorFunctionFailed);
}
X(DWORD, XStorageBuildServerPath)(DWORD u, DWORD fac, void* ctx, DWORD cb, void* name, WCHAR* out, DWORD* plen) {
  if (out) out[0] = 0;
  if (plen) *plen = 1;
  return kErrorFunctionFailed;
}
X(DWORD, XStorageDownloadToMemory)(DWORD u, void* path, DWORD cb, void* b, DWORD cr, void* r, XOV* ov) {
  return Finish(ov, kErrorNotFound);
}
