import json
import os
import subprocess
import uuid
from typing import List, Optional

from fastapi import FastAPI, APIRouter, Depends, HTTPException, Body, Query
from fastapi.responses import JSONResponse, PlainTextResponse
import uvicorn

import pam
from fastapi.security import HTTPBasic

app = FastAPI(title="NixWall API")

security = HTTPBasic()


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


PAM_SERVICE = os.environ.get("NW_PAM_SERVICE", "nixwall-auth")

IP = env("NW_IP_BIN", "ip")
GIT = env("NW_GIT_BIN", "git")
NXR = env("NW_NIXOS_REBUILD_BIN", "nixos-rebuild")
NIX = env("NW_NIX_BIN", "nix")
SDR = env("NW_SYSTEMD_RUN_BIN", "systemd-run")
SCT = env("NW_SYSTEMCTL_BIN", "systemctl")
JCT = env("NW_JOURNALCTL_BIN", "journalctl")

CONFIG_PATH = env("NW_CONFIG_PATH", "/etc/nixos/config.json")
REPO_DIR = env("NW_REPO_DIR", "/etc/nixos")
FLAKE = env("NW_FLAKE", "/etc/nixos")


def require_auth(creds=Depends(security)):
    pam_auth = pam.pam()
    if not pam_auth.authenticate(creds.username, creds.password, service=PAM_SERVICE):
        from fastapi import HTTPException

        raise HTTPException(status_code=401, detail="Unauthorized")
    return creds.username


router = APIRouter(dependencies=[Depends(require_auth)])


def _run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p


@router.get("/interfaces")
def list_interfaces(user: str = Depends(require_auth)):
    p = _run([IP, "-j", "addr", "show"])
    if p.returncode != 0:
        raise HTTPException(status_code=500, detail=p.stderr.strip() or "ip failed")
    try:
        return json.loads(p.stdout)
    except Exception:
        return PlainTextResponse(p.stdout, media_type="text/plain")


@router.get("/config")
def get_config(user: str = Depends(require_auth)):
    try:
        with open(CONFIG_PATH, "r") as f:
            data = json.load(f)
        return JSONResponse(content=data)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="config.json not found")
    except json.JSONDecodeError:
        with open(CONFIG_PATH, "r") as f:
            return PlainTextResponse(f.read(), media_type="application/json")


@app.put("/config")
def put_config(cfg: dict = Body(...), user: str = Depends(require_auth)):
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, CONFIG_PATH)
    return {"status": "ok"}


@app.post("/git/commit")
def git_commit(message: str = Body(..., embed=True), user: str = Depends(require_auth)):
    if not os.path.isdir(os.path.join(REPO_DIR, ".git")):
        raise HTTPException(status_code=400, detail="Not a git repository")
    out = []
    for cmd in ([GIT, "add", "-A"], [GIT, "commit", "-m", message]):
        p = _run(cmd, cwd=REPO_DIR)
        out.append(
            {
                "cmd": " ".join(cmd),
                "rc": p.returncode,
                "stdout": p.stdout,
                "stderr": p.stderr,
            }
        )
    return {"steps": out}


@app.post("/git/push")
def git_push(
    remote: str = Body("origin", embed=True),
    branch: str = Body("HEAD", embed=True),
    user: str = Depends(require_auth),
):
    if not os.path.isdir(os.path.join(REPO_DIR, ".git")):
        raise HTTPException(status_code=400, detail="Not a git repository")
    p = _run([GIT, "push", remote, branch], cwd=REPO_DIR)
    return {"rc": p.returncode, "stdout": p.stdout, "stderr": p.stderr}


def _detect_attr(preferred: Optional[str]) -> str:
    if preferred:
        return preferred
    p = _run(
        [
            NIX,
            "eval",
            "--json",
            FLAKE + "#nixosConfigurations",
            "--apply",
            "builtins.attrNames",
        ]
    )
    if p.returncode != 0:
        return "nixwall"
    try:
        names = json.loads(p.stdout)
        if "nixwall" in names:
            return "nixwall"
        if "machine" in names:
            return "machine"
        return names[0] if names else "nixwall"
    except Exception:
        return "nixwall"


def _queue_rebuild(mode: str, attr: Optional[str], extra_args: Optional[List[str]]):
    mode = mode or "switch"
    if mode not in ("switch", "boot", "test"):
        raise HTTPException(
            status_code=400, detail="mode must be one of: switch, boot, test"
        )

    target = _detect_attr(attr)
    job_id = uuid.uuid4().hex[:10]
    unit = f"nixwall-apply-{job_id}.service"

    cmd = [
        SDR,
        "--unit",
        unit,
        "--description",
        f"NixWall apply ({mode}) via API",
        "--collect",
        "--property",
        "After=network-online.target",
        "--property",
        "Wants=network-online.target",
        NXR,
        mode,
        "--flake",
        f"{FLAKE}#{target}",
        "-L",
    ]
    if extra_args:
        cmd.extend(extra_args)

    p = _run(cmd)
    if p.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail={
                "message": "systemd-run failed",
                "rc": p.returncode,
                "stderr": p.stderr,
                "stdout": p.stdout,
            },
        )
    return job_id, unit


@app.post("/apply", status_code=202)
def apply_config(
    mode: str = Body("switch", embed=True),
    attr: Optional[str] = Body(None, embed=True),
    extraArgs: Optional[List[str]] = Body(None, embed=True),
    user: str = Depends(require_auth),
):
    job_id, unit = _queue_rebuild(mode, attr, extraArgs)
    return {
        "status": "queued",
        "id": job_id,
        "unit": unit,
        "mode": mode,
        "attr": _detect_attr(attr),
    }


def _unit_status(unit: str):
    p = _run(
        [
            SCT,
            "show",
            unit,
            "-p",
            "ActiveState",
            "-p",
            "SubState",
            "-p",
            "ExecMainStatus",
            "-p",
            "Result",
        ]
    )
    if p.returncode != 0:
        raise HTTPException(status_code=404, detail="unit not found")
    result = {}
    for line in p.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            if k == "ExecMainStatus":
                try:
                    result[k] = int(v)
                except Exception:
                    result[k] = v
            else:
                result[k] = v
    return result


@router.get("/apply/{job_id}")
def apply_status(job_id: str, user: str = Depends(require_auth)):
    unit = f"nixwall-apply-{job_id}.service"
    return {"id": job_id, "unit": unit, "status": _unit_status(unit)}


@router.get("/apply/{job_id}/logs")
def apply_logs(
    job_id: str,
    lines: int = Query(200, ge=1, le=5000),
    user: str = Depends(require_auth),
):
    unit = f"nixwall-apply-{job_id}.service"
    p = _run([JCT, "-u", unit, "--no-pager", "--output=short-iso", "-n", str(lines)])
    if p.returncode != 0:
        raise HTTPException(status_code=404, detail="unit not found or no logs")
    return PlainTextResponse(p.stdout, media_type="text/plain")


app.include_router(router)


def main():
    host = env("NW_API_HOST", "127.0.0.1")
    port = int(env("NW_API_PORT", "8080"))
    cert = env("NW_API_TLS_CERT", "")
    key = env("NW_API_TLS_KEY", "")

    uvicorn.run(
        app,
        host=host,
        port=port,
        ssl_certfile=cert or None,
        ssl_keyfile=key or None,
    )


if __name__ == "__main__":
    main()
