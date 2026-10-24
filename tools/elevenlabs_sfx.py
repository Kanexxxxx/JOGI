"""Quatro SFX curtos em cache; plano offline por padrão, sem repetição de POST.

Usa o mesmo cliente autenticado/seguro do TTS, sem copiar a chave para o jogo.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
if __package__ in (None, ""):
    sys.path.insert(0, str(ROOT))
from tools.elevenlabs_audio import AudioError, Client, atomic_json, load_key

MANIFEST = ROOT / "game/resources/audio/sfx_manifest.json"
AMBIENCE_MANIFEST = ROOT / "game/resources/audio/ambience_manifest.json"
CACHE = ROOT / "game/assets/audio/elevenlabs-sfx"
MAX_SECONDS = 8.0
MAX_CREDITS = 1000
KINDS = {"boost", "shield", "impact", "victory"}


def read_manifest(path: Path = MANIFEST) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or data.get("model_id") != "eleven_text_to_sound_v2":
        raise AudioError("Manifesto SFX incompatível.")
    clips = data.get("clips", [])
    ambience = data.get("pack_kind") == "arena_ambience"
    expected = {"crowd"} if ambience else KINDS
    if len(clips) != len(expected) or {c.get("kind") for c in clips} != expected:
        raise AudioError("O pacote contém exatamente quatro tipos de SFX.")
    for clip in clips:
        duration = clip.get("duration_seconds")
        upper = 10.0 if ambience else 3.0
        if not isinstance(duration, (int, float)) or isinstance(duration, bool) or not math.isfinite(duration) or not .5 <= duration <= upper:
            raise AudioError("Cada SFX deve durar entre 0,5 e 3 segundos.")
        prompt = clip.get("prompt", "")
        if not isinstance(prompt, str) or not 20 <= len(prompt) <= 500 or any(ord(c) < 32 for c in prompt):
            raise AudioError("Descrição de SFX inválida.")
    return data


def payload_for(data: dict, clip: dict) -> dict:
    return {"text": clip["prompt"], "duration_seconds": clip["duration_seconds"],
            "prompt_influence": .6, "loop": data.get("pack_kind") == "arena_ambience", "model_id": data["model_id"]}


def digest_for(payload: dict) -> str:
    signature = {"payload": payload, "output_format": "mp3_44100_128"}
    return hashlib.sha256(json.dumps(signature, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def plan(data: dict, cache: Path = CACHE) -> dict:
    clips = []
    for clip in data["clips"]:
        payload = payload_for(data, clip)
        digest = digest_for(payload)
        # Duas unidades publicadas oficialmente: usar a mais conservadora.
        cost = max(200, math.ceil(float(clip["duration_seconds"]) * 40))
        clips.append({"kind": clip["kind"], "duration_seconds": clip["duration_seconds"], "estimated_credit_ceiling": cost,
                      "cached": (cache / (digest + ".mp3")).is_file(), "cache_key": digest, "request": payload})
    total = sum(float(c["duration_seconds"]) for c in clips)
    ceiling = sum(int(c["estimated_credit_ceiling"]) for c in clips)
    ambience = data.get("pack_kind") == "arena_ambience"
    if len(clips) != (1 if ambience else 4) or total > (10.0 if ambience else MAX_SECONDS) or ceiling > MAX_CREDITS:
        raise AudioError("Pacote excedeu quatro arquivos, oito segundos ou orçamento conservador de 1.000 créditos.")
    return {"dry_run": True, "network_requests": 0, "credits_spent": 0, "total_seconds": total,
            "estimated_credit_ceiling": ceiling, "credit_limit": MAX_CREDITS,
            "pending_credit_ceiling": sum(c["estimated_credit_ceiling"] for c in clips if not c["cached"]), "clips": clips}


def generate(data: dict, client: Client, cache: Path = CACHE, manifest_path: Path = MANIFEST) -> dict:
    prepared = plan(data, cache)
    cache.mkdir(parents=True, exist_ok=True)
    lock = cache / ".generation.lock"
    try:
        handle = lock.open("x", encoding="ascii")
    except FileExistsError:
        raise AudioError("Geração SFX ativa ou interrompida; confira o processo e o histórico antes de remover o lock.") from None
    try:
        with handle:
            handle.write(str(os.getpid()))
        quota_before = client.subscription()
        if quota_before["remaining"] < prepared["pending_credit_ceiling"]:
            raise AudioError("Saldo incluído insuficiente para o teto conservador; não será usada cobrança excedente.")
        journal_path = cache / "generation_journal.json"
        journal = json.loads(journal_path.read_text(encoding="utf-8")) if journal_path.exists() else {"schema_version": 1, "entries": {}}
        generated, reused, reported_cost = 0, 0, 0
        for clip, entry in zip(data["clips"], prepared["clips"], strict=True):
            digest = entry["cache_key"]
            output = cache / (digest + ".mp3")
            if output.exists():
                recorded = journal["entries"].get(digest, {})
                if output.stat().st_size > 10_000_000 or recorded.get("state") != "complete" or recorded.get("audio_sha256") != hashlib.sha256(output.read_bytes()).hexdigest():
                    raise AudioError("SFX em cache não está íntegro ou confirmado; nenhum arquivo foi sobrescrito.")
                reused += 1
            else:
                if digest in journal["entries"]:
                    raise AudioError("SFX anterior incerto ou interrompido. Confira histórico/consumo antes de tentar outra geração.")
                journal["entries"][digest] = {"state": "pending", "kind": clip["kind"], "duration_seconds": clip["duration_seconds"], "created_unix": int(time.time())}
                atomic_json(journal_path, journal)
                try:
                    body, headers = client.request("/v1/sound-generation?output_format=mp3_44100_128", entry["request"])
                    if len(body) < 128 or not (body.startswith(b"ID3") or (body[0] == 0xFF and body[1] & 0xE0 == 0xE0)):
                        raise AudioError("A API SFX não retornou MP3 reconhecível; não haverá repetição automática.")
                    with output.open("xb") as audio_file:
                        audio_file.write(body)
                    cost_string = next((str(v) for k,v in headers.items() if k.lower() == "character-cost"), "")
                    cost = int(cost_string) if cost_string.isdigit() else None
                    record = journal["entries"][digest]
                    record.update({"state":"complete", "audio_sha256":hashlib.sha256(body).hexdigest(), "reported_credit_cost":cost})
                    atomic_json(journal_path, journal)
                    generated += 1
                    reported_cost += cost or 0
                    if reported_cost > MAX_CREDITS:
                        raise AudioError("O custo retornado pela API ultrapassou o limite; geração de novos SFX interrompida.")
                except (AudioError, OSError):
                    if journal["entries"][digest]["state"] != "complete":
                        journal["entries"][digest]["state"] = "uncertain"
                        atomic_json(journal_path, journal)
                    raise
            clip["clip_path"] = "res://assets/audio/elevenlabs-sfx/" + output.name
            clip["cache_key"] = digest
            atomic_json(manifest_path, data)
        quota_after = client.subscription()
        data["status"] = "generated_pending_listening_review"
        atomic_json(manifest_path, data)
        return {"generated":generated,"reused":reused,"reported_credit_cost":reported_cost,
                "account_usage_difference":max(0,quota_after["used"] - quota_before["used"]),
                "remaining":quota_after["remaining"],"duration_seconds":prepared["total_seconds"],"status":data["status"]}
    finally:
        lock.unlink(missing_ok=True)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["plan", "generate"])
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--pack", choices=["effects", "ambience"], default="effects")
    args = parser.parse_args(argv)
    try:
        manifest = AMBIENCE_MANIFEST if args.pack == "ambience" else MANIFEST
        data = read_manifest(manifest)
        result = generate(data, Client(load_key()), manifest_path=manifest) if args.command == "generate" and args.execute else plan(data)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (AudioError, OSError, ValueError, KeyError, TypeError) as exc:
        message = str(exc) if isinstance(exc, AudioError) else "Falha na configuração/cache SFX; verifique os arquivos locais sem enviar segredos."
        print(json.dumps({"error":message},ensure_ascii=False),file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
