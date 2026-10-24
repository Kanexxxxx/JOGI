"""ElevenLabs local: segredo fora do Godot; TTS somente por comando explícito.

Só a biblioteca padrão. `plan` nunca faz rede. `status` e `voices` são GET.
Um POST interrompido fica registrado e não é repetido automaticamente.
"""
from __future__ import annotations

import argparse
import copy
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "game/resources/audio/voice_manifest.json"
CACHE = ROOT / "game/assets/audio/elevenlabs"
ENV_FILE = ROOT / ".env.local"
MAX_CHARACTERS = 2000
API_ORIGIN = "https://api.elevenlabs.io"
VOICE_ID = re.compile(r"[A-Za-z0-9_-]{6,100}\Z")
POLITICAL_NAMES = re.compile(r"lula|bolsonaro|trump|biden|obama|putin|zelensky|luiz in[aá]cio|fl[aá]vio", re.I)
SAFE_CATEGORIES = {"premade", "generated"}
SETTINGS = {"stability": 0.45, "similarity_boost": 0.75, "style": 0.2, "use_speaker_boost": True}


class AudioError(RuntimeError):
    """Mensagem pública deliberadamente sem headers/corpo de erro remoto."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Não encaminhar xi-api-key a outro destino.


class Client:
    def __init__(self, key: str, opener=None, timeout: float = 45.0):
        if not key or not re.fullmatch(r"[A-Za-z0-9_-]{16,256}", key):
            raise AudioError("Chave ausente ou inválida. Abra CONFIGURAR_VOZ.cmd localmente.")
        self._key = key
        self._opener = opener or urllib.request.build_opener(NoRedirect())
        self.timeout = timeout

    def request(self, path: str, payload: dict | None = None) -> tuple[bytes, dict]:
        if not path.startswith("/") or path.startswith("//") or "\r" in path or "\n" in path:
            raise AudioError("Caminho de API inválido.")
        data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(API_ORIGIN + path, data=data, headers={
            "xi-api-key": self._key, "Content-Type": "application/json", "Accept": "application/json" if data is None else "audio/mpeg",
        }, method="GET" if data is None else "POST")
        try:
            with self._opener.open(request, timeout=self.timeout) as response:
                # Limites também se aplicam a respostas sem Content-Length.
                limit = 10_000_000 if data is not None else 2_000_000
                body = response.read(limit + 1)
                if len(body) > limit:
                    raise AudioError("Resposta excedeu o limite local; não houve repetição.")
                return body, dict(response.headers)
        except urllib.error.HTTPError as exc:
            raise AudioError(f"ElevenLabs respondeu HTTP {exc.code}; nenhuma tentativa automática.") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise AudioError("Rede interrompida; nenhuma tentativa automática. Consulte o histórico antes de gerar novamente.") from None

    def get_json(self, path: str):
        body, _ = self.request(path)
        try:
            return json.loads(body)
        except (ValueError, UnicodeError):
            raise AudioError("A API não retornou JSON válido.") from None

    def subscription(self) -> dict:
        source = self.get_json("/v1/user/subscription")
        used, limit = int(source["character_count"]), int(source["character_limit"])
        # Não retornar faturas, emails, dados do titular ou a chave.
        return {"key_configured": True, "tier": str(source.get("tier", "")), "status": str(source.get("status", "")),
                "used": used, "limit": limit, "remaining": max(0, limit - used)}

    def voices(self) -> list[dict]:
        voices, token = [], None
        for _ in range(10):
            query = {"page_size": 100, "include_total_count": "false"}
            if token:
                query["next_page_token"] = token
            page = self.get_json("/v2/voices?" + urllib.parse.urlencode(query))
            for voice in page.get("voices", []):
                labels = voice.get("labels") or {}
                voices.append({"voice_id": str(voice.get("voice_id", "")), "name": str(voice.get("name", "")),
                               "category": str(voice.get("category", "")), "language": str(labels.get("language", "")),
                               "description": str(voice.get("description") or "")[:500]})
            token = page.get("next_page_token")
            if not page.get("has_more"):
                return voices
            if not token:
                raise AudioError("Paginação de vozes incompleta; não é seguro selecionar uma voz ausente.")
        raise AudioError("Catálogo excedeu o limite de dez páginas; refine a seleção no site.")


def read_env(path: Path = ENV_FILE) -> dict[str, str]:
    if not path.exists():
        return {}
    values = {}
    # Não executa PowerShell, expansão de variáveis nem substituição de comandos.
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        match = re.fullmatch(r"\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*", raw)
        if match:
            value = match[2]
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            values[match[1]] = value
    return values


def load_key(path: Path = ENV_FILE) -> str:
    return os.environ.get("ELEVENLABS_API_KEY", "") or read_env(path).get("ELEVENLABS_API_KEY", "")


def configure(path: Path = ENV_FILE) -> dict:
    if not sys.stdin.isatty():
        raise AudioError("Configure em um terminal local interativo; não cole a chave no chat.")
    key = getpass.getpass("Cole a chave ElevenLabs (entrada oculta) e pressione Enter: ").strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{16,256}", key):
        raise AudioError("Formato inválido. Nenhum arquivo foi alterado.")
    previous = path.read_text(encoding="utf-8-sig") if path.exists() else ""
    lines = [line for line in previous.splitlines() if not re.match(r"\s*ELEVENLABS_API_KEY\s*=", line)]
    lines.append("ELEVENLABS_API_KEY=" + key)
    # Arquivo temporário na mesma pasta; nunca imprimir conteúdo ou usar argumento de processo.
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    os.chmod(temporary, 0o600)
    temporary.replace(path)
    return {"saved": True, "file": ".env.local", "credits_spent": 0,
            "next": "py tools/elevenlabs_audio.py status"}


def atomic_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    temporary.replace(path)


def read_manifest(path: Path = MANIFEST) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("clips"), list):
        raise AudioError("Manifesto incompatível.")
    ids = set()
    for clip in data["clips"]:
        if not re.fullmatch(r"[a-z0-9_]{1,64}", clip.get("id", "")) or clip["id"] in ids:
            raise AudioError("IDs de clipe inválidos ou duplicados.")
        ids.add(clip["id"])
        if clip.get("team") not in (0, 1, 2) or clip.get("voice_role") not in ("narrator", "team1", "team2"):
            raise AudioError("Equipe ou perfil inválido.")
        text = clip.get("text", "")
        if not isinstance(text, str) or not 1 <= len(text) <= 160 or any(ord(c) < 32 for c in text):
            raise AudioError("Texto vazio, longo ou com caracteres de controle.")
    return data


def cache_key(model: str, voice: str, text: str, settings: dict) -> str:
    fields = {"model": model, "voice": voice, "text": text, "settings": settings, "format": "mp3_44100_128", "seed": 13022}
    return hashlib.sha256(json.dumps(fields, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def plan(data: dict, cache: Path = CACHE) -> dict:
    model = data.get("model_id", "eleven_multilingual_v2")
    total = sum(len(c["text"]) for c in data["clips"])
    if total > MAX_CHARACTERS:
        raise AudioError(f"Pacote excede o limite inicial de {MAX_CHARACTERS} caracteres.")
    entries = []
    for clip in data["clips"]:
        profile = data["voices"][clip["voice_role"]]
        voice = profile.get("voice_id", "")
        digest = cache_key(model, voice, clip["text"], data.get("voice_settings", SETTINGS))
        entries.append({"id": clip["id"], "kind": clip["kind"], "team": clip["team"], "voice_role": clip["voice_role"],
                        "voice_configured": bool(VOICE_ID.fullmatch(voice) and profile.get("original_synthetic") is True),
                        "characters": len(clip["text"]), "text": clip["text"], "cache_key": digest,
                        "cached": (cache / (digest + ".mp3")).is_file()})
    return {"dry_run": True, "network_requests": 0, "credits_spent": 0, "model_id": model,
            "clip_count": len(entries), "total_characters": total, "initial_limit": MAX_CHARACTERS,
            "pending_characters": sum(e["characters"] for e in entries if not e["cached"]),
            "ready_to_generate": all(e["voice_configured"] for e in entries), "clips": entries}


def validate_profiles(data: dict, available: list[dict]) -> None:
    by_id = {v["voice_id"]: v for v in available}
    if data["voices"].get("team1", {}).get("voice_id") == data["voices"].get("team2", {}).get("voice_id"):
        raise AudioError("Escolha vozes distintas para as duas equipes.")
    for role in {c["voice_role"] for c in data["clips"]}:
        profile = data["voices"][role]
        voice_id = profile.get("voice_id", "")
        if not VOICE_ID.fullmatch(voice_id) or profile.get("original_synthetic") is not True:
            raise AudioError(f"Perfil {role} ainda não tem uma voz original selecionada.")
        voice = by_id.get(voice_id)
        if voice is None or voice["category"] not in SAFE_CATEGORIES:
            raise AudioError(f"Perfil {role}: selecione uma voz premade/generated disponível; clonagem não é usada neste projeto.")
        if POLITICAL_NAMES.search(voice["name"] + " " + voice["description"]):
            raise AudioError(f"Perfil {role}: selecione uma voz original, sem imitação de figura política.")


def generate(data: dict, client: Client, cache: Path = CACHE, manifest_path: Path = MANIFEST) -> dict:
    # Exclusão entre processos: dois terminais não podem cobrar o mesmo pacote.
    cache.mkdir(parents=True, exist_ok=True)
    lock = cache / ".generation.lock"
    try:
        handle = lock.open("x", encoding="ascii")
    except FileExistsError:
        raise AudioError("Outra geração está ativa ou foi interrompida. Confira o processo e o histórico antes de remover .generation.lock.") from None
    try:
        with handle:
            handle.write(str(os.getpid()))
        return _generate_locked(data, client, cache, manifest_path)
    finally:
        lock.unlink(missing_ok=True)


def _generate_locked(data: dict, client: Client, cache: Path, manifest_path: Path) -> dict:
    prepared = plan(data, cache)
    if not prepared["ready_to_generate"]:
        raise AudioError("Selecione os três perfis de vozes originais antes da geração.")
    validate_profiles(data, client.voices())
    models = client.get_json("/v1/models")
    if not any(m.get("model_id") == prepared["model_id"] and m.get("can_do_text_to_speech") for m in models):
        raise AudioError("Modelo de voz não disponível nesta conta.")
    # Conservador para o modelo fixo inicial: sem overage automático ou troca silenciosa de modelo.
    if prepared["model_id"] != "eleven_multilingual_v2":
        raise AudioError("O pacote inicial está orçado apenas para eleven_multilingual_v2.")
    quota = client.subscription()
    if quota["remaining"] < prepared["pending_characters"]:
        raise AudioError("Créditos incluídos insuficientes; cobrança excedente não será acionada.")
    cache.mkdir(parents=True, exist_ok=True)
    journal_path = cache / "generation_journal.json"
    journal = json.loads(journal_path.read_text(encoding="utf-8")) if journal_path.exists() else {"schema_version": 1, "entries": {}}
    created, reused = 0, 0
    for clip, entry in zip(data["clips"], prepared["clips"], strict=True):
        digest = entry["cache_key"]
        output = cache / (digest + ".mp3")
        if output.is_file():
            saved = journal["entries"].get(digest, {})
            if output.stat().st_size > 10_000_000 or saved.get("state") != "complete" or saved.get("audio_sha256") != hashlib.sha256(output.read_bytes()).hexdigest():
                raise AudioError("Cache sem confirmação no diário; revise antes de reutilizar.")
            reused += 1
        else:
            if digest in journal["entries"]:
                raise AudioError("Geração anterior interrompida ou incerta. Confira o histórico ElevenLabs antes de qualquer nova tentativa.")
            journal["entries"][digest] = {"state": "pending", "clip_id": clip["id"], "characters": entry["characters"], "created_unix": int(time.time())}
            atomic_json(journal_path, journal)  # Persistir antes do único POST.
            try:
                payload = {"text": clip["text"], "model_id": prepared["model_id"], "seed": 13022,
                           "voice_settings": data.get("voice_settings", SETTINGS)}
                voice = data["voices"][clip["voice_role"]]["voice_id"]
                audio, _headers = client.request("/v1/text-to-speech/" + urllib.parse.quote(voice, safe="") + "?output_format=mp3_44100_128", payload)
                if len(audio) < 128 or not (audio.startswith(b"ID3") or (audio[0] == 0xFF and audio[1] & 0xE0 == 0xE0)):
                    raise AudioError("A resposta não contém MP3 reconhecível. Nenhuma repetição automática.")
                with output.open("xb") as handle:
                    handle.write(audio)
                journal["entries"][digest]["state"] = "complete"
                journal["entries"][digest]["audio_sha256"] = hashlib.sha256(audio).hexdigest()
                atomic_json(journal_path, journal)
                created += 1
            except (AudioError, OSError):
                journal["entries"][digest]["state"] = "uncertain"
                atomic_json(journal_path, journal)
                raise
        clip["clip_path"] = "res://assets/audio/elevenlabs/" + output.name
        clip["cache_key"] = digest
        atomic_json(manifest_path, data)  # Clipe concluído é aproveitado mesmo se o próximo falhar.
    data["status"] = "generated_pending_listening_review"
    atomic_json(manifest_path, data)
    return {"created": created, "reused": reused, "characters_sent": sum(e["characters"] for e in prepared["clips"] if not e["cached"]),
            "status": data["status"], "next": "Ouvir e aprovar os clipes localmente antes da transmissão."}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("configure", "status", "voices", "plan"):
        sub.add_parser(name)
    select = sub.add_parser("select-voices", help="IDs públicos de vozes originais, nunca chave de API.")
    for role in ("narrator", "team1", "team2"):
        select.add_argument("--" + role, required=True)
    select.add_argument("--confirm-original-voices", action="store_true", required=True)
    generate_parser = sub.add_parser("generate", help="Gera o pacote somente com --execute; padrão é plano sem rede.")
    generate_parser.add_argument("--execute", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.command == "configure":
            result = configure()
        elif args.command == "plan" or (args.command == "generate" and not args.execute):
            result = plan(read_manifest())
        else:
            client = Client(load_key())
            if args.command == "status":
                result = client.subscription()
            elif args.command == "voices":
                result = {"voices": client.voices(), "credits_spent": 0}
            elif args.command == "select-voices":
                data = copy.deepcopy(read_manifest())
                for role in ("narrator", "team1", "team2"):
                    data["voices"][role] = {"voice_id": getattr(args, role), "original_synthetic": True}
                if args.team1 == args.team2:
                    raise AudioError("Escolha vozes distintas para as duas equipes.")
                validate_profiles(data, client.voices())
                atomic_json(MANIFEST, data)
                result = {"configured": True, "credits_spent": 0, "next": "py tools/elevenlabs_audio.py plan"}
            else:
                result = generate(read_manifest(), client)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (AudioError, OSError, ValueError, KeyError, TypeError) as exc:
        # Não publicar erros de bibliotecas que possam incluir request/headers.
        message = str(exc) if isinstance(exc, AudioError) else "Falha ao ler/gravar configuração local; confira os arquivos sem enviar segredos."
        print(json.dumps({"error": message}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
