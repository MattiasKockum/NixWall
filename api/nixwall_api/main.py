import json
import os
import subprocess
import uuid
from typing import List, Optional

from fastapi import FastAPI, HTTPException, Body, Query
from fastapi.responses import JSONResponse, PlainTextResponse
import uvicorn


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


IP   = env("NW_IP_BIN", "ip")
GIT  = env("NW_GIT_BIN", "git")
NXR  = env("NW_NIXOS_REBUILD_BIN", "nixos-rebuild")
NIX  = env("NW_NIX_BIN", "nix")
SDR  = env("NW_SYSTEMD_RUN_BIN", "systemd-run")
SCT  = env("NW_SYSTEMCTL_BIN", "systemctl")
JCT  = env("NW_JOURNALCTL_BIN", "journalctl")

CONFIG_PATH = env("NW_CONFIG_PATH", "/etc/nixos/config.json")
REPO_DIR    = env("NW_REPO_DIR", "/etc/nixos")
FLAKE       = env("NW_FLAKE", "/etc/nixos")

app = FastAPI(title="NixWall API")


def _run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p


@app.get("/interfaces")
def list_interfaces():
    p = _run([IP, "-j", "addr", "show"])
    if p.returncode != 0:
        raise HTTPException(status_code=500, detail=p.stderr.strip() or "ip failed")
    try:
        return json.loads(p.stdout)
    except Exception:
        return PlainTextResponse(p.stdout, media_type="text/plain")


@app.get("/config")
def get_config():
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
def put_config(cfg: dict = Body(...)):
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, CONFIG_PATH)
    return {"status": "ok"}


@app.post("/git/commit")
def git_commit(message: str = Body(..., embed=True)):
    if not os.path.isdir(os.path.join(REPO_DIR, ".git")):
        raise HTTPException(status_code=400, detail="Not a git repository")
    out = []
    for cmd in ([GIT, "add", "-A"], [GIT, "commit", "-m", message]):
        p = _run(cmd, cwd=REPO_DIR)
        out.append({"cmd": " ".join(cmd), "rc": p.returncode, "stdout": p.stdout, "stderr": p.stderr})
    return {"steps": out}


@app.post("/git/push")
def git_push(remote: str = Body("origin", embed=True), branch: str = Body("HEAD", embed=True)):
    if not os.path.isdir(os.path.join(REPO_DIR, ".git")):
        raise HTTPException(status_code=400, detail="Not a git repository")
    p = _run([GIT, "push", remote, branch], cwd=REPO_DIR)
    return {"rc": p.returncode, "stdout": p.stdout, "stderr": p.stderr}


def _detect_attr(preferred: Optional[str]) -> str:
    if preferred:
        return preferred
    p = _run([NIX, "eval", "--json", FLAKE + "#nixosConfigurations", "--apply", "builtins.attrNames"])
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
        raise HTTPException(status_code=400, detail="mode must be one of: switch, boot, test")

    target = _detect_attr(attr)
    job_id = uuid.uuid4().hex[:10]
    unit = f"nixwall-apply-{job_id}.service"

    cmd = [
        SDR,
        "--unit", unit,
        "--description", f"NixWall apply ({mode}) via API",
        "--collect",
        "--property", "After=network-online.target",
        "--property", "Wants=network-online.target",
        NXR, mode, "--flake", f"{FLAKE}#{target}", "-L",
    ]
    if extra_args:
        cmd.extend(extra_args)

    p = _run(cmd)
    if p.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail={"message": "systemd-run failed", "rc": p.returncode, "stderr": p.stderr, "stdout": p.stdout},
        )
    return job_id, unit


@app.post("/apply", status_code=202)
def apply_config(
    mode: str = Body("switch", embed=True),
    attr: Optional[str] = Body(None, embed=True),
    extraArgs: Optional[List[str]] = Body(None, embed=True),
):
    job_id, unit = _queue_rebuild(mode, attr, extraArgs)
    return {"status": "queued", "id": job_id, "unit": unit, "mode": mode, "attr": _detect_attr(attr)}


def _unit_status(unit: str):
    p = _run([SCT, "show", unit, "-p", "ActiveState", "-p", "SubState", "-p", "ExecMainStatus", "-p", "Result"])
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


@app.get("/apply/{job_id}")
def apply_status(job_id: str):
    unit = f"nixwall-apply-{job_id}.service"
    return {"id": job_id, "unit": unit, "status": _unit_status(unit)}


@app.get("/apply/{job_id}/logs")
def apply_logs(job_id: str, lines: int = Query(200, ge=1, le=5000)):
    unit = f"nixwall-apply-{job_id}.service"
    p = _run([JCT, "-u", unit, "--no-pager", "--output=short-iso", "-n", str(lines)])
    if p.returncode != 0:
        raise HTTPException(status_code=404, detail="unit not found or no logs")
    return PlainTextResponse(p.stdout, media_type="text/plain")


def main():
    host = env("NW_API_HOST", "127.0.0.1")
    port = int(env("NW_API_PORT", "8080"))
    uvicorn.run(app, host=host, port=port)


if __name__ == "__main__":
    main()

