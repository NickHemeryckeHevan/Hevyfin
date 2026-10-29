"""The services the panel talks to. Jellyfin calls are made with the signed-in admin's own token;
Seerr, Sonarr, Radarr, Prowlarr and qBittorrent with their API keys (from the environment).
Only JELLYFIN_URL is needed; each of the others is optional and off when its URL is unset."""
import os

import requests

ENV = os.environ.get
JELLYFIN = ENV("JELLYFIN_URL", "http://host.containers.internal:8096").rstrip("/")
CLIENT = 'MediaBrowser Client="Hevyfin Admin", Device="Panel", DeviceId="hevyfin-admin-panel", Version="1.0.0"'


class ServiceError(Exception):
    def __init__(self, message, status=502):
        super().__init__(message)
        self.status = status


def _check(r, name):
    if r.status_code == 401:
        raise ServiceError(f"{name} refused the sign-in", 401)
    if r.status_code >= 400:
        detail = r.text[:200].strip().strip('"')
        raise ServiceError(f"{name}: {detail or r.status_code}", 400 if r.status_code < 500 else 502)
    return r.json() if r.content and "json" in r.headers.get("Content-Type", "") else None


def jellyfin(method, path, token=None, **kw):
    auth = CLIENT + (f', Token="{token}"' if token else "")
    try:
        r = requests.request(method, JELLYFIN + path, headers={"Authorization": auth}, timeout=30, **kw)
    except requests.RequestException as e:
        raise ServiceError(f"Jellyfin is unreachable ({type(e).__name__})")
    return _check(r, "Jellyfin")


class Arr:
    """Seerr (/api/v1), Sonarr and Radarr (/api/v3), Prowlarr (/api/v1): an X-Api-Key each."""

    def __init__(self, name, url, key, prefix):
        self.name, self.url, self.key, self.prefix = name, (url or "").rstrip("/"), key or "", prefix

    @property
    def configured(self):
        return bool(self.url and self.key)

    def __call__(self, method, path, **kw):
        if not self.configured:
            raise ServiceError(f"{self.name} isn't set up", 503)
        try:
            r = requests.request(method, f"{self.url}{self.prefix}/{path}", headers={"X-Api-Key": self.key}, timeout=60, **kw)
        except requests.RequestException as e:
            raise ServiceError(f"{self.name} is unreachable ({type(e).__name__})")
        return _check(r, self.name)


seerr = Arr("Seerr", ENV("SEERR_URL"), ENV("SEERR_KEY"), "/api/v1")
sonarr = Arr("Sonarr", ENV("SONARR_URL"), ENV("SONARR_KEY"), "/api/v3")
radarr = Arr("Radarr", ENV("RADARR_URL"), ENV("RADARR_KEY"), "/api/v3")
prowlarr = Arr("Prowlarr", ENV("PROWLARR_URL"), ENV("PROWLARR_KEY"), "/api/v1")
QBIT = ENV("QBIT_URL", "").rstrip("/")
_qbit = requests.Session()


def _qbit_login():
    """Signs in with QBIT_USER / QBIT_PASS when set (otherwise qBittorrent must let the panel
    in without a login, its "bypass authentication for clients in whitelisted subnets")."""
    if ENV("QBIT_USER"):
        _qbit.post(f"{QBIT}/api/v2/auth/login", data={"username": ENV("QBIT_USER"), "password": ENV("QBIT_PASS", "")},
                   headers={"Referer": QBIT}, timeout=20)


def qbit(path):
    if not QBIT:
        raise ServiceError("qBittorrent isn't set up", 503)
    try:
        r = _qbit.get(f"{QBIT}/api/v2/{path}", timeout=20)
        if r.status_code == 403 and ENV("QBIT_USER"):
            _qbit_login()
            r = _qbit.get(f"{QBIT}/api/v2/{path}", timeout=20)
    except requests.RequestException as e:
        raise ServiceError(f"qBittorrent is unreachable ({type(e).__name__})")
    return _check(r, "qBittorrent")
