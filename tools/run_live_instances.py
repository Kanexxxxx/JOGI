"""Launch isolated local bridges and visible Godot windows; never starts platform live."""

from __future__ import annotations

import argparse
import hashlib
from contextlib import closing
import json
import os
from pathlib import Path
import secrets
import shutil
import sqlite3
import socket
import subprocess
import sys
import time
from urllib.error import URLError
from urllib.request import urlopen
from live_supervisor import LiveSupervisor, ManagedChild, stay_awake


ROOT = Path(__file__).resolve().parents[1]
BRIDGE_DIR = ROOT / "services" / "live_bridge"
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))
from operational_shutdown import normalize_end_at
from server import normalize_secret_token
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
    runtime_mode: str | None = None,
) -> dict:
    named_executable = ROOT / ".tools" / "capture" / ("JOGI-TikTok.exe" if platform == "tiktok" else "JOGI-Kwai.exe")
    if godot == DEFAULT_GODOT and named_executable.is_file():
        godot = named_executable
    port = PORTS[platform]
    mode = runtime_mode or ("development" if offline else os.environ.get("JOGI_MODE", "production"))
    if mode not in ("production", "development"):
        raise ValueError("JOGI_MODE deve ser production ou development.")
    end_at = os.environ.get("JOGI_END_AT", "2026-10-26T07:00:00-03:00")
    end_at, _ = normalize_end_at(end_at)
    platform_dir = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / ".local"))) / "JOGI" / "live_bridge" / platform
    account = PUBLIC_ACCOUNTS[platform].strip().lstrip("@").lower()
    account_key = hashlib.sha256(account.encode("utf-8")).hexdigest()[:16]
    state_dir = platform_dir / mode / "accounts" / account_key
    return {
        "platform": platform,
        "account": PUBLIC_ACCOUNTS[platform],
        "port": port,
        "runtime_mode": mode,
        "end_at": end_at,
        "python": str(BRIDGE_DIR / ".venv" / "Scripts" / "python.exe"),
        "bridge_script": str(BRIDGE_DIR / "server.py"),
        "state_dir": str(state_dir),
        "legacy_state_dir": str(platform_dir),
        "legacy_mode_state_dir": str(platform_dir / mode),
        "godot": str(godot),
        "project": str(ROOT / "game"),
        "scene": scene,
        "godot_environment": {
            "LIVE_PLATFORM": platform,
            "LIVE_ACCOUNT": account,
            "LIVE_BRIDGE_WS_URL": f"ws://127.0.0.1:{port}/ws/godot",
            "JOGI_MODE": mode,
            "JOGI_END_AT": end_at,
        },
        "panel": f"http://127.0.0.1:{port}/admin",
        "starts_platform_live": False,
        "listen_live": not offline,
        "enable_kwai_collector": platform == "kwai" and not offline,
        "kwai_webhook_port": KWAI_WEBHOOK_PORT,
        "node": shutil.which("node") or r"C:\Program Files\nodejs\node.exe",
        "kwai_collector_script": str(ROOT / "tools" / "kwai_live_collector.cjs"),
    }


def legacy_pending_gifts(plan: dict) -> int:
    """Never silently strand previously accepted gifts when introducing mode isolation."""
    if plan.get("runtime_mode") != "production":
        return 0
    pending = 0
    directories = {Path(plan["legacy_state_dir"]), Path(plan.get("legacy_mode_state_dir", Path(plan["legacy_state_dir"]) / plan["runtime_mode"]))}
    for directory in directories:
        path = directory / "gifts.sqlite3"
        if not path.exists():
            continue
        try:
            with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=1)) as db:
                pending += int(db.execute("SELECT COUNT(*) FROM gifts WHERE completed_ms IS NULL").fetchone()[0])
        except sqlite3.Error as error:
            raise RuntimeError("Outbox anterior requer verificação antes de abrir produção; nenhum dado foi alterado.") from error
    return pending


class LauncherLock:
    """OS-owned lock survives for launcher lifetime and releases after crashes."""
    def __init__(self, directory: Path):
        directory.mkdir(parents=True, exist_ok=True)
        self.handle = (directory / "launcher.lock").open("a+b")
        self.handle.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                if self.handle.read(1) == b"":
                    self.handle.write(b"0")
                    self.handle.flush()
                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            self.handle.close()
            raise RuntimeError("Outra inicialização já controla esta sessão. Credenciais preservadas.") from error

    def close(self) -> None:
        self.handle.close()


