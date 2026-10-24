"""Diagnostico somente leitura; nao inicia processos nem altera sessoes."""
from __future__ import annotations
import json
from pathlib import Path
import socket
import sys
from urllib.request import urlopen
from run_live_instances import build_plan

def main() -> int:
    print("JOGI — diagnostico local (nenhuma LIVE iniciada)")
    print("Python real:", sys.executable)
    for platform in ("tiktok", "kwai"):
        plan = build_plan(platform, runtime_mode="production")
        print("\n", platform.upper(), "@" + plan["account"], "| encerramento:", plan["end_at"])
        for key in ("python", "godot", "node", "bridge_script", "kwai_collector_script"):
            path = Path(plan[key])
            print(key + ":", "OK" if path.is_file() else "AUSENTE", path)
        print("Painel:", plan["panel"])
        print("Estado privado:", plan["state_dir"])
        port = plan["port"]
        with socket.socket() as probe:
            probe.settimeout(0.5)
            occupied = probe.connect_ex(("127.0.0.1", port)) == 0
        print("Porta", port, "OCUPADA — nao abra outra sessao antes de identificar a atual" if occupied else "livre")
        if occupied:
            try:
                with urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as response:
                    health = json.load(response)
                print("Estado observado:", json.dumps({key: health[key] for key in ("platform", "account", "runtime_mode", "platform_events_status", "platform_events_connected", "pending_gifts") if key in health}, ensure_ascii=False))
            except Exception as error:
                print("Health sem resposta valida:", type(error).__name__, "— processo preservado")
    with socket.socket() as probe:
        probe.settimeout(0.5)
        print("\nWebhook Kwai 8786:", "ocupada" if probe.connect_ex(("127.0.0.1", 8786)) == 0 else "livre; receptor nao confirmado")
    print("\nPorta aberta nao comprova Godot ou sala conectada. Consulte docs/GUIA_COMPLETO_OPERACAO_LIVES.md.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
