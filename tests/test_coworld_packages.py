"""Exercise policy packages through the compiled Coworld game and file protocol."""

import argparse
import hashlib
import io
import json
import os
import socket
import struct
import subprocess
import time
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_LIMIT = 64 * 1024 * 1024


def package(files: dict[str, bytes], compression: int) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=compression) as archive:
        for name, content in files.items():
            archive.writestr(name, content)
    return output.getvalue()


def episode(
    binary: Path,
    root: Path,
    name: str,
    candidate: bytes,
    rejected: bool,
    error: str = "Uncompressed data exceeds output limit",
    runtime_fault: bool = False,
) -> None:
    directory = root / name
    directory.mkdir()
    manifest = json.loads((ROOT / "coworld_manifest_template.json").read_text())
    config = next(
        variant["game_config"]
        for variant in manifest["variants"]
        if variant["id"] == "duel"
    )
    config["tokens"] = ["qualification-seat-0", "qualification-seat-1"]
    seats = []
    for slot, source in enumerate(
        [candidate, (ROOT / "players/classic.bas").read_bytes()]
    ):
        path = directory / f"player-{slot}"
        path.write_bytes(source)
        seats.append(
            {
                "slot": slot,
                "file_uri": path.as_uri(),
                "content_hash": "sha256:" + hashlib.sha256(source).hexdigest(),
                "size_bytes": len(source),
                "log_uri": (directory / f"player-{slot}.log").as_uri(),
                "artifact_uri": (directory / f"player-{slot}.zip").as_uri(),
            }
        )
    documents = {
        "CONFIG": config,
        "PLAYER_SEATS": {
            "schema": "coworld-player-seats/1",
            "seats": seats,
            "player_status_uri": (directory / "status.json").as_uri(),
        },
    }
    env = os.environ.copy()
    for key, document in documents.items():
        path = directory / f"{key}.json"
        path.write_text(json.dumps(document))
        env[f"COGAME_{key}_URI"] = path.as_uri()
    for key, filename in {
        "RESULTS": "results.json",
        "SAVE_REPLAY": "replay",
        "PLAYER_FAILURE": "failure.json",
    }.items():
        env[f"COGAME_{key}_URI"] = (directory / filename).as_uri()
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    env.update(COGAME_HOST="127.0.0.1", COGAME_PORT=str(port))
    started = time.monotonic()
    with (directory / "game.log").open("xb") as log:
        process = subprocess.Popen(
            [str(binary)], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT
        )
        try:
            load_rejected = rejected and not runtime_fault
            marker = directory / ("failure.json" if load_rejected else "results.json")
            unexpected = directory / (
                "results.json" if load_rejected else "failure.json"
            )
            while not marker.exists():
                assert not unexpected.exists(), (
                    f"{name}: unexpected outcome: {unexpected.read_text()}"
                )
                assert process.poll() is None, (directory / "game.log").read_text()
                assert time.monotonic() - started < 120, f"{name}: no terminal outcome"
                time.sleep(0.02)
            statuses = json.loads((directory / "status.json").read_text())["players"]
            assert [status["slot"] for status in statuses] == [0, 1]
            outcome = json.loads(marker.read_text())
            if rejected:
                if runtime_fault:
                    assert len(outcome["scores"]) == 2
                    assert statuses[1]["exit_code"] == 0
                    assert (directory / "replay").stat().st_size > 0
                else:
                    assert outcome["failed_policy_index"] == 0
                assert statuses[0]["exit_code"] != 0
                assert error in (directory / "player-0.log").read_text()
                assert not unexpected.exists()
            else:
                assert len(outcome["scores"]) == 2
                assert all(
                    status["state"] == "exited" and status["exit_code"] == 0
                    for status in statuses
                )
                assert (directory / "replay").stat().st_size > 0
                assert not unexpected.exists()
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/healthz", timeout=5
            ) as response:
                assert response.status == 200
            (directory / "verified.json").write_text(
                json.dumps(
                    {
                        "case": name,
                        "rejected": rejected,
                        "seconds": time.monotonic() - started,
                        "binary_sha256": hashlib.sha256(
                            binary.read_bytes()
                        ).hexdigest(),
                        "candidate_sha256": hashlib.sha256(candidate).hexdigest(),
                    },
                    indent=2,
                )
                + "\n"
            )
        finally:
            process.terminate()
            process.wait(timeout=5)
    print(name, "passed", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True)
    baseline = (ROOT / "players/classic.bas").read_bytes()
    for name, compression in [
        ("stored", zipfile.ZIP_STORED),
        ("deflated", zipfile.ZIP_DEFLATED),
    ]:
        episode(
            binary,
            evidence,
            name,
            package(
                {"policy.bas": baseline, "resource.bin": b"data" * 1024}, compression
            ),
            False,
        )
    episode(
        binary,
        evidence,
        "aggregate-limit",
        package(
            {
                "policy.bas": baseline,
                "first.bin": b"x" * (PACKAGE_LIMIT // 2),
                "second.bin": b"y" * (PACKAGE_LIMIT // 2),
            },
            zipfile.ZIP_DEFLATED,
        ),
        True,
    )
    forged = bytearray(
        package(
            {"policy.bas": baseline, "oversized.bin": b"x" * (PACKAGE_LIMIT + 1)},
            zipfile.ZIP_DEFLATED,
        )
    )
    local = forged.index(b"PK\x03\x04", 4)
    central = forged.index(b"PK\x01\x02", forged.index(b"PK\x01\x02") + 4)
    for offset in [local + 22, central + 24]:
        struct.pack_into("<I", forged, offset, 0)
    episode(binary, evidence, "false-size-limit", bytes(forged), True)

    for name, source, error, runtime_fault in [
        (
            "instruction-limit",
            b"while 1\na = 1\nwend\n",
            "BASIC instruction limit exceeded",
            True,
        ),
        (
            "source-limit",
            b"'" + b"x" * (256 * 1024) + b"\n",
            "BASIC source exceeds the configured byte limit",
            False,
        ),
        ("memory-limit", b"dim a(2000000)\n", "memory limit", False),
    ]:
        episode(binary, evidence, name, source, True, error, runtime_fault)
    episode(
        binary,
        evidence,
        "package-traversal",
        package(
            {"policy.bas": baseline, "../outside": b"forbidden"}, zipfile.ZIP_DEFLATED
        ),
        True,
        "Invalid package resource path",
    )