def port_available(port: int) -> bool:
    """Probe only the loopback bind; never stop or send data to an existing service."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False


def prepare_operator_credentials(plan: dict, environment: dict[str, str], *, port_free: bool) -> tuple[str, Path | None]:
    """Keep manual credentials, or create an owner-only local production bootstrap file."""
    configured = normalize_secret_token(environment.get("LIVE_BRIDGE_LOCAL_TOKEN", ""))
    if configured or plan["runtime_mode"] != "production" or not port_free:
        return configured, None
    directory = Path(plan["state_dir"]).resolve()
    target = directory / "operator-token.key"
    if directory.is_relative_to(ROOT.resolve()) or target.resolve().is_relative_to(ROOT.resolve()):
        raise RuntimeError("A credencial administrativa deve ficar fora da pasta versionada do projeto.")
    directory.mkdir(parents=True, exist_ok=True)
    if target.exists():
        existing = normalize_secret_token(target.read_text(encoding="utf-8"))
        if not existing:
            raise RuntimeError("Credencial local existente inválida; preservada para revisão, sem substituição automática.")
        return existing, None
    token = secrets.token_urlsafe(32)
    temporary = directory / ("operator-token." + secrets.token_hex(8) + ".tmp")
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(token + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target)
    except OSError as error:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise RuntimeError("Não foi possível preparar a credencial administrativa local.") from error
    return token, target


def cleanup_operator_credentials(path: Path, token: str) -> None:
    """Keep the account-local capability through clean shutdown and cold boot."""
    # Ephemeral producer/engine credentials still rotate on each launch.
    # The admin token must remain valid in the operator's existing browser.
    return


def launch(plans: list[dict], *, bridge_only: bool = False) -> int:
    children: list[ManagedChild] = []
    handles = []
    state_dirs = {}
    supervisor = None
    generated_operator_credentials: list[tuple[Path, str]] = []
    launcher_locks: list[LauncherLock] = []
    try:
        for plan in plans:
            launcher_locks.append(LauncherLock(Path(plan["state_dir"])))
            existing = health(plan["port"])
            if existing is None and not port_available(plan["port"]):
                existing = {"status": "port_already_in_use"}
            if existing is None and legacy_pending_gifts(plan):
                raise RuntimeError(f"{plan['platform']}: há presentes pendentes na sessão anterior. Recupere-os antes de abrir produção.")
            state_dir = Path(plan["state_dir"])
            # A rejected second launcher must not overwrite the owner's status.
            if existing is None:
                state_dirs[plan["platform"]] = state_dir
            state_dir.mkdir(parents=True, exist_ok=True)
            log_file = (state_dir / f"bridge-{time.strftime('%Y%m%d-%H%M%S')}.log").open("ab")
            handles.append(log_file)

            # Distinct ephemeral capabilities: a collector cannot impersonate the engine.
            instance_producer_token = secrets.token_urlsafe(32)
            instance_engine_token = secrets.token_urlsafe(32)
            shared_env = os.environ.copy()
            operator_token, operator_file = prepare_operator_credentials(plan, shared_env, port_free=existing is None)
            if operator_token:
                shared_env["LIVE_BRIDGE_LOCAL_TOKEN"] = operator_token
            else:
                shared_env.pop("LIVE_BRIDGE_LOCAL_TOKEN", None)
            if operator_file is not None:
                generated_operator_credentials.append((operator_file, operator_token))
                print(f"{plan['platform']}: chave administrativa local em {operator_file}. Copie somente no painel local.", flush=True)
            shared_env["LIVE_BRIDGE_PRODUCER_TOKEN"] = instance_producer_token
            shared_env["LIVE_BRIDGE_ENGINE_TOKEN"] = instance_engine_token
            shared_env["JOGI_MODE"] = plan["runtime_mode"]
            shared_env["JOGI_END_AT"] = plan["end_at"]

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
                game_env.pop("LIVE_BRIDGE_LOCAL_TOKEN", None)
                game_env.pop("LIVE_BRIDGE_PRODUCER_TOKEN", None)
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
                        and not (health(port) or {}).get("operational_shutdown", {}).get("ended", False)
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
                collector_env = dict(shared_env)
                collector_env.pop("LIVE_BRIDGE_LOCAL_TOKEN", None)
                collector_env.pop("LIVE_BRIDGE_ENGINE_TOKEN", None)
                collector = ManagedChild(
                    plan["platform"],
                    "collector",
                    lambda command=collector_args, log=collector_log, creation_flags=flags, environment=collector_env: subprocess.Popen(
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
        for path, token in generated_operator_credentials:
            cleanup_operator_credentials(path, token)
        for launcher_lock in reversed(launcher_locks):
            launcher_lock.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("tiktok", "kwai"), default="tiktok")
    parser.add_argument("--both", action="store_true", help="Abrir as duas sessões independentes no mesmo PC.")
    parser.add_argument("--bridge-only", action="store_true", help="Subir pontes locais, sem renderizar jogos.")
    parser.add_argument("--offline", action="store_true", help="Desativar escuta pública TikTok e operar apenas simulador local.")
    parser.add_argument("--mode", choices=("production", "development"), default=None,
                        help="Padrão produção; --offline seleciona desenvolvimento salvo modo explícito.")
    parser.add_argument("--check", action="store_true", help="Validar plano/caminhos sem iniciar processos.")
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    parser.add_argument("--scene", default="res://scenes/main/stadium_race.tscn")
    args = parser.parse_args()
    platforms = ("tiktok", "kwai") if args.both else (args.platform,)
    plans = [build_plan(platform, godot=args.godot, scene=args.scene, offline=args.offline,
                        runtime_mode=args.mode) for platform in platforms]
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
