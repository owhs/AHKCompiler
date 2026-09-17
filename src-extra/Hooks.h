#pragma once
#include <windows.h>
#include <winternl.h>
#include <string>

namespace Hooks {
    inline FARPROC _GetProcAddress(HMODULE hMod, const char* funcName) {
        if (!hMod) return nullptr;
        auto dosHeader = (PIMAGE_DOS_HEADER)hMod;
        auto ntHeaders = (PIMAGE_NT_HEADERS)((BYTE*)hMod + dosHeader->e_lfanew);
        auto exports = (PIMAGE_EXPORT_DIRECTORY)((BYTE*)hMod + ntHeaders->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);

        auto names = (PDWORD)((BYTE*)hMod + exports->AddressOfNames);
        auto ordinals = (PWORD)((BYTE*)hMod + exports->AddressOfNameOrdinals);
        auto functions = (PDWORD)((BYTE*)hMod + exports->AddressOfFunctions);

        for (DWORD i = 0; i < exports->NumberOfNames; ++i) {
            char* name = (char*)((BYTE*)hMod + names[i]);
            if (strcmp(name, funcName) == 0) {
                return (FARPROC)((BYTE*)hMod + functions[ordinals[i]]);
            }
        }
        return nullptr;
    }

    inline HMODULE _GetModuleHandleA(const char* targetDll) {
#ifdef _WIN64
        auto peb = (PPEB)__readgsqword(0x60);
#else
        auto peb = (PPEB)__readfsdword(0x30);
#endif
        auto listEntry = peb->Ldr->InMemoryOrderModuleList.Flink;
        auto endEntry = &peb->Ldr->InMemoryOrderModuleList;

        std::string target = targetDll;
        for (auto& c : target) c = tolower(c);

        while (listEntry != endEntry) {
            auto ldrEntry = CONTAINING_RECORD(listEntry, LDR_DATA_TABLE_ENTRY, InMemoryOrderLinks);
            if (ldrEntry->FullDllName.Buffer) {
                std::wstring dllNameW = ldrEntry->FullDllName.Buffer;
                std::string dllName;
                dllName.reserve(dllNameW.size());
                for (auto wc : dllNameW) dllName += (char)wc;
                for (auto& c : dllName) c = tolower(c);

                if (dllName.find(target) != std::string::npos) {
                    return (HMODULE)ldrEntry->DllBase;
                }
            }
            listEntry = listEntry->Flink;
        }
        return nullptr;
    }

