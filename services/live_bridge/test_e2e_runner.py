"""Test runner para validacao ponta a ponta (E2E): LiveBridge + Godot 4.7.2."""

import asyncio
import json
import logging
import os
import subprocess
import sys
from pathlib import Path

from protocol import build_admin_command_envelope, build_follow_envelope, build_gift_envelope, build_vote_envelope
from server import LiveBridgeServer
from simulator import MockLiveEventSimulator, SimulatorConfig

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("e2e_runner")

PROJECT_DIR = Path(__file__).resolve().parent.parent.parent
GAME_DIR = PROJECT_DIR / "game"
GDA_EXE = Path(r"C:\Users\Kanex\.local\bin\gda.exe")
GODOT_EXE = Path(r"C:\Users\Kanex\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")


async def run_e2e_test() -> int:
    logger.info("Iniciando LiveBridgeServer em porta local efêmera isolada...")
    srv = LiveBridgeServer(host="127.0.0.1", port=0, platform="tiktok", rate_limit_per_sec=100.0)
    await srv.start()
    godot_url = f"ws://127.0.0.1:{srv.bound_port}/ws/godot"
    child_env = os.environ.copy()
    child_env.update({"LIVE_BRIDGE_WS_URL": godot_url, "LIVE_PLATFORM": "tiktok"})
    proc = None

    try:
        logger.info("Executando test_live_bridge_e2e.gd via GDA CLI...")
        proc = await asyncio.create_subprocess_exec(
            str(GDA_EXE),
            "script",
            "run",
            "res://tests/test_live_bridge_e2e.gd",
            "--strict",
            "--project",
            str(GAME_DIR),
            "--godot",
            str(GODOT_EXE),
            "--json",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=child_env,
        )

        # Aguarda conexao do Godot no WebSocket
        connected = False
        for _ in range(60):
            if len(srv.godot_clients) > 0:
                connected = True
                break
            await asyncio.sleep(0.1)

        if not connected:
            logger.error("Timeout aguardando Godot conectar em %s", godot_url)
            proc.kill()
            return 1

        logger.info("Godot conectado! Enviando metas pelo contrato canônico do backend...")
        srv.enqueue_envelope(build_admin_command_envelope(command='set_live_goals', live_goals={
            'likes': {'goal_kind': 'likes', 'goal_target': 1500, 'goal_label': 'Curtidas E2E'},
            'gifts': {'goal_kind': 'gift_specific', 'goal_target': 300, 'goal_label': 'Rosas E2E', 'goal_gift_id': 'rose_e2e'},
            'follows': {'goal_kind': 'follows', 'goal_target': 10000, 'goal_label': 'Seguidores E2E',
                        'follower_baseline': 8400, 'baseline_updated_at': '2026-10-24T15:00:00Z'},
        }, event_id='evt_e2e_canonical_goals'))
        srv.enqueue_envelope(build_follow_envelope(user_id='e2e_follower', display_name='Teste local',
            event_id='evt_e2e_follow_probe', source='simulator'))
        logger.info("Verificando ACK de presente simulado antes do restante dos eventos...")
        srv.enqueue_envelope(build_gift_envelope(user_id="e2e_probe", display_name="Teste local",
            candidate_slot=1, event_id="evt_e2e_ack_probe", source="simulator"))
        for _ in range(60):
            if srv.metrics["gift_acks_total"] >= 1:
                break
            await asyncio.sleep(0.05)
        if srv.metrics["gift_acks_total"] < 1:
            logger.error("Godot não confirmou o presente simulado via event_ack.")
            return 1
        sim = MockLiveEventSimulator(
            SimulatorConfig(
                seed=77,
                mode="normal",
                count=6,
                candidate_slot=1,
                ingest_url=f"ws://127.0.0.1:{srv.bound_port}/ws/ingest",
            )
        )
        sim_stats = await sim.stream_to_server()
        logger.info("Simulador terminou envio: %s", sim_stats)

        # Aguarda conclusao do teste no Godot
        stdout_b, stderr_b = await asyncio.wait_for(proc.communicate(), timeout=20.0)
        stdout_str = stdout_b.decode("utf-8", errors="replace").strip()
        stderr_str = stderr_b.decode("utf-8", errors="replace").strip()

        logger.info("GDA STDOUT: %s", stdout_str)
        if stderr_str:
            logger.warning("GDA STDERR: %s", stderr_str)

        if proc.returncode != 0:
            logger.error("Godot E2E falhou com exit code %d", proc.returncode)
            return proc.returncode

        evidence = {"result": "passed", "godot_exit_code": proc.returncode,
                    "gift_acks_total": srv.metrics["gift_acks_total"],
                    "pending_gifts_at_end": srv.outbox.pending_count(),
                    "network_scope": "isolated loopback; simulator only", "gda_result": json.loads(stdout_str)}
        (Path(__file__).parent / "e2e-reliability-validation.json").write_text(
            json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")

        logger.info("=== TEST_LIVE_BRIDGE_E2E PASSOU COM SUCESSO! ===")
        return 0

    except Exception as exc:
        logger.exception("Erro durante execucao do teste E2E: %s", exc)
        return 1
    finally:
        if proc is not None and proc.returncode is None:
            proc.kill()
            await proc.communicate()
        await srv.stop()
        logger.info("LiveBridgeServer encerrado.")


def main() -> None:
    code = asyncio.run(run_e2e_test())
    sys.exit(code)


if __name__ == "__main__":
    main()
