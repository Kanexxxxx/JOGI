"""Ephemeral local-only bridge for reproducible panel QA; no platform listeners."""
import argparse
import asyncio
import json
import os
import tempfile
from pathlib import Path
from server import LiveBridgeServer


async def main(ready_file: Path, mode: str, platform: str, stop_file: Path | None = None) -> None:
    runtime = tempfile.TemporaryDirectory(prefix="jogi-panel-backend-")
    bridge = LiveBridgeServer(port=0, platform=platform, account="", runtime_mode=mode,
                              outbox_path=Path(runtime.name) / "gifts.sqlite3")
    await bridge.start()
    ready_file.write_text(json.dumps({"port": bridge.bound_port, "platform": platform, "pid": os.getpid()}), encoding="utf-8")
    try:
        while stop_file is None or not stop_file.exists():
            await asyncio.sleep(.2)
    finally:
        await bridge.stop()
        runtime.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ready-file", type=Path, required=True)
    parser.add_argument("--mode", choices=("production", "development"), default="development")
    parser.add_argument("--platform", choices=("tiktok", "kwai"), default="tiktok")
    parser.add_argument("--stop-file", type=Path)
    args = parser.parse_args()
    asyncio.run(main(args.ready_file, args.mode, args.platform, args.stop_file))