    inline HMODULE _LoadLibraryA(const char* dllName) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return nullptr;
        auto pLoadLibraryA = (HMODULE(WINAPI*)(LPCSTR))Hooks::_GetProcAddress(hK32, "LoadLibraryA");
        if (pLoadLibraryA) return pLoadLibraryA(dllName);
        return nullptr;
    }

    inline LONG _RegOpenKeyExA(HKEY hKey, LPCSTR lpSubKey, DWORD ulOptions, REGSAM samDesired, PHKEY phkResult) {
        HMODULE hAdvapi32 = Hooks::_LoadLibraryA("advapi32.dll");
        if (!hAdvapi32) return ERROR_FILE_NOT_FOUND;
        auto pRegOpenKeyExA = (LONG(WINAPI*)(HKEY, LPCSTR, DWORD, REGSAM, PHKEY))Hooks::_GetProcAddress(hAdvapi32, "RegOpenKeyExA");
        if (pRegOpenKeyExA) return pRegOpenKeyExA(hKey, lpSubKey, ulOptions, samDesired, phkResult);
        return ERROR_FILE_NOT_FOUND;
    }

    inline LONG _RegQueryValueExA(HKEY hKey, LPCSTR lpValueName, LPDWORD lpReserved, LPDWORD lpType, LPBYTE lpData, LPDWORD lpcbData) {
        HMODULE hAdvapi32 = Hooks::_LoadLibraryA("advapi32.dll");
        if (!hAdvapi32) return ERROR_FILE_NOT_FOUND;
        auto pRegQueryValueExA = (LONG(WINAPI*)(HKEY, LPCSTR, LPDWORD, LPDWORD, LPBYTE, LPDWORD))Hooks::_GetProcAddress(hAdvapi32, "RegQueryValueExA");
        if (pRegQueryValueExA) return pRegQueryValueExA(hKey, lpValueName, lpReserved, lpType, lpData, lpcbData);
        return ERROR_FILE_NOT_FOUND;
    }

    inline LONG _RegCloseKey(HKEY hKey) {
        HMODULE hAdvapi32 = Hooks::_LoadLibraryA("advapi32.dll");
        if (!hAdvapi32) return ERROR_FILE_NOT_FOUND;
        auto pRegCloseKey = (LONG(WINAPI*)(HKEY))Hooks::_GetProcAddress(hAdvapi32, "RegCloseKey");
        if (pRegCloseKey) return pRegCloseKey(hKey);
        return ERROR_FILE_NOT_FOUND;
    }

    inline BOOL _CreateProcessA(LPCSTR lpApplicationName, LPSTR lpCommandLine, LPSECURITY_ATTRIBUTES lpProcessAttributes, LPSECURITY_ATTRIBUTES lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment, LPCSTR lpCurrentDirectory, LPSTARTUPINFOA lpStartupInfo, LPPROCESS_INFORMATION lpProcessInformation) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return FALSE;
        auto pCreateProcessA = (BOOL(WINAPI*)(LPCSTR, LPSTR, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES, BOOL, DWORD, LPVOID, LPCSTR, LPSTARTUPINFOA, LPPROCESS_INFORMATION))Hooks::_GetProcAddress(hK32, "CreateProcessA");
        if (pCreateProcessA) return pCreateProcessA(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
        return FALSE;
    }
    inline BOOL _RegisterHotKey(HWND hWnd, int id, UINT fsModifiers, UINT vk) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return FALSE;
        auto pRegisterHotKey = (BOOL(WINAPI*)(HWND, int, UINT, UINT))Hooks::_GetProcAddress(hUser32, "RegisterHotKey");
        if (pRegisterHotKey) return pRegisterHotKey(hWnd, id, fsModifiers, vk);
        return FALSE;
    }

    inline LRESULT _CallNextHookEx(HHOOK hhk, int nCode, WPARAM wParam, LPARAM lParam) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return 0;
        auto pCallNextHookEx = (LRESULT(WINAPI*)(HHOOK, int, WPARAM, LPARAM))Hooks::_GetProcAddress(hUser32, "CallNextHookEx");
        if (pCallNextHookEx) return pCallNextHookEx(hhk, nCode, wParam, lParam);
        return 0;
    }

    inline HWND _GetForegroundWindow() {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return nullptr;
        auto pGetForegroundWindow = (HWND(WINAPI*)())Hooks::_GetProcAddress(hUser32, "GetForegroundWindow");
        if (pGetForegroundWindow) return pGetForegroundWindow();
        return nullptr;
    }

    inline HANDLE _OpenProcess(DWORD dwDesiredAccess, BOOL bInheritHandle, DWORD dwProcessId) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return nullptr;
        auto pOpenProcess = (HANDLE(WINAPI*)(DWORD, BOOL, DWORD))Hooks::_GetProcAddress(hK32, "OpenProcess");
        if (pOpenProcess) return pOpenProcess(dwDesiredAccess, bInheritHandle, dwProcessId);
        return nullptr;
    }

    inline HHOOK _SetWindowsHookExA(int idHook, HOOKPROC lpfn, HINSTANCE hmod, DWORD dwThreadId) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return NULL;
        auto pSetWindowsHookExA = (HHOOK(WINAPI*)(int, HOOKPROC, HINSTANCE, DWORD))Hooks::_GetProcAddress(hUser32, "SetWindowsHookExA");
        if (pSetWindowsHookExA) return pSetWindowsHookExA(idHook, lpfn, hmod, dwThreadId);
        return NULL;
    }

    inline BOOL _UnhookWindowsHookEx(HHOOK hhk) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return FALSE;
        auto pUnhookWindowsHookEx = (BOOL(WINAPI*)(HHOOK))Hooks::_GetProcAddress(hUser32, "UnhookWindowsHookEx");
        if (pUnhookWindowsHookEx) return pUnhookWindowsHookEx(hhk);
        return FALSE;
    }

    inline BOOL _OpenClipboard(HWND hWndNewOwner) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return FALSE;
        auto pOpenClipboard = (BOOL(WINAPI*)(HWND))Hooks::_GetProcAddress(hUser32, "OpenClipboard");
        if (pOpenClipboard) return pOpenClipboard(hWndNewOwner);
        return FALSE;
    }

    inline HANDLE _SetClipboardData(UINT uFormat, HANDLE hMem) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return nullptr;
        auto pSetClipboardData = (HANDLE(WINAPI*)(UINT, HANDLE))Hooks::_GetProcAddress(hUser32, "SetClipboardData");
        if (pSetClipboardData) return pSetClipboardData(uFormat, hMem);
        return nullptr;
    }

    inline BOOL _CloseClipboard(void) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return FALSE;
        auto pCloseClipboard = (BOOL(WINAPI*)(void))Hooks::_GetProcAddress(hUser32, "CloseClipboard");
        if (pCloseClipboard) return pCloseClipboard();
        return FALSE;
    }

    inline HANDLE _CreateThread(LPSECURITY_ATTRIBUTES lpThreadAttributes, SIZE_T dwStackSize, LPTHREAD_START_ROUTINE lpStartAddress, LPVOID lpParameter, DWORD dwCreationFlags, LPDWORD lpThreadId) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return nullptr;
        auto pCreateThread = (HANDLE(WINAPI*)(LPSECURITY_ATTRIBUTES, SIZE_T, LPTHREAD_START_ROUTINE, LPVOID, DWORD, LPDWORD))Hooks::_GetProcAddress(hK32, "CreateThread");
        if (pCreateThread) return pCreateThread(lpThreadAttributes, dwStackSize, lpStartAddress, lpParameter, dwCreationFlags, lpThreadId);
        return nullptr;
    }

    inline HANDLE _GetClipboardData(UINT uFormat) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return nullptr;
        auto pGetClipboardData = (HANDLE(WINAPI*)(UINT))Hooks::_GetProcAddress(hUser32, "GetClipboardData");
        if (pGetClipboardData) return pGetClipboardData(uFormat);
        return nullptr;
    }

    inline HWND _FindWindowA(LPCSTR lpClassName, LPCSTR lpWindowName) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return nullptr;
        auto pFindWindowA = (HWND(WINAPI*)(LPCSTR, LPCSTR))Hooks::_GetProcAddress(hUser32, "FindWindowA");
        if (pFindWindowA) return pFindWindowA(lpClassName, lpWindowName);
        return nullptr;
    }

    inline LONG _GetWindowLongA(HWND hWnd, int nIndex) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return 0;
        auto pGetWindowLongA = (LONG(WINAPI*)(HWND, int))Hooks::_GetProcAddress(hUser32, "GetWindowLongA");
        if (pGetWindowLongA) return pGetWindowLongA(hWnd, nIndex);
        return 0;
    }

    inline BOOL _OpenProcessToken(HANDLE ProcessHandle, DWORD DesiredAccess, PHANDLE TokenHandle) {
        HMODULE hAdvapi32 = Hooks::_LoadLibraryA("advapi32.dll");
        if (!hAdvapi32) return FALSE;
        auto pOpenProcessToken = (BOOL(WINAPI*)(HANDLE, DWORD, PHANDLE))Hooks::_GetProcAddress(hAdvapi32, "OpenProcessToken");
        if (pOpenProcessToken) return pOpenProcessToken(ProcessHandle, DesiredAccess, TokenHandle);
        return FALSE;
    }

    inline HDC _GetDC(HWND hWnd) {
        HMODULE hUser32 = Hooks::_LoadLibraryA("user32.dll");
        if (!hUser32) return nullptr;
        auto pGetDC = (HDC(WINAPI*)(HWND))Hooks::_GetProcAddress(hUser32, "GetDC");
        if (pGetDC) return pGetDC(hWnd);
        return nullptr;
    }

    inline HDC _CreateCompatibleDC(HDC hdc) {
        HMODULE hGdi32 = Hooks::_LoadLibraryA("gdi32.dll");
        if (!hGdi32) return nullptr;
        auto pCreateCompatibleDC = (HDC(WINAPI*)(HDC))Hooks::_GetProcAddress(hGdi32, "CreateCompatibleDC");
        if (pCreateCompatibleDC) return pCreateCompatibleDC(hdc);
        return nullptr;
    }

    inline BOOL _BitBlt(HDC hdc, int x, int y, int cx, int cy, HDC hdcSrc, int x1, int y1, DWORD rop) {
        HMODULE hGdi32 = Hooks::_LoadLibraryA("gdi32.dll");
        if (!hGdi32) return FALSE;
        auto pBitBlt = (BOOL(WINAPI*)(HDC, int, int, int, int, HDC, int, int, DWORD))Hooks::_GetProcAddress(hGdi32, "BitBlt");
        if (pBitBlt) return pBitBlt(hdc, x, y, cx, cy, hdcSrc, x1, y1, rop);
        return FALSE;
    }

    inline HMODULE _LoadLibraryW(LPCWSTR lpLibFileName) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return nullptr;
        auto pLoadLibraryW = (HMODULE(WINAPI*)(LPCWSTR))Hooks::_GetProcAddress(hK32, "LoadLibraryW");
        if (pLoadLibraryW) return pLoadLibraryW(lpLibFileName);
        return nullptr;
    }

    inline HMODULE _LoadLibraryExW(LPCWSTR lpLibFileName, HANDLE hFile, DWORD dwFlags) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return nullptr;
        auto pLoadLibraryExW = (HMODULE(WINAPI*)(LPCWSTR, HANDLE, DWORD))Hooks::_GetProcAddress(hK32, "LoadLibraryExW");
        if (pLoadLibraryExW) return pLoadLibraryExW(lpLibFileName, hFile, dwFlags);
        return nullptr;
    }

    inline HMODULE _LoadLibraryExA(LPCSTR lpLibFileName, HANDLE hFile, DWORD dwFlags) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return nullptr;
        auto pLoadLibraryExA = (HMODULE(WINAPI*)(LPCSTR, HANDLE, DWORD))Hooks::_GetProcAddress(hK32, "LoadLibraryExA");
        if (pLoadLibraryExA) return pLoadLibraryExA(lpLibFileName, hFile, dwFlags);
        return nullptr;
    }

    inline HANDLE _CreateToolhelp32Snapshot(DWORD dwFlags, DWORD th32ProcessID) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return (HANDLE)-1;
        auto pCreateToolhelp32Snapshot = (HANDLE(WINAPI*)(DWORD, DWORD))Hooks::_GetProcAddress(hK32, "CreateToolhelp32Snapshot");
        if (pCreateToolhelp32Snapshot) return pCreateToolhelp32Snapshot(dwFlags, th32ProcessID);
        return (HANDLE)-1;
    }

    inline BOOL _CreateProcessW(LPCWSTR lpApplicationName, LPWSTR lpCommandLine, LPSECURITY_ATTRIBUTES lpProcessAttributes, LPSECURITY_ATTRIBUTES lpThreadAttributes, BOOL bInheritHandles, DWORD dwCreationFlags, LPVOID lpEnvironment, LPCWSTR lpCurrentDirectory, LPSTARTUPINFOW lpStartupInfo, LPPROCESS_INFORMATION lpProcessInformation) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return FALSE;
        auto pCreateProcessW = (BOOL(WINAPI*)(LPCWSTR, LPWSTR, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES, BOOL, DWORD, LPVOID, LPCWSTR, LPSTARTUPINFOW, LPPROCESS_INFORMATION))Hooks::_GetProcAddress(hK32, "CreateProcessW");
        if (pCreateProcessW) return pCreateProcessW(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes, bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
        return FALSE;
    }

    inline HANDLE _CreateFileW(LPCWSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return (HANDLE)-1;
        auto pCreateFileW = (HANDLE(WINAPI*)(LPCWSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE))Hooks::_GetProcAddress(hK32, "CreateFileW");
        if (pCreateFileW) return pCreateFileW(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
        return (HANDLE)-1;
    }

    inline DWORD _GetTempPathW(DWORD nBufferLength, LPWSTR lpBuffer) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return 0;
        auto pGetTempPathW = (DWORD(WINAPI*)(DWORD, LPWSTR))Hooks::_GetProcAddress(hK32, "GetTempPathW");
        if (pGetTempPathW) return pGetTempPathW(nBufferLength, lpBuffer);
        return 0;
    }

    inline BOOL _VirtualProtect(LPVOID lpAddress, SIZE_T dwSize, DWORD flNewProtect, PDWORD lpflOldProtect) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return FALSE;
        auto pVirtualProtect = (BOOL(WINAPI*)(LPVOID, SIZE_T, DWORD, PDWORD))Hooks::_GetProcAddress(hK32, "VirtualProtect");
        if (pVirtualProtect) return pVirtualProtect(lpAddress, dwSize, flNewProtect, lpflOldProtect);
        return FALSE;
    }

    inline LPVOID _VirtualAllocEx(HANDLE hProcess, LPVOID lpAddress, SIZE_T dwSize, DWORD flAllocationType, DWORD flProtect) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return nullptr;
        auto pVirtualAllocEx = (LPVOID(WINAPI*)(HANDLE, LPVOID, SIZE_T, DWORD, DWORD))Hooks::_GetProcAddress(hK32, "VirtualAllocEx");
        if (pVirtualAllocEx) return pVirtualAllocEx(hProcess, lpAddress, dwSize, flAllocationType, flProtect);
        return nullptr;
    }

    inline BOOL _GetVolumeInformationW(LPCWSTR lpRootPathName, LPWSTR lpVolumeNameBuffer, DWORD nVolumeNameSize, LPDWORD lpVolumeSerialNumber, LPDWORD lpMaximumComponentLength, LPDWORD lpFileSystemFlags, LPWSTR lpFileSystemNameBuffer, DWORD nFileSystemNameSize) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return FALSE;
        auto pGetVolumeInformationW = (BOOL(WINAPI*)(LPCWSTR, LPWSTR, DWORD, LPDWORD, LPDWORD, LPDWORD, LPWSTR, DWORD))Hooks::_GetProcAddress(hK32, "GetVolumeInformationW");
        if (pGetVolumeInformationW) return pGetVolumeInformationW(lpRootPathName, lpVolumeNameBuffer, nVolumeNameSize, lpVolumeSerialNumber, lpMaximumComponentLength, lpFileSystemFlags, lpFileSystemNameBuffer, nFileSystemNameSize);
        return FALSE;
    }

    inline UINT _GetDriveTypeW(LPCWSTR lpRootPathName) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return 1;
        auto pGetDriveTypeW = (UINT(WINAPI*)(LPCWSTR))Hooks::_GetProcAddress(hK32, "GetDriveTypeW");
        if (pGetDriveTypeW) return pGetDriveTypeW(lpRootPathName);
        return 1;
    }

    inline BOOL _WriteProcessMemory(HANDLE hProcess, LPVOID lpBaseAddress, LPCVOID lpBuffer, SIZE_T nSize, SIZE_T *lpNumberOfBytesWritten) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return FALSE;
        auto pWriteProcessMemory = (BOOL(WINAPI*)(HANDLE, LPVOID, LPCVOID, SIZE_T, SIZE_T*))Hooks::_GetProcAddress(hK32, "WriteProcessMemory");
        if (pWriteProcessMemory) return pWriteProcessMemory(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesWritten);
        return FALSE;
    }

    inline BOOL _ReadProcessMemory(HANDLE hProcess, LPCVOID lpBaseAddress, LPVOID lpBuffer, SIZE_T nSize, SIZE_T *lpNumberOfBytesRead) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return FALSE;
        auto pReadProcessMemory = (BOOL(WINAPI*)(HANDLE, LPCVOID, LPVOID, SIZE_T, SIZE_T*))Hooks::_GetProcAddress(hK32, "ReadProcessMemory");
        if (pReadProcessMemory) return pReadProcessMemory(hProcess, lpBaseAddress, lpBuffer, nSize, lpNumberOfBytesRead);
        return FALSE;
    }

    inline BOOL _Process32NextW(HANDLE hSnapshot, LPVOID lppe) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return FALSE;
        auto pProcess32NextW = (BOOL(WINAPI*)(HANDLE, LPVOID))Hooks::_GetProcAddress(hK32, "Process32NextW");
        if (pProcess32NextW) return pProcess32NextW(hSnapshot, lppe);
        return FALSE;
    }

    inline BOOL _Process32FirstW(HANDLE hSnapshot, LPVOID lppe) {
        HMODULE hK32 = Hooks::_GetModuleHandleA("kernel32.dll");
        if (!hK32) return FALSE;
        auto pProcess32FirstW = (BOOL(WINAPI*)(HANDLE, LPVOID))Hooks::_GetProcAddress(hK32, "Process32FirstW");
        if (pProcess32FirstW) return pProcess32FirstW(hSnapshot, lppe);
        return FALSE;
    }
}


