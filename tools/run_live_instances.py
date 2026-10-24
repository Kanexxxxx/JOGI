"""Launch isolated local bridges and visible Godot windows; never starts platform live."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import time
from urllib.error import URLError
from urllib.request import urlopen
from live_supervisor import LiveSupervisor, ManagedChild, stay_awake


ROOT = Path(__file__).resolve().parents[1]
BRIDGE_DIR = ROOT / "services" / "live_bridge"
PUBLIC_ACCOUNTS = {"tiktok": "nostalgiia.br", "kwai": "mentalista.."}
PORTS = {"tiktok": 8765, "kwai": 8766}
KWAI_WEBHOOK_PORT = 8786
DEFAULT_GODOT = Path(r"C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe")


def health(port: int) -> dict | None:
    try:
        with urlopen(f"http://127.0.0.1:{port}/health", timeout=0.5) as response:
            return json.load(response)
    except (URLError, TimeoutError, ValueError, OSError):
        return None


def build_plan(
    platform: str,
    *,
    godot: Path = DEFAULT_GODOT,
    scene: str = "res://scenes/main/stadium_race.tscn",
    offline: bool = False,
) -> dict:
    port = PORTS[platform]
    state_dir = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / ".local"))) / "JOGI" / "live_bridge" / platform
    return {
        "platform": platform,
        "account": PUBLIC_ACCOUNTS[platform],
        "port": port,
        "python": str(BRIDGE_DIR / ".venv" / "Scripts" / "python.exe"),
        "bridge_script": str(BRIDGE_DIR / "server.py"),
        "state_dir": str(state_dir),
        "godot": str(godot),
        "project": str(ROOT / "game"),
        "scene": scene,
        "godot_environment": {
            "LIVE_PLATFORM": platform,
            "LIVE_BRIDGE_WS_URL": f"ws://127.0.0.1:{port}/ws/godot",
        },
        "panel": f"http://127.0.0.1:{port}/admin",
        "starts_platform_live": False,
        "listen_live": not offline,
        "enable_kwai_collector": platform == "kwai" and not offline,
        "kwai_webhook_port": KWAI_WEBHOOK_PORT,
        "node": shutil.which("node") or r"C:\Program Files\nodejs\node.exe",
        "kwai_collector_script": str(ROOT / "tools" / "kwai_live_collector.cjs"),
    }


def launch(plans: list[dict], *, bridge_only: bool = False) -> int:
    children: list[ManagedChild] = []
    handles = []
    state_dirs = {}
    supervisor = None
    try:
        for plan in plans:
            existing = health(plan["port"])
            state_dir = Path(plan["state_dir"])
            # A rejected second launcher must not overwrite the owner's status.
            if existing is None:
                state_dirs[plan["platform"]] = state_dir
            state_dir.mkdir(parents=True, exist_ok=True)
            log_file = (state_dir / f"bridge-{time.strftime('%Y%m%d-%H%M%S')}.log").open("ab")
            handles.append(log_file)

            # Ephemeral per-instance producer token binds bridge, Godot, and Kwai collector
            # without storing secrets in git or HTML. Operator LIVE_BRIDGE_LOCAL_TOKEN is preserved if set.
            instance_producer_token = secrets.token_urlsafe(32)
            shared_env = os.environ.copy()
            shared_env["LIVE_BRIDGE_PRODUCER_TOKEN"] = instance_producer_token

            server_args = [
                plan["python"],
                "-u",
                plan["bridge_script"],
                "--platform",
                plan["platform"],
                "--account",
                plan["account"],
                "--port",
                str(plan["port"]),
                "--state-dir",
                plan["state_dir"],
            ]
            if plan["platform"] == "kwai":
                server_args.extend(["--kwai-webhook-port", str(plan.get("kwai_webhook_port", KWAI_WEBHOOK_PORT))])
            if plan["listen_live"]:
                server_args.append("--listen-live")
            flags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
            bridge = ManagedChild(
                plan["platform"],
                "bridge",
                lambda command=server_args, log=log_file, creation_flags=flags, environment=shared_env: subprocess.Popen(
                    command, cwd=BRIDGE_DIR, env=environment, stdout=log, stderr=log, creationflags=creation_flags
                ),
            )
            if existing is not None:
                bridge.requires_attention = True
                bridge.last_exit = "port_already_in_use"
                print(f"{plan['platform']}: porta ocupada; precisa de atenção. Processo existente preservado.", flush=True)
            children.append(bridge)
            if not bridge_only:
                game_env = dict(shared_env)
                game_env.update(plan["godot_environment"])
                # The game is intentionally visible for OBS/TikTok Studio capture.
                game = ManagedChild(
                    plan["platform"],
                    "game",
                    lambda args=[plan["godot"], "--path", plan["project"], plan["scene"]], environment=game_env: subprocess.Popen(
                        args, cwd=ROOT, env=environment
                    ),
                    ready=lambda dependency=bridge, port=plan["port"], platform=plan["platform"]: (
                        dependency.process is not None and (health(port) or {}).get("platform") == platform
                    ),
                )
                if existing is not None:
                    game.requires_attention = True
                    game.last_exit = "bridge_port_already_in_use"
                children.append(game)
            if (
                plan.get("enable_kwai_collector")
                and Path(plan.get("node", "")).is_file()
                and Path(plan.get("kwai_collector_script", "")).is_file()
            ):
                collector_log = (state_dir / f"kwai-collector-{time.strftime('%Y%m%d-%H%M%S')}.log").open("ab")
                handles.append(collector_log)
                webhook_port = int(plan.get("kwai_webhook_port", KWAI_WEBHOOK_PORT))
                collector_args = [
                    plan["node"],
                    plan["kwai_collector_script"],
                    "--account",
                    plan["account"],
                    "--bridge",
                    f"http://127.0.0.1:{plan['port']}",
                    "--webhook",
                    f"http://127.0.0.1:{webhook_port}/webhook/kwai",
                ]
                collector = ManagedChild(
                    plan["platform"],
                    "collector",
                    lambda command=collector_args, log=collector_log, creation_flags=flags, environment=shared_env: subprocess.Popen(
                        command, cwd=ROOT, env=environment, stdout=log, stderr=log, creationflags=creation_flags
                    ),
                    ready=lambda dependency=bridge, port=plan["port"]: (
                        dependency.process is not None
                        and (health(port) or {}).get("platform") == "kwai"
                        and (health(port) or {}).get("platform_events_status")
                        not in (None, "not_started", "kwai_requires_collector")
                    ),
                )
                if existing is not None:
                    collector.requires_attention = True
                    collector.last_exit = "bridge_port_already_in_use"
                children.append(collector)
            print(f"{plan['platform'].upper()}: painel {plan['panel']} | outbox {state_dir}", flush=True)
        supervisor = LiveSupervisor(children, state_dirs)
        print("Supervisão local ativa. Reinícios são isolados; Ctrl+C encerra os processos deste launcher.", flush=True)
        with stay_awake():
            while True:
                supervisor.step(time.monotonic())
                time.sleep(0.5)
    except KeyboardInterrupt:
        return 0
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if supervisor is not None:
            supervisor.shutdown()
        for handle in handles:
            handle.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("tiktok", "kwai"), default="tiktok")
    parser.add_argument("--both", action="store_true", help="Abrir as duas sessões independentes no mesmo PC.")
    parser.add_argument("--bridge-only", action="store_true", help="Subir pontes locais, sem renderizar jogos.")
    parser.add_argument("--offline", action="store_true", help="Desativar escuta pública TikTok e operar apenas simulador local.")
    parser.add_argument("--check", action="store_true", help="Validar plano/caminhos sem iniciar processos.")
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    parser.add_argument("--scene", default="res://scenes/main/stadium_race.tscn")
    args = parser.parse_args()
    platforms = ("tiktok", "kwai") if args.both else (args.platform,)
    plans = [build_plan(platform, godot=args.godot, scene=args.scene, offline=args.offline) for platform in platforms]
    for plan in plans:
        for field in ("python", "bridge_script") + (() if args.bridge_only else ("godot",)):
            if not Path(plan[field]).is_file():
                parser.error(f"Executável/arquivo ausente: {plan[field]}")
        if not args.scene.startswith("res://") or ".." in Path(args.scene.removeprefix("res://")).parts:
            parser.error("--scene deve ser um caminho res:// dentro de game.")
        if not (ROOT / "game" / args.scene.removeprefix("res://")).is_file():
            parser.error("Cena informada não existe em game.")
    if args.check:
        print(json.dumps({"valid": True, "processes_started": False, "plans": plans}, ensure_ascii=False, indent=2))
        return 0
    return launch(plans, bridge_only=args.bridge_only)


if __name__ == "__main__":
    raise SystemExit(main())
