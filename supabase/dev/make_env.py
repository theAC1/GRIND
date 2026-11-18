#!/usr/bin/env python3
"""Erzeugt .env mit Test-Geheimnissen und den dazu passenden API-Schlüsseln."""
import base64, hashlib, hmac, json, os, secrets, time

here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, ".env")
if os.path.exists(path):
    print(".env existiert bereits")
    raise SystemExit

def b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def jwt(role: str, secret: str) -> str:
    now = int(time.time())
    head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    body = b64(json.dumps({"role": role, "iss": "supabase", "iat": now,
                           "exp": now + 10 * 365 * 24 * 3600}, separators=(",", ":")).encode())
    sig = hmac.new(secret.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest()
    return f"{head}.{body}.{b64(sig)}"

secret = secrets.token_hex(32)
with open(path, "w") as f:
    f.write(f"POSTGRES_PASSWORD={secrets.token_hex(16)}\n")
    f.write(f"JWT_SECRET={secret}\n")
    f.write(f"ANON_KEY={jwt('anon', secret)}\n")
    f.write(f"SERVICE_ROLE_KEY={jwt('service_role', secret)}\n")
print("geschrieben:", path)