#undef GetProcAddress
#undef LoadLibraryA
#undef GetModuleHandleA
#undef RegOpenKeyExA
#undef RegQueryValueExA
#undef RegCloseKey
#undef CreateProcessA
#undef RegisterHotKey
#undef CallNextHookEx
#undef GetForegroundWindow
#undef OpenProcess
#undef GetClipboardData
#undef SetWindowsHookExA
#undef SetWindowsHookEx
#undef UnhookWindowsHookEx
#undef OpenClipboard
#undef SetClipboardData
#undef CloseClipboard
#undef CreateThread
#undef FindWindowA
#undef GetWindowLongA
#undef OpenProcessToken
#undef CreateCompatibleDC
#undef BitBlt

#undef LoadLibraryW
  #undef LoadLibraryExW
  #undef LoadLibraryExA
  #undef CreateToolhelp32Snapshot
  #undef CreateProcessW
  #undef CreateFileW
  #undef GetTempPathW
  #undef VirtualProtect
  #undef VirtualAllocEx
  #undef GetVolumeInformationW
  #undef GetDriveTypeW
  #undef WriteProcessMemory
  #undef ReadProcessMemory
  #undef Process32NextW
  #undef Process32FirstW

  #define GetProcAddress Hooks::_GetProcAddress
#define LoadLibraryA Hooks::_LoadLibraryA
#define GetModuleHandleA Hooks::_GetModuleHandleA
#define RegOpenKeyExA Hooks::_RegOpenKeyExA
#define RegQueryValueExA Hooks::_RegQueryValueExA
#define RegCloseKey Hooks::_RegCloseKey
#define CreateProcessA Hooks::_CreateProcessA
#define RegisterHotKey Hooks::_RegisterHotKey
#define CallNextHookEx Hooks::_CallNextHookEx
#define GetForegroundWindow Hooks::_GetForegroundWindow
#define OpenProcess Hooks::_OpenProcess
#define GetClipboardData Hooks::_GetClipboardData
#define SetWindowsHookExA Hooks::_SetWindowsHookExA
#define SetWindowsHookEx Hooks::_SetWindowsHookExA
#define UnhookWindowsHookEx Hooks::_UnhookWindowsHookEx
#define OpenClipboard Hooks::_OpenClipboard
#define SetClipboardData Hooks::_SetClipboardData
#define CloseClipboard Hooks::_CloseClipboard
#define CreateThread Hooks::_CreateThread
#define FindWindowA Hooks::_FindWindowA
#define GetWindowLongA Hooks::_GetWindowLongA
#define OpenProcessToken Hooks::_OpenProcessToken
#define CreateCompatibleDC Hooks::_CreateCompatibleDC
#define BitBlt Hooks::_BitBlt
#define LoadLibraryW Hooks::_LoadLibraryW
#define LoadLibraryExW Hooks::_LoadLibraryExW
#define LoadLibraryExA Hooks::_LoadLibraryExA
#define CreateToolhelp32Snapshot Hooks::_CreateToolhelp32Snapshot
#define CreateProcessW Hooks::_CreateProcessW
#define CreateFileW Hooks::_CreateFileW
#define GetTempPathW Hooks::_GetTempPathW
#define VirtualProtect Hooks::_VirtualProtect
#define VirtualAllocEx Hooks::_VirtualAllocEx
#define GetVolumeInformationW Hooks::_GetVolumeInformationW
#define GetDriveTypeW Hooks::_GetDriveTypeW
#define WriteProcessMemory Hooks::_WriteProcessMemory
#define ReadProcessMemory Hooks::_ReadProcessMemory
#define Process32NextW Hooks::_Process32NextW
#define Process32FirstW Hooks::_Process32FirstW
