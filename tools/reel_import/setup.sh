#!/usr/bin/env bash
# Richtet den Reel-Import ein: Python-Umgebung mit yt-dlp und faster-whisper.
# Voraussetzung: python3 (>= 3.10) und ffmpeg.
set -euo pipefail
cd "$(dirname "$0")"

command -v python3 >/dev/null || { echo "python3 fehlt"; exit 1; }
if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "ffmpeg fehlt. Installieren mit z. B.:  sudo apt-get install -y ffmpeg"
  exit 1
fi

[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet --upgrade -r requirements.txt
[ -f .env ] || { cp .env.example .env; chmod 600 .env; echo ".env angelegt – bitte ausfüllen."; }

.venv/bin/python reel_import.py doctor
echo
echo "Aufruf:  $(pwd)/.venv/bin/python $(pwd)/reel_import.py <befehl>"
