#!/usr/bin/env python3
"""CoachPlan Reel-Import.

Holt ein Video (Instagram-Reel, YouTube-Short, …), zerlegt es in
Transkript und Standbilder und legt daraus in CoachPlan einen Clip und
Übungen an. Die Übungen schlägt ein Sprachmodell oder ein Agent vor; der
Trainer prüft sie in der App.

    reel_import.py doctor
    reel_import.py fetch   <url>            # Video, Standbilder, Transkript
    reel_import.py analyze <ordner>         # optional: Vorschlag per LLM-API
    reel_import.py validate <ordner>        # exercises.json prüfen
    reel_import.py upload  <ordner>         # Clip + Übungen nach CoachPlan
    reel_import.py run     <url>            # alle drei Schritte nacheinander

Ablauf und Format von exercises.json: siehe AGENT.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
TAXONOMY = json.loads((HERE / "taxonomy.json").read_text("utf-8"))
CATEGORIES = tuple(TAXONOMY["categories"])
MAX_EXERCISE_IMAGES = 4


class ImportError_(Exception):
    """Fehler mit einer Meldung für den Aufrufer."""


def load_env(path: Path = HERE / ".env") -> None:
    """Liest KEY=WERT aus .env; bereits gesetzte Variablen haben Vorrang."""
    if not path.exists():
        return
    for line in path.read_text("utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key.strip(), value)


# ---------------------------------------------------------------------------
# Kennungen
# ---------------------------------------------------------------------------

_TRACKING = re.compile(r"^(utm_|igsh|igshid|si$|feature$|fbclid|share)")


def normalize_url(url: str) -> str:
    """Gleiche Videos sollen trotz Tracking-Anhängseln gleich heißen."""
    url = url.strip()
    if "://" not in url:
        url = "https://" + url
    p = urllib.parse.urlsplit(url)
    host = p.netloc.lower().removeprefix("www.").removeprefix("m.")
    query = [
        (k, v)
        for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True)
        if not _TRACKING.match(k)
    ]
    path = p.path.rstrip("/")
    return urllib.parse.urlunsplit(
        ("https", host, path, urllib.parse.urlencode(query), "")
    )


def clip_id(url: str) -> str:
    """Stabile Kennung: derselbe Link ergibt immer denselben Clip."""
    digest = hashlib.sha1(normalize_url(url).encode("utf-8")).hexdigest()
    return "imp-" + digest[:12]


# ---------------------------------------------------------------------------
# fetch: Video, Standbilder, Transkript
# ---------------------------------------------------------------------------


def _run(cmd: list[str]) -> str:
    try:
        return subprocess.run(
            cmd, check=True, capture_output=True, text=True
        ).stdout
    except FileNotFoundError:
        raise ImportError_(f"{cmd[0]} ist nicht installiert.") from None
    except subprocess.CalledProcessError as e:
        tail = (e.stderr or "").strip().splitlines()[-3:]
        raise ImportError_(f"{cmd[0]} fehlgeschlagen: " + " | ".join(tail)) from None


def probe(video: Path) -> tuple[float, bool]:
    """Dauer in Sekunden und ob eine Tonspur vorhanden ist."""
    info = json.loads(
        _run(
            [
                "ffprobe", "-v", "error", "-print_format", "json",
                "-show_entries", "format=duration:stream=codec_type",
                str(video),
            ]
        )
    )
    duration = float(info.get("format", {}).get("duration") or 0)
    has_audio = any(s.get("codec_type") == "audio" for s in info.get("streams", []))
    return duration, has_audio


def frame_times(duration: float, count: int | None) -> list[float]:
    """Gleichmäßig verteilte Zeitpunkte; ohne Vorgabe etwa alle 4 Sekunden."""
    if duration <= 0:
        return [0.0]
    n = count or min(12, max(4, round(duration / 4)))
    return [round(duration * (i + 0.5) / n, 2) for i in range(n)]


def extract_frames(video: Path, out: Path, times: list[float]) -> list[dict]:
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    frames = []
    for i, t in enumerate(times):
        target = out / f"{i:02d}.jpg"
        _run(
            [
                "ffmpeg", "-y", "-loglevel", "error", "-ss", str(t),
                "-i", str(video), "-frames:v", "1",
                "-vf", "scale='min(1280,iw)':-2", "-q:v", "4", str(target),
            ]
        )
        if target.exists():
            frames.append({"index": i, "time": t, "file": f"frames/{target.name}"})
    return frames


class _SilentLogger:
    def debug(self, msg): pass
    def info(self, msg): pass
    def warning(self, msg): pass
    def error(self, msg): pass


def download(url: str, out: Path, cookies: str | None) -> dict:
    """Lädt das Video mit yt-dlp nach out/video.mp4 und liefert Metadaten."""
    try:
        import yt_dlp
    except ImportError:
        raise ImportError_("yt-dlp fehlt – bitte setup.sh ausführen.") from None
    for old in out.glob("video.*"):
        old.unlink()
    options = {
        "format": "bv*[height<=720]+ba/b[height<=720]/b",
        "merge_output_format": "mp4",
        "outtmpl": str(out / "video.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "logger": _SilentLogger(),  # Fehler meldet dieses Skript selbst
    }
    if cookies:
        options["cookiefile"] = cookies
    try:
        with yt_dlp.YoutubeDL(options) as ydl:
            info = ydl.extract_info(url, download=True)
    except Exception as e:  # yt-dlp wirft je nach Plattform Verschiedenes
        raise ImportError_(
            "Download fehlgeschlagen: "
            + str(e).replace("ERROR: ", "")
            + "\nHinweis: Verlangt die Plattform eine Anmeldung, hilft "
            "--cookies <datei> (siehe AGENT.md)."
        ) from None
    return {
        "title": info.get("title") or "",
        "description": info.get("description") or "",
        "uploader": info.get("uploader") or info.get("channel") or "",
        "platform": info.get("extractor_key") or "",
    }


def transcribe(video: Path, model_name: str, language: str | None) -> dict:
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        raise ImportError_("faster-whisper fehlt – bitte setup.sh ausführen.") from None
    model = WhisperModel(
        model_name,
        device=os.environ.get("WHISPER_DEVICE", "auto"),
        compute_type=os.environ.get("WHISPER_COMPUTE", "default"),
    )
    segments, info = model.transcribe(
        str(video), language=language or None, vad_filter=True
    )
    result = [
        {"start": round(s.start, 1), "end": round(s.end, 1), "text": s.text.strip()}
        for s in segments
        if s.text.strip()
    ]
    return {"language": info.language, "segments": result}


def stamp(seconds: float) -> str:
    s = int(seconds)
    return f"{s // 60}:{s % 60:02d}"


def transcript_text(segments: list[dict]) -> str:
    return "\n".join(f"[{stamp(s['start'])}] {s['text']}" for s in segments)


def cmd_fetch(a: argparse.Namespace) -> None:
    cid = clip_id(a.url)
    out = Path(a.out) / cid
    out.mkdir(parents=True, exist_ok=True)

    if a.file:
        source = Path(a.file)
        if not source.is_file():
            raise ImportError_(f"Datei nicht gefunden: {source}")
        for old in out.glob("video.*"):
            old.unlink()
        video = out / f"video{source.suffix or '.mp4'}"
        shutil.copyfile(source, video)
        meta = {"title": "", "description": "", "uploader": "", "platform": ""}
    else:
        print(f"Lade {a.url} …")
        meta = download(a.url, out, a.cookies)
        videos = sorted(out.glob("video.*"))
        if not videos:
            raise ImportError_("yt-dlp hat keine Videodatei geliefert.")
        video = videos[0]
    if a.title:
        meta["title"] = a.title

    duration, has_audio = probe(video)
    frames = extract_frames(video, out / "frames", frame_times(duration, a.frames))
    print(f"{len(frames)} Standbilder, Dauer {stamp(duration)}")

    if a.transcript_file:
        text = Path(a.transcript_file).read_text("utf-8").strip()
        speech = {"language": a.language or "", "segments": [], "text": text}
    elif a.no_transcribe or not has_audio:
        speech = {"language": "", "segments": [], "text": ""}
        print("Keine Transkription" + ("" if has_audio else " (keine Tonspur)"))
    else:
        print(f"Transkribiere mit Whisper ({a.model}) …")
        speech = transcribe(video, a.model, a.language)
        speech["text"] = transcript_text(speech["segments"])
        print(f"{len(speech['segments'])} Abschnitte, Sprache: {speech['language']}")

    result = {
        "clipId": cid,
        "url": normalize_url(a.url),
        "title": meta["title"],
        "caption": meta["description"],
        "uploader": meta["uploader"],
        "platform": meta["platform"],
        "duration": round(duration, 1),
        "language": speech["language"],
        "transcript": speech["text"],
        "segments": speech["segments"],
        "frames": frames,
        "video": video.name,
    }
    if a.delete_video:
        video.unlink()
        result["video"] = None
    (out / "result.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), "utf-8"
    )
    (out / "transcript.txt").write_text(speech["text"] + "\n", "utf-8")
    print(f"Fertig: {out}")


# ---------------------------------------------------------------------------
# exercises.json: prüfen und vereinheitlichen
# ---------------------------------------------------------------------------

_CATEGORY_ALIASES = {
    "kraft": "kraft", "strength": "kraft", "krafttraining": "kraft",
    "physio": "physio", "reha": "physio", "rehab": "physio",
    "physiotherapie": "physio", "prävention": "physio",
    "mobility": "mobility", "mobilität": "mobility", "mobilitaet": "mobility",
    "beweglichkeit": "mobility", "dehnung": "mobility", "stretching": "mobility",
}


def _strings(value) -> list[str]:
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list):
        return []
    seen, out = set(), []
    for v in value:
        s = str(v).strip()
        if s and s.lower() not in seen:
            seen.add(s.lower())
            out.append(s)
    return out


def _match_vocabulary(tags: list[str], vocabulary: list[str]) -> list[str]:
    """Schreibweise des Baukastens übernehmen ("maximalkraft" → "Maximalkraft")."""
    by_lower = {v.lower(): v for v in vocabulary}
    return [by_lower.get(t.lower(), t) for t in tags]


def normalize_exercises(data, frame_count: int) -> tuple[list[dict], list[str]]:
    """Liefert bereinigte Übungen und Hinweise. Wirft bei harten Fehlern."""
    if isinstance(data, dict):
        data = data.get("exercises")
    if not isinstance(data, list):
        raise ImportError_('Erwartet: {"exercises": [ … ]}')
    exercises, notes, names = [], [], set()
    for n, raw in enumerate(data, start=1):
        if not isinstance(raw, dict):
            raise ImportError_(f"Übung {n}: kein Objekt.")
        name = str(raw.get("name") or "").strip()
        if not name:
            raise ImportError_(f"Übung {n}: name fehlt.")
        if name.lower() in names:
            raise ImportError_(f"Übung {n}: „{name}“ kommt doppelt vor.")
        names.add(name.lower())
        category = _CATEGORY_ALIASES.get(str(raw.get("category") or "").strip().lower())
        if category is None:
            raise ImportError_(
                f"Übung {n} („{name}“): category muss eine von "
                + ", ".join(CATEGORIES) + " sein."
            )
        goals = _match_vocabulary(_strings(raw.get("goals")), TAXONOMY["goals"])
        equipment = _match_vocabulary(
            _strings(raw.get("equipment")), TAXONOMY["equipment"]
        )
        for kind, tags, known in (
            ("Ziel", goals, TAXONOMY["goals"]),
            ("Equipment", equipment, TAXONOMY["equipment"]),
        ):
            for t in tags:
                if t not in known:
                    notes.append(f"„{name}“: neues Schlagwort ({kind}) „{t}“")
        frames = []
        for f in raw.get("frames") or []:
            if isinstance(f, bool) or not isinstance(f, int):
                raise ImportError_(f"Übung {n} („{name}“): frames müssen Zahlen sein.")
            if not 0 <= f < frame_count:
                raise ImportError_(
                    f"Übung {n} („{name}“): Standbild {f} gibt es nicht "
                    f"(vorhanden: 0 bis {frame_count - 1})."
                )
            if f not in frames:
                frames.append(f)
        if len(frames) > MAX_EXERCISE_IMAGES:
            notes.append(f"„{name}“: nur die ersten {MAX_EXERCISE_IMAGES} Bilder werden übernommen")
            frames = frames[:MAX_EXERCISE_IMAGES]
        if not str(raw.get("description") or "").strip():
            notes.append(f"„{name}“: keine Coach-Hinweise (description)")
        exercises.append(
            {
                "name": name,
                "category": category,
                "bodyRegion": str(raw.get("bodyRegion") or "").strip(),
                "goals": goals,
                "equipment": equipment,
                "description": str(raw.get("description") or "").strip(),
                "whenToUse": str(raw.get("whenToUse") or "").strip(),
                "frames": frames,
            }
        )
    return exercises, notes


def read_result(folder: Path) -> dict:
    path = folder / "result.json"
    if not path.exists():
        raise ImportError_(f"{path} fehlt – zuerst „fetch“ ausführen.")
    return json.loads(path.read_text("utf-8"))


def read_exercises(folder: Path, result: dict) -> tuple[list[dict], list[str]]:
    path = folder / "exercises.json"
    if not path.exists():
        return [], []
    try:
        data = json.loads(path.read_text("utf-8"))
    except json.JSONDecodeError as e:
        raise ImportError_(f"exercises.json ist kein gültiges JSON: {e}") from None
    return normalize_exercises(data, len(result["frames"]))


def cmd_validate(a: argparse.Namespace) -> None:
    folder = Path(a.folder)
    result = read_result(folder)
    if not (folder / "exercises.json").exists():
        raise ImportError_("exercises.json fehlt.")
    exercises, notes = read_exercises(folder, result)
    for e in exercises:
        print(f"  {e['category']:8} {e['name']}  ({len(e['frames'])} Bilder)")
    for n in notes:
        print("Hinweis:", n)
    print(f"{len(exercises)} Übungen, gültig.")


# ---------------------------------------------------------------------------
# analyze: Vorschlag über eine OpenAI-kompatible Chat-Schnittstelle
# ---------------------------------------------------------------------------


def build_prompt(result: dict) -> tuple[str, str]:
    system = (
        "Du hilfst einem Trainer, Übungen aus einem Trainingsvideo in seine "
        "Übungsbibliothek zu übernehmen. Du bekommst Titel, Beschreibung und "
        "Transkript des Videos sowie die Zeitpunkte der Standbilder.\n\n"
        "Antworte ausschließlich mit JSON in dieser Form:\n"
        '{"exercises": [{"name": "…", "category": "kraft|physio|mobility", '
        '"bodyRegion": "…", "goals": ["…"], "equipment": ["…"], '
        '"description": "…", "whenToUse": "…", "frames": [0, 1]}]}\n\n'
        "Regeln:\n"
        "- Eine Übung je klar unterscheidbarer Bewegung; zeigt das Video "
        "mehrere, dann mehrere Einträge.\n"
        "- Nur verwenden, was Titel, Beschreibung oder Transkript hergeben. "
        "Nichts erfinden. Fehlt eine Angabe, das Feld leer lassen.\n"
        "- description: Coach-Hinweise zur Ausführung, knapp, auf Deutsch.\n"
        "- whenToUse: wofür und wann die Übung eingesetzt wird.\n"
        "- goals bevorzugt aus: " + ", ".join(TAXONOMY["goals"]) + "\n"
        "- equipment bevorzugt aus: " + ", ".join(TAXONOMY["equipment"]) + "\n"
        "- frames: Nummern der Standbilder, deren Zeitpunkt zur Übung passt "
        "(höchstens 4); leer, wenn unklar.\n"
        "- Enthält das Video keine erkennbare Übung: {\"exercises\": []}."
    )
    frames = ", ".join(f"{f['index']} bei {stamp(f['time'])}" for f in result["frames"])
    user = (
        f"Titel: {result.get('title') or '–'}\n"
        f"Von: {result.get('uploader') or '–'}\n\n"
        f"Beschreibung:\n{result.get('caption') or '–'}\n\n"
        f"Transkript:\n{result.get('transcript') or '– (kein gesprochener Text)'}\n\n"
        f"Standbilder (Nummer bei Zeit): {frames or '–'}"
    )
    return system, user


def extract_json(text: str):
    """Holt das JSON aus einer Modellantwort, auch aus ```-Blöcken."""
    text = text.strip()
    fenced = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    if fenced:
        text = fenced.group(1).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    start, end = text.find("{"), text.rfind("}")
    if start >= 0 and end > start:
        try:
            return json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            pass
    raise ImportError_("Die Modellantwort enthält kein gültiges JSON.")


def http(method: str, url: str, headers: dict, body: bytes | None = None,
         timeout: int = 120) -> bytes:
    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:400]
        raise ImportError_(f"{method} {url} → HTTP {e.code}: {detail}") from None
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise ImportError_(f"{url} ist nicht erreichbar: {e}") from None


def chat(base_url: str, model: str, key: str | None, system: str, user: str) -> str:
    url = base_url.rstrip("/") + "/chat/completions"
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    payload = {
        "model": model,
        "temperature": 0.2,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }
    raw = http("POST", url, headers, json.dumps(payload).encode("utf-8"), timeout=600)
    try:
        return json.loads(raw)["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError, json.JSONDecodeError):
        raise ImportError_("Unerwartete Antwort der LLM-Schnittstelle.") from None


def cmd_analyze(a: argparse.Namespace) -> None:
    folder = Path(a.folder)
    result = read_result(folder)
    base = a.llm_url or os.environ.get("LLM_URL")
    model = a.llm_model or os.environ.get("LLM_MODEL")
    if not base or not model:
        raise ImportError_("LLM_URL und LLM_MODEL fehlen (.env oder --llm-url/--llm-model).")
    system, user = build_prompt(result)
    answer = chat(base, model, os.environ.get("LLM_API_KEY"), system, user)
    exercises, notes = normalize_exercises(extract_json(answer), len(result["frames"]))
    (folder / "exercises.json").write_text(
        json.dumps({"exercises": exercises}, ensure_ascii=False, indent=2), "utf-8"
    )
    for e in exercises:
        print(f"  {e['category']:8} {e['name']}")
    for n in notes:
        print("Hinweis:", n)
    print(f"{len(exercises)} Übungen vorgeschlagen → {folder / 'exercises.json'}")


# ---------------------------------------------------------------------------
# upload: Clip und Übungen nach CoachPlan (Supabase)
# ---------------------------------------------------------------------------


class CoachPlan:
    def __init__(self) -> None:
        missing = [
            k for k in ("COACHPLAN_URL", "COACHPLAN_ANON_KEY",
                        "COACHPLAN_EMAIL", "COACHPLAN_PASSWORD")
            if not os.environ.get(k)
        ]
        if missing:
            raise ImportError_("In .env fehlen: " + ", ".join(missing))
        self.base = os.environ["COACHPLAN_URL"].rstrip("/")
        self.key = os.environ["COACHPLAN_ANON_KEY"]
        raw = http(
            "POST",
            f"{self.base}/auth/v1/token?grant_type=password",
            {"apikey": self.key, "Content-Type": "application/json"},
            json.dumps({
                "email": os.environ["COACHPLAN_EMAIL"],
                "password": os.environ["COACHPLAN_PASSWORD"],
            }).encode("utf-8"),
        )
        session = json.loads(raw)
        self.token = session["access_token"]
        self.user_id = session["user"]["id"]
        profile = self.rest("GET", f"profiles?select=role&id=eq.{self.user_id}")
        if not profile or profile[0].get("role") != "coach":
            raise ImportError_("Das Konto ist kein Trainer-Konto.")

    def _headers(self, extra: dict | None = None) -> dict:
        return {"apikey": self.key, "Authorization": f"Bearer {self.token}", **(extra or {})}

    def rest(self, method: str, path: str, body=None, prefer: str | None = None):
        headers = self._headers({"Content-Type": "application/json"})
        if prefer:
            headers["Prefer"] = prefer
        raw = http(
            method, f"{self.base}/rest/v1/{path}", headers,
            None if body is None else json.dumps(body).encode("utf-8"),
        )
        return json.loads(raw) if raw else None

    def upsert(self, table: str, rows: list[dict]) -> None:
        if rows:
            self.rest("POST", f"{table}?on_conflict=coach_id,id", rows,
                      prefer="resolution=merge-duplicates,return=minimal")

    def existing_ids(self, table: str, ids: list[str]) -> set[str]:
        if not ids:
            return set()
        quoted = ",".join(f'"{i}"' for i in ids)
        rows = self.rest(
            "GET",
            f"{table}?select=id&coach_id=eq.{self.user_id}&deleted=is.false"
            f"&id=in.({urllib.parse.quote(quoted)})",
        )
        return {r["id"] for r in rows}

    def upload_image(self, image_id: str, path: Path) -> None:
        http(
            "POST",
            f"{self.base}/storage/v1/object/media/{self.user_id}/{image_id}",
            self._headers({"Content-Type": "image/jpeg", "x-upsert": "true"}),
            path.read_bytes(),
        )


def clip_notes(result: dict) -> str:
    parts = []
    if result.get("uploader"):
        parts.append(f"Von: {result['uploader']}")
    if result.get("caption"):
        parts.append(result["caption"].strip())
    if result.get("transcript"):
        language = f", {result['language']}" if result.get("language") else ""
        parts.append(f"Transkript (automatisch{language}):\n{result['transcript']}")
    return "\n\n".join(parts)


def cmd_upload(a: argparse.Namespace) -> None:
    folder = Path(a.folder)
    result = read_result(folder)
    exercises, notes = read_exercises(folder, result)
    for n in notes:
        print("Hinweis:", n)

    cid = result["clipId"]
    image_ids = {f["index"]: f"{cid}-f{f['index']:02d}" for f in result["frames"]}
    exercise_ids = [f"{cid}-x{i:02d}" for i in range(len(exercises))]

    api = CoachPlan()
    for f in result["frames"]:
        api.upload_image(image_ids[f["index"]], folder / f["file"])
    print(f"{len(image_ids)} Bilder hochgeladen")

    clip_exists = bool(api.existing_ids("clips", [cid]))
    if clip_exists and not a.overwrite:
        print("Clip existiert schon – unverändert gelassen (--overwrite zum Ersetzen)")
    else:
        api.upsert("clips", [{
            "coach_id": api.user_id,
            "id": cid,
            "deleted": False,
            "data": {
                "url": result["url"],
                "title": result.get("title") or "",
                "notes": clip_notes(result),
                "imageIds": list(image_ids.values()),
                "createdAt": datetime.now().isoformat(timespec="milliseconds"),
            },
        }])
        print("Clip " + ("aktualisiert" if clip_exists else "angelegt"))

    # Übungen, die der Trainer in der App schon bearbeitet haben könnte,
    # nicht ungefragt überschreiben.
    present = api.existing_ids("exercises", exercise_ids)
    rows, skipped = [], 0
    for eid, e in zip(exercise_ids, exercises):
        if eid in present and not a.overwrite:
            skipped += 1
            continue
        rows.append({
            "coach_id": api.user_id,
            "id": eid,
            "deleted": False,
            "data": {
                "name": e["name"],
                "category": e["category"],
                "bodyRegion": e["bodyRegion"],
                "description": e["description"],
                "whenToUse": e["whenToUse"],
                "goals": e["goals"],
                "equipment": e["equipment"],
                "videoLinks": [result["url"]],
                "imageIds": [image_ids[i] for i in e["frames"]],
                "sourceClipId": cid,
                "needsReview": True,
            },
        })
    api.upsert("exercises", rows)
    print(f"{len(rows)} Übungen angelegt" + (f", {skipped} vorhandene übersprungen" if skipped else ""))
    print("In der App: nach dem nächsten Abgleich unter „Clips“ und „Übungen“ (Marke „Prüfen“).")


# ---------------------------------------------------------------------------
# run: alles in einem Schritt
# ---------------------------------------------------------------------------


def cmd_run(a: argparse.Namespace) -> None:
    """fetch → analyze → upload. Braucht LLM_URL/LLM_MODEL für die Auswertung."""
    if not (a.llm_url or os.environ.get("LLM_URL")) or not (
        a.llm_model or os.environ.get("LLM_MODEL")
    ):
        raise ImportError_(
            "„run“ braucht LLM_URL und LLM_MODEL. Ohne LLM-Schnittstelle die "
            "Schritte einzeln ausführen (fetch, exercises.json schreiben, upload)."
        )
    cmd_fetch(a)
    a.folder = str(Path(a.out) / clip_id(a.url))
    cmd_analyze(a)
    cmd_upload(a)


# ---------------------------------------------------------------------------
# doctor
# ---------------------------------------------------------------------------


def cmd_doctor(a: argparse.Namespace) -> None:
    ok = True

    def report(label: str, good: bool, detail: str = "") -> None:
        nonlocal ok
        ok = ok and good
        print(("OK     " if good else "FEHLT  ") + label + (f"  {detail}" if detail else ""))

    for tool in ("ffmpeg", "ffprobe"):
        report(tool, shutil.which(tool) is not None)
    try:
        import yt_dlp
        report("yt-dlp", True, yt_dlp.version.__version__)
    except ImportError:
        report("yt-dlp", False, "setup.sh ausführen")
    try:
        import faster_whisper
        report("faster-whisper", True, faster_whisper.__version__)
    except ImportError:
        report("faster-whisper", False, "setup.sh ausführen")

    if a.model:
        try:
            from faster_whisper import WhisperModel
            WhisperModel(
                a.model,
                device=os.environ.get("WHISPER_DEVICE", "auto"),
                compute_type=os.environ.get("WHISPER_COMPUTE", "default"),
            )
            report(f"Whisper-Modell „{a.model}“ geladen", True)
        except Exception as e:
            report(f"Whisper-Modell „{a.model}“", False, str(e)[:200])

    configured = all(
        os.environ.get(k)
        for k in ("COACHPLAN_URL", "COACHPLAN_ANON_KEY",
                  "COACHPLAN_EMAIL", "COACHPLAN_PASSWORD")
    )
    if configured:
        try:
            api = CoachPlan()
            report("CoachPlan-Anmeldung", True, api.base)
        except ImportError_ as e:
            report("CoachPlan-Anmeldung", False, str(e)[:200])
    else:
        print("–      CoachPlan nicht konfiguriert (.env) – nur für „upload“ nötig")
    if not ok:
        sys.exit(1)


# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> None:
    load_env()
    parser = argparse.ArgumentParser(description="CoachPlan Reel-Import")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("doctor", help="Installation prüfen")
    p.add_argument("--model", help="zusätzlich dieses Whisper-Modell laden")
    p.set_defaults(func=cmd_doctor)

    def fetch_options(p: argparse.ArgumentParser) -> None:
        p.add_argument("url", help="Link zum Video (auch bei --file: Quelle für die App)")
        p.add_argument("--file", help="vorhandene Videodatei statt Download")
        p.add_argument("--out", default=os.environ.get("IMPORT_DIR", str(HERE / "imports")))
        p.add_argument("--title", help="Titel überschreiben")
        p.add_argument("--model", default=os.environ.get("WHISPER_MODEL", "small"))
        p.add_argument("--language", default=os.environ.get("WHISPER_LANGUAGE") or None,
                       help="z. B. de, en; ohne Angabe automatisch")
        p.add_argument("--frames", type=int, help="Anzahl Standbilder (sonst nach Dauer)")
        p.add_argument("--cookies", default=os.environ.get("YTDLP_COOKIES") or None,
                       help="Cookie-Datei für yt-dlp (Netscape-Format)")
        p.add_argument("--no-transcribe", action="store_true")
        p.add_argument("--transcript-file", help="fertiges Transkript statt Whisper")
        p.add_argument("--delete-video", action="store_true",
                       help="Videodatei nach der Verarbeitung löschen")

    p = sub.add_parser("fetch", help="Video holen, Standbilder und Transkript erzeugen")
    fetch_options(p)
    p.set_defaults(func=cmd_fetch)

    p = sub.add_parser("analyze", help="Übungen per LLM-Schnittstelle vorschlagen")
    p.add_argument("folder")
    p.add_argument("--llm-url", help="OpenAI-kompatible Basisadresse, z. B. http://localhost:11434/v1")
    p.add_argument("--llm-model")
    p.set_defaults(func=cmd_analyze)

    p = sub.add_parser("run", help="fetch + analyze + upload in einem Schritt")
    fetch_options(p)
    p.add_argument("--llm-url")
    p.add_argument("--llm-model")
    p.add_argument("--overwrite", action="store_true")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("validate", help="exercises.json prüfen")
    p.add_argument("folder")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("upload", help="Clip und Übungen nach CoachPlan hochladen")
    p.add_argument("folder")
    p.add_argument("--overwrite", action="store_true",
                   help="vorhandenen Clip/Übungen dieses Imports ersetzen")
    p.set_defaults(func=cmd_upload)

    args = parser.parse_args(argv)
    try:
        args.func(args)
    except ImportError_ as e:
        print("FEHLER:", e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
