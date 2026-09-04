"""Runs karaoke's expensive commands on a machine that has a GPU.

Prod (music.ltvb.nl) is 6 vCPU with no GPU, where htdemucs takes ~205s a song
-- about 80% of a prepare, and only just faster than the song is long, so
queued singers wait behind each other. This agent is the far end of an SSH
connection: prod stages inputs into a work directory here, runs the very same
commands it would otherwise have run locally, and pulls the finished artifacts
back.

It decides nothing. Every argv is built by Ruby, so the duration windows, the
yt-dlp player-client walk and the artifact set all stay in one place and this
file never has to be redeployed when they change.

One request per invocation, framed so that no variable data ever reaches a
shell -- which matters more than usual here, because this box is Windows and
`ssh host "cmd"` lands in cmd.exe with its own quoting rules. A single line of
JSON arrives on stdin; a single line of JSON leaves on stdout:

    {"action": "ping"}                                    -> liveness, no imports
    {"action": "probe"}                                   -> torch/CUDA report
    {"action": "exec", "argv": [...], "outputs": [...]}   -> run a command
    {"action": "put", "token": t, "name": n, "size": s}   -> + s raw bytes on stdin
    {"action": "fetch", "token": t, "name": n}            -> raw bytes on stdout
    {"action": "release", "token": t}                     -> drop the work directory

"{{work}}" inside an argv entry is replaced with the request's work directory,
so the caller never needs to know this box's path syntax. An "exec" without a
token opens a new work directory and returns it; passing that token back runs
the next command in the same one, which is how a download, a separation and an
mp3 encode share a directory without the audio ever crossing the network.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

# Work directories are handed out by name and named back by the caller, so both
# halves are checked against these rather than trusted: a token or a filename
# containing a separator or ".." would otherwise reach anywhere on the disk.
TOKEN_PATTERN = re.compile(r"\A[0-9a-f]{32}\Z")
NAME_PATTERN = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")

WORK_PLACEHOLDER = "{{work}}"
# A crashed prepare leaves its directory behind; the next request sweeps up
# anything old enough that no live job could still be using it.
STALE_SECONDS = 12 * 60 * 60
DEFAULT_TIMEOUT_SECONDS = 1800
# Enough of a failing command's output to tell a 403 from a missing model file,
# without shipping a megabyte of demucs progress bars back over the wire. The
# tail rather than the head, because a command that printed one answer (the
# alignment offset) and a command that failed both put what matters last.
OUTPUT_TAIL_BYTES = 4000
# Streamed rather than read whole: a vocal stem is tens of megabytes and this
# box is not necessarily generous with RAM.
CHUNK_BYTES = 1 << 20


def base_dir():
    configured = os.environ.get("KARAOKE_GPU_WORKDIR", "").strip()
    root = Path(configured) if configured else Path(tempfile.gettempdir()) / "karaoke-gpu"
    root.mkdir(parents=True, exist_ok=True)
    return root


def sweep_stale(root):
    cutoff = time.time() - STALE_SECONDS
    for path in root.iterdir():
        try:
            if path.is_dir() and path.stat().st_mtime < cutoff:
                shutil.rmtree(path, ignore_errors=True)
        except OSError:
            pass


def work_dir(root, token, create=False):
    if not TOKEN_PATTERN.match(token or ""):
        raise ValueError("malformed work token")

    path = root / token
    if create:
        path.mkdir(parents=True, exist_ok=True)
    elif not path.is_dir():
        raise ValueError("unknown work token")
    return path


def staged_path(directory, name):
    if not NAME_PATTERN.match(name or ""):
        raise ValueError(f"malformed staged name: {name!r}")

    return directory / name


# --- Actions -------------------------------------------------------------

def do_ping(_request, _root):
    # Deliberately imports nothing: prod probes liveness before every prepare,
    # and importing torch to answer would cost seconds each time.
    return {"ok": True, "agent": 1, "platform": sys.platform, "python": sys.version.split()[0]}


def do_probe(_request, _root):
    report = {"ok": True, "platform": sys.platform, "python": sys.version.split()[0]}
    try:
        import torch

        report["torch"] = torch.__version__
        report["cuda"] = bool(torch.cuda.is_available())
        if report["cuda"]:
            report["gpu"] = torch.cuda.get_device_name(0)
            report["gpu_memory_gb"] = round(torch.cuda.get_device_properties(0).total_memory / 1e9, 1)
    except Exception as error:  # noqa: BLE001 - a probe reports faults, it does not raise them
        report["torch_error"] = f"{type(error).__name__}: {error}"

    for tool in ("ffmpeg", "yt-dlp", "node", "deno"):
        report[tool] = shutil.which(tool) or None
    return report


def do_exec(request, root):
    argv = request.get("argv") or []
    if not argv or not all(isinstance(entry, str) for entry in argv):
        raise ValueError("exec needs a non-empty argv of strings")

    # The caller normally names the work directory, so that a download, a
    # separation and an encode can be aimed at one directory without a token
    # having to be round-tripped back first -- and so that two commands started
    # concurrently for the same song cannot each open a directory of their own.
    token = request.get("token") or uuid.uuid4().hex
    directory = work_dir(root, token, create=True)
    resolved = [entry.replace(WORK_PLACEHOLDER, str(directory)) for entry in argv]

    environment = dict(os.environ)
    # yt-dlp and demucs both scatter intermediates through the temp directory;
    # pointing it at the work directory means "release" cleans those up too.
    environment.update({"TMP": str(directory), "TEMP": str(directory), "TMPDIR": str(directory)})
    for key, value in (request.get("env") or {}).items():
        environment[str(key)] = str(value).replace(WORK_PLACEHOLDER, str(directory))

    timeout = float(request.get("timeout") or DEFAULT_TIMEOUT_SECONDS)
    started = time.monotonic()
    timed_out = False
    status = None
    stdout = b""
    stderr = b""

    try:
        completed = subprocess.run(
            resolved, cwd=str(directory), env=environment,
            stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout,
        )
        status = completed.returncode
        stdout = completed.stdout or b""
        stderr = completed.stderr or b""
    except subprocess.TimeoutExpired as expired:
        timed_out = True
        stdout = expired.stdout or b""
        stderr = expired.stderr or b""
    except FileNotFoundError as missing:
        return {
            "ok": False, "token": token, "error": f"not executable on this host: {missing.filename}",
        }

    # Declared up front by the caller, because "did it work" is decided by which
    # files appeared and not by an exit status -- yt-dlp in particular exits
    # non-zero on a --max-downloads stop, having produced exactly what we asked.
    outputs = {}
    for name in request.get("outputs") or []:
        path = staged_path(directory, name)
        if path.is_file():
            outputs[name] = path.stat().st_size

    return {
        "ok": not timed_out and status == 0,
        "token": token,
        "status": status,
        "timed_out": timed_out,
        "seconds": round(time.monotonic() - started, 1),
        "outputs": outputs,
        "stdout": stdout[-OUTPUT_TAIL_BYTES:].decode("utf-8", "replace"),
        "stderr": stderr[-OUTPUT_TAIL_BYTES:].decode("utf-8", "replace"),
    }


def do_put(request, root):
    directory = work_dir(root, request.get("token"), create=True)
    path = staged_path(directory, request.get("name"))
    remaining = int(request.get("size") or 0)

    with path.open("wb") as handle:
        while remaining > 0:
            chunk = sys.stdin.buffer.read(min(CHUNK_BYTES, remaining))
            if not chunk:
                raise ValueError("stream ended before the declared size")
            handle.write(chunk)
            remaining -= len(chunk)

    return {"ok": True, "token": request["token"], "name": request["name"], "size": path.stat().st_size}


def do_fetch(request, root):
    directory = work_dir(root, request.get("token"))
    path = staged_path(directory, request.get("name"))
    if not path.is_file():
        raise ValueError(f"nothing staged as {request.get('name')!r}")

    # The odd one out: raw bytes, no JSON envelope, so the caller can redirect
    # this straight into its own file. Failure is signalled by the exit status.
    with path.open("rb") as handle:
        shutil.copyfileobj(handle, sys.stdout.buffer, CHUNK_BYTES)
    sys.stdout.buffer.flush()
    return None


def do_release(request, root):
    token = request.get("token")
    if TOKEN_PATTERN.match(token or ""):
        shutil.rmtree(root / token, ignore_errors=True)
    return {"ok": True}


ACTIONS = {
    "ping": do_ping,
    "probe": do_probe,
    "exec": do_exec,
    "put": do_put,
    "fetch": do_fetch,
    "release": do_release,
}


def main():
    try:
        header = sys.stdin.buffer.readline()
        request = json.loads(header.decode("utf-8"))
        action = ACTIONS[request.get("action")]
    except (json.JSONDecodeError, KeyError, UnicodeDecodeError) as error:
        sys.stderr.write(f"unreadable request: {error}\n")
        return 2

    root = base_dir()
    sweep_stale(root)

    try:
        response = action(request, root)
    except Exception as error:  # noqa: BLE001 - every fault is reported, never raised
        sys.stderr.write(f"{type(error).__name__}: {error}\n")
        return 1

    if response is not None:
        # Written as bytes: Python's text stdout would turn these newlines into
        # CRLF on Windows, and the caller reads exactly one line.
        sys.stdout.buffer.write((json.dumps(response) + "\n").encode("utf-8"))
        sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
