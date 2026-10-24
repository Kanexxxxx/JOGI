"""Ephemeral local-only bridge for reproducible panel QA; no platform listeners."""
import argparse
import asyncio
import json
from pathlib import Path
from server import LiveBridgeServer


async def main(ready_file: Path) -> None:
    bridge = LiveBridgeServer(port=0, platform="tiktok", account="qa_local")
    await bridge.start()
    ready_file.write_text(json.dumps({"port": bridge.bound_port, "platform": "tiktok"}), encoding="utf-8")
    try:
        await asyncio.Event().wait()
    finally:
        await bridge.stop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ready-file", type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(main(args.ready_file))
