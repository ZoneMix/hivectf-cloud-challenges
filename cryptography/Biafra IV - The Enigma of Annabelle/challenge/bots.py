from enigma.machine import EnigmaMachine
from pathlib import Path
import socket
import os
import json
import asyncio
import random
import string

HOST = os.getenv("HOST", "127.0.0.1")
PORT = int(os.getenv("PORT", 1337))
FLAG = os.getenv("FLAG", "HiveCTF{test_flag}")
chat_history_file = Path(__file__).parent / "static" / "bot_chat.txt"

BOT_SENDERS = {"Quartermaster", "Signals", "Courier-3", "Clerk", "Aide", "General"}

def build_machine():
    return EnigmaMachine.from_key_sheet(
        rotors="I II III",
        reflector="B",
        ring_settings="1 1 1",
        plugboard_settings="AV BS CG DL FU HZ IN KM OW RX"
    )

def rand_start():
    return "".join(random.choice(string.ascii_uppercase) for _ in range(3))

def encrypt_message(message: str, start: str) -> str:
    machine = build_machine()
    machine.set_display(start)
    return machine.process_text(message)

def decrypt_message(ciphertext: str, start: str) -> str:
    machine = build_machine()
    machine.set_display(start)
    return machine.process_text(ciphertext)

def send_req(rfile, wfile, obj: dict) -> dict[str, list[dict[str, str]]]:
    wfile.write(json.dumps(obj) + "\n")
    wfile.flush()
    return json.loads(rfile.readline())

async def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((HOST, PORT))
        rfile = s.makefile("r", encoding="utf-8", newline="\n")
        wfile = s.makefile("w", encoding="utf-8", newline="\n")

        seen = set()

        # Seed encrypted bot traffic into the board
        with open(chat_history_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line: continue

                sender, content = line.split(": ", 1)
                start = rand_start()
                encrypted = encrypt_message(content, start)

                pd = { "method": "POST", "sender": sender, "start": start, "content": encrypted}
                resp = send_req(rfile, wfile, pd)

                if resp.get("ok"): seen.add((sender, encrypted, start))

                await asyncio.sleep(2)

        while True:
            resp = send_req(rfile, wfile, {"method": "GET"})
            if resp.get("ok"):
                for msg in resp["messages"]:
                    sender = msg.get("sender", "")
                    content = msg.get("content", "")
                    start = msg.get("start", "")

                    key = (sender, content, start)
                    if key in seen: continue
                    seen.add(key)

                    if len(start) != 3 or not start.isalpha(): continue

                    try: plaintext = decrypt_message(content, start)
                    except Exception: continue

                    if sender == "You"  and "flag" in plaintext.lower():
                        reply_start = rand_start()
                        reply_cipher = encrypt_message(FLAG, reply_start)

                        send_req(rfile, wfile, {
                            "method": "POST",
                            "sender": "General",
                            "start": reply_start,
                            "content": reply_cipher
                        })

            await asyncio.sleep(2)

if __name__ == "__main__": asyncio.run(main())