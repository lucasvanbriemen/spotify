#!/usr/bin/env python3
"""Small localhost-only HTTP wrapper around the persistent Kokoro pipeline."""

import io
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import soundfile as sf
from kokoro import KPipeline

HOST = "127.0.0.1"
PORT = 8765
SAMPLE_RATE = 24_000
MAX_TEXT_LENGTH = 5_000

pipeline = KPipeline(lang_code="a")
inference_lock = threading.Lock()


def synthesize(text: str, voice: str, speed: float) -> bytes:
    with inference_lock:
        chunks = [audio for _, _, audio in pipeline(text, voice=voice, speed=speed)]

    if not chunks:
        raise ValueError("Kokoro returned no audio")

    pause = np.zeros(int(SAMPLE_RATE * 0.08), dtype=np.float32)
    joined = chunks[0]
    for chunk in chunks[1:]:
        joined = np.concatenate((joined, pause, chunk))

    output = io.BytesIO()
    sf.write(output, joined, SAMPLE_RATE, format="WAV", subtype="PCM_16")
    return output.getvalue()


class Handler(BaseHTTPRequestHandler):
    server_version = "LTVBKokoro/1.0"

    def do_GET(self):
        if self.path != "/health":
            self.send_error(404)
            return

        self.respond_json(200, {"status": "ok"})

    def do_POST(self):
        if self.path != "/synthesize":
            self.send_error(404)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 50_000:
                raise ValueError("invalid request size")

            payload = json.loads(self.rfile.read(length))
            text = str(payload["text"]).strip()
            voice = str(payload["voice"]).strip()
            speed = float(payload.get("speed", 1.0))
            if not text or len(text) > MAX_TEXT_LENGTH:
                raise ValueError("invalid text")
            if not voice or not 0.75 <= speed <= 1.25:
                raise ValueError("invalid voice or speed")

            audio = synthesize(text, voice, speed)
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(audio)))
            self.end_headers()
            self.wfile.write(audio)
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            self.respond_json(422, {"error": str(error)})
        except Exception as error:
            self.respond_json(500, {"error": str(error)})

    def log_message(self, message_format, *args):
        print(f"{self.address_string()} - {message_format % args}", flush=True)

    def respond_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
