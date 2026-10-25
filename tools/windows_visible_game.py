"""Start the TikTok renderer on the interactive desktop, even from a private desktop.

subprocess.STARTUPINFO does not expose lpDesktop. Use CreateProcessW explicitly;
never move or close another application's window. The returned object implements
the small Popen interface used by LiveSupervisor.
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
import os
import subprocess
import time


class _StartupInfo(ctypes.Structure):
    _fields_ = [
        ("cb", wintypes.DWORD), ("lpReserved", wintypes.LPWSTR),
        ("lpDesktop", wintypes.LPWSTR), ("lpTitle", wintypes.LPWSTR),
        ("dwX", wintypes.DWORD), ("dwY", wintypes.DWORD),
        ("dwXSize", wintypes.DWORD), ("dwYSize", wintypes.DWORD),
        ("dwXCountChars", wintypes.DWORD), ("dwYCountChars", wintypes.DWORD),
        ("dwFillAttribute", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
        ("wShowWindow", wintypes.WORD), ("cbReserved2", wintypes.WORD),
        ("lpReserved2", ctypes.c_void_p), ("hStdInput", wintypes.HANDLE),
        ("hStdOutput", wintypes.HANDLE), ("hStdError", wintypes.HANDLE),
    ]


class _ProcessInfo(ctypes.Structure):
    _fields_ = [("hProcess", wintypes.HANDLE), ("hThread", wintypes.HANDLE),
                ("dwProcessId", wintypes.DWORD), ("dwThreadId", wintypes.DWORD)]


class InteractiveGameProcess:
    def __init__(self, args: list[str], *, cwd: str, env: dict[str, str]):
        if os.name != "nt":
            raise OSError("InteractiveGameProcess requires Windows")
        args = [os.fspath(arg) for arg in args]
        cwd = os.fspath(cwd)
        self.args = list(args)
        self.returncode: int | None = None
        self._handle = None
        self._kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self._kernel.CreateProcessW.argtypes = [
            wintypes.LPCWSTR, wintypes.LPWSTR, ctypes.c_void_p, ctypes.c_void_p,
            wintypes.BOOL, wintypes.DWORD, ctypes.c_void_p, wintypes.LPCWSTR,
            ctypes.POINTER(_StartupInfo), ctypes.POINTER(_ProcessInfo)]
        self._kernel.CreateProcessW.restype = wintypes.BOOL
        self._kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        self._kernel.WaitForSingleObject.restype = wintypes.DWORD
        self._kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        self._kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
        self._kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        startup = _StartupInfo()
        startup.cb = ctypes.sizeof(startup)
        startup.lpDesktop = "winsta0\\default"
        startup.dwFlags = 1  # STARTF_USESHOWWINDOW
        startup.wShowWindow = 1  # SW_SHOWNORMAL; do not inherit SW_HIDE.
        command = ctypes.create_unicode_buffer(subprocess.list2cmdline(args))
        environment = ctypes.create_unicode_buffer(
            "\0".join(f"{key}={value}" for key, value in sorted(env.items(), key=lambda p: p[0].upper())) + "\0\0")
        info = _ProcessInfo()
        if not self._kernel.CreateProcessW(
            args[0], command, None, None, False, 0x400,  # CREATE_UNICODE_ENVIRONMENT
            environment, cwd, ctypes.byref(startup), ctypes.byref(info)):
            raise ctypes.WinError(ctypes.get_last_error())
        self.pid = int(info.dwProcessId)
        self._handle = info.hProcess
        self._kernel.CloseHandle(info.hThread)

    def poll(self) -> int | None:
        if self.returncode is None and self._kernel.WaitForSingleObject(self._handle, 0) == 0:
            code = wintypes.DWORD()
            if not self._kernel.GetExitCodeProcess(self._handle, ctypes.byref(code)):
                raise ctypes.WinError(ctypes.get_last_error())
            self.returncode = int(code.value)
            self._kernel.CloseHandle(self._handle)
            self._handle = None
        return self.returncode

    def wait(self, timeout: float | None = None) -> int:
        deadline = None if timeout is None else time.monotonic() + timeout
        while self.poll() is None:
            if deadline is not None and time.monotonic() >= deadline:
                raise subprocess.TimeoutExpired(self.args, timeout)
            time.sleep(.02)
        return self.returncode

    def terminate(self) -> None:
        if self.poll() is None and not self._kernel.TerminateProcess(self._handle, 1):
            raise ctypes.WinError(ctypes.get_last_error())

    kill = terminate


def spawn_tiktok_game(args: list[str], *, cwd: str, env: dict[str, str]):
    if any(arg in ("--headless", "headless") for arg in args):
        raise ValueError("The production TikTok renderer must be graphical")
    if os.name == "nt":
        return InteractiveGameProcess(args, cwd=cwd, env=env)
    return subprocess.Popen(args, cwd=cwd, env=env)
