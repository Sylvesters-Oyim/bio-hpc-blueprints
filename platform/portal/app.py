"""Cluster Portal – web interface for the lab Slurm cluster.

Users log in with their cluster account. Every action runs *as that user*
over SSH to the head node, so the portal itself needs no special rights.
Listens on 127.0.0.1 only (head node browser, or an SSH tunnel).
"""
import io, os, re, secrets, shlex, threading, time
from functools import wraps

import paramiko
from flask import (Flask, abort, flash, jsonify, redirect, render_template, request,
                   send_file, session, url_for)

TEMPLATES = "/shared/template"
IDLE_LOGOUT = 8 * 3600
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,60}$")
TEXT_EXT = {".tsv", ".csv", ".txt", ".out", ".log", ".env", ".md", ".py", ".sh", ".sbatch",
            ".smi", ".fasta", ".mdp", ".xvg", ".mut", ".pml"}
MOL_EXT = {".pdb", ".pdbqt", ".gro", ".sdf", ".mol2", ".pqr"}

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)
app.config["MAX_CONTENT_LENGTH"] = 2 * 1024**3

_conns, _lock = {}, threading.Lock()      # session token -> [SSHClient, last_used]


# ---------- SSH as the logged-in user ----------
def ssh():
    with _lock:
        c = _conns.get(session.get("token"))
        if c and c[0].get_transport() and c[0].get_transport().is_active():
            c[1] = time.time()
            return c[0]
    session.clear()
    abort(401)


def run(cmd, timeout=60):
    _, out, err = ssh().exec_command(f"bash -lc {shlex.quote(cmd)}", timeout=timeout)
    code = out.channel.recv_exit_status()
    return code, out.read().decode(errors="replace"), err.read().decode(errors="replace")


def job_dir(name):
    if not NAME_RE.match(name):
        abort(404)
    return f"/home/{session['user']}/jobs/{name}"


def safe_path(name, rel):
    rel = os.path.normpath(rel or ".")
    if rel.startswith(("..", "/")):
        abort(404)
    return f"{job_dir(name)}/{rel}"


def reaper():
    while True:
        time.sleep(300)
        with _lock:
            for t, (c, last) in list(_conns.items()):
                if time.time() - last > IDLE_LOGOUT:
                    c.close()
                    del _conns[t]


threading.Thread(target=reaper, daemon=True).start()


def login_required(f):
    @wraps(f)
    def wrapper(*a, **kw):
        if session.get("token") not in _conns:
            return redirect(url_for("login", next=request.path))
        return f(*a, **kw)
    return wrapper


@app.before_request
def csrf():
    if request.method == "POST" and request.endpoint != "login":
        if request.form.get("csrf") != session.get("csrf"):
            abort(400)


@app.errorhandler(401)
def unauthorized(_):
    return redirect(url_for("login"))


@app.context_processor
def inject():
    return {"user": session.get("user"), "csrf": session.get("csrf")}


# ---------- templates ----------
def read_settings(text):
    """settings.env -> [(key, value, label)]; the comment above a key is its label."""
    fields, label = [], ""
    for line in text.splitlines():
        if line.startswith("#"):
            label = line.lstrip("# ").strip()
        elif "=" in line:
            k, v = line.split("=", 1)
            fields.append((k.strip(), v.strip().strip("'\""), label))
            label = ""
    return fields


def list_templates():
    out = []
    for t in sorted(os.listdir(TEMPLATES)):
        readme = os.path.join(TEMPLATES, t, "README.md")
        if os.path.isfile(readme):
            lines = open(readme).read().splitlines()
            out.append({"id": t, "title": lines[0].lstrip("# "),
                        "blurb": next((l for l in lines[1:] if l.strip()), ""),
                        "needs": next((l for l in lines if l.startswith("Needs ")), "")})
    return out


# ---------- pages ----------
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            client.connect("127.0.0.1", username=request.form.get("user", "").strip(),
                           password=request.form.get("password", ""),
                           look_for_keys=False, allow_agent=False, timeout=10)
        except Exception:
            flash("Wrong username or password.")
            return render_template("login.html"), 401
        token = secrets.token_hex(24)
        with _lock:
            _conns[token] = [client, time.time()]
        session.clear()
        session.update(token=token, user=request.form["user"].strip(), csrf=secrets.token_hex(16))
        nxt = request.args.get("next", "/")
        return redirect(nxt if nxt.startswith("/") and not nxt.startswith("//") else "/")
    return render_template("login.html")


@app.route("/logout")
def logout():
    with _lock:
        c = _conns.pop(session.get("token"), None)
    if c:
        c[0].close()
    session.clear()
    return redirect(url_for("login"))


@app.route("/")
@login_required
def dashboard():
    return render_template("dashboard.html")


@app.route("/api/status")
@login_required
def api_status():
    _, nodes, _ = run("sinfo -h -N -o '%N|%T|%C|%m|%e|%O'")
    _, queue, _ = run("squeue -h -o '%i|%u|%j|%T|%M|%l|%D|%C|%R'")
    node_rows = []
    for line in nodes.splitlines():
        n, state, cpus, mem, free, load = line.split("|")
        alloc, _, _, total = map(int, cpus.split("/"))
        node_rows.append({"name": n, "state": state, "alloc": alloc, "total": total, "mem": int(mem),
                          "free_mem": int(free) if free.isdigit() else None, "load": load})
    keys = ["id", "user", "name", "state", "time", "limit", "nodes", "cpus", "where"]
    return jsonify(nodes=node_rows, queue=[dict(zip(keys, l.split("|"))) for l in queue.splitlines()])


@app.route("/new")
@login_required
def new():
    return render_template("new.html", templates=list_templates())


@app.route("/new/<tid>", methods=["GET", "POST"])
@login_required
def new_job(tid):
    tdir = os.path.join(TEMPLATES, tid)
    if not NAME_RE.match(tid) or not os.path.isdir(tdir):
        abort(404)
    fields = read_settings(open(os.path.join(tdir, "settings.env")).read())

    if request.method == "GET":
        return render_template("new_job.html", tid=tid, fields=fields,
                               readme=open(os.path.join(tdir, "README.md")).read(),
                               inputs=sorted(os.listdir(os.path.join(tdir, "input"))),
                               default=f"{tid.split('_', 1)[-1]}-{time.strftime('%m%d-%H%M')}")

    name = request.form.get("name", "").strip()
    if not NAME_RE.match(name):
        flash("Job name: letters, numbers, - _ . only.")
        return redirect(request.url)
    d = job_dir(name)
    code, _, err = run(f"mkdir -p ~/jobs && [ ! -e {shlex.quote(d)} ] && cp -r {TEMPLATES}/{tid} {shlex.quote(d)}")
    if code:
        flash(f"A job called {name} already exists. {err}")
        return redirect(request.url)

    sftp = ssh().open_sftp()
    uploads = [f for f in request.files.getlist("files") if f.filename]
    if uploads and not request.form.get("keep_examples"):
        run(f"rm -f {shlex.quote(d)}/input/*")
    for f in uploads:
        sftp.putfo(f.stream, f"{d}/input/{os.path.basename(f.filename)}")

    lines = []
    for key, _, label in fields:
        value = request.form.get(key, "").replace("\n", " ").strip()
        lines += ([f"# {label}"] if label else []) + [f"{key}={shlex.quote(value) if value else ''}"]
    with sftp.open(f"{d}/settings.env", "w") as fh:
        fh.write("\n".join(lines) + "\n")
    sftp.close()

    code, out, err = run(f"cd {shlex.quote(d)} && ./submit.sh", timeout=300)
    flash(("Submitted. " if code == 0 else "Submit failed. ") + (out + err).strip())
    return redirect(url_for("job", name=name))


@app.route("/jobs")
@login_required
def jobs():
    _, out, _ = run("mkdir -p ~/jobs; cd ~/jobs; for d in */; do [ -d \"$d\" ] || continue; d=${d%/}; "
                    "printf '%s|%s|%s\\n' \"$d\" \"$(stat -c %Y \"$d\")\" \"$(ls \"$d/results\" 2>/dev/null | wc -l)\"; done")
    _, q, _ = run("squeue --me -h -o '%T|%Z'")
    active = {}
    for line in q.splitlines():
        state, wd = line.split("|", 1)
        active.setdefault(os.path.basename(wd), []).append(state)
    rows = []
    for line in out.splitlines():
        name, mtime, nres = line.split("|")
        states = active.get(name, [])
        rows.append({"name": name, "mtime": time.strftime("%d %b %H:%M", time.localtime(int(mtime))),
                     "sort": int(mtime), "results": int(nres),
                     "status": "running" if "RUNNING" in states else "queued" if states else "done"})
    return render_template("jobs.html", rows=sorted(rows, key=lambda r: -r["sort"]))


@app.route("/jobs/<name>")
@login_required
def job(name):
    d = job_dir(name)
    code, listing, _ = run(f"cd {shlex.quote(d)} && find results logs input -type f -printf '%p|%s\\n' 2>/dev/null | sort")
    if code and not listing:
        abort(404)
    files = {"results": [], "logs": [], "input": []}
    for line in listing.splitlines():
        path, size = line.rsplit("|", 1)
        if path.startswith("results/parts/") or path.count("/") > 3:
            continue
        files[path.split("/")[0]].append({"path": path, "size": int(size),
                                          "ext": os.path.splitext(path)[1].lower()})
    _, q, _ = run("squeue --me -h -o '%i|%j|%T|%M|%R|%Z'")
    queue = [dict(zip(["id", "name", "state", "time", "where"], l.split("|")[:5]))
             for l in q.splitlines() if l.endswith("|" + d)]
    _, settings, _ = run(f"cat {shlex.quote(d)}/settings.env")
    return render_template("job.html", name=name, files=files, queue=queue,
                           settings=read_settings(settings), TEXT_EXT=TEXT_EXT, MOL_EXT=MOL_EXT)


@app.route("/jobs/<name>/file")
@login_required
def job_file(name):
    rel = request.args.get("path", "")
    p, ext = safe_path(name, rel), os.path.splitext(rel)[1].lower()
    sftp = ssh().open_sftp()
    try:
        if request.args.get("view") and ext in TEXT_EXT:
            size = sftp.stat(p).st_size
            with sftp.open(p) as fh:
                fh.seek(max(0, size - 400_000))
                text = fh.read().decode(errors="replace")
            table = None
            if ext in {".tsv", ".csv"}:
                table = [l.split("\t" if ext == ".tsv" else ",") for l in text.splitlines()[:1001]]
            return render_template("file.html", name=name, path=rel, text=text, table=table,
                                   truncated=size > 400_000)
        buf = io.BytesIO()
        sftp.getfo(p, buf)
        buf.seek(0)
        return send_file(buf, download_name=os.path.basename(p), as_attachment=not request.args.get("raw"))
    except FileNotFoundError:
        abort(404)
    finally:
        sftp.close()


@app.route("/jobs/<name>/zip")
@login_required
def job_zip(name):
    _, out, _ = ssh().exec_command(f"cd {shlex.quote(job_dir(name))} && zip -qr - results logs settings.env input",
                                   timeout=900)
    return send_file(io.BytesIO(out.read()), download_name=f"{name}.zip", as_attachment=True)


@app.route("/jobs/<name>/<action>", methods=["POST"])
@login_required
def job_action(name, action):
    d = job_dir(name)
    if action == "cancel":
        _, q, _ = run("squeue --me -h -o '%A|%Z'")
        ids = {l.split("|")[0] for l in q.splitlines() if l.endswith("|" + d)}
        if ids:
            run("scancel " + " ".join(ids))
        flash("Cancel requested." if ids else "Nothing running.")
    elif action == "resubmit":
        code, out, err = run(f"cd {shlex.quote(d)} && ./submit.sh", timeout=300)
        flash(("Submitted. " if code == 0 else "Submit failed. ") + (out + err).strip())
    elif action == "delete":
        run(f"rm -rf {shlex.quote(d)}")
        flash(f"Deleted {name}.")
        return redirect(url_for("jobs"))
    else:
        abort(404)
    return redirect(url_for("job", name=name))


@app.route("/learn")
def learn():
    return send_file(os.path.join(app.root_path, "static", "cluster101.html"))


if __name__ == "__main__":
    from waitress import serve
    serve(app, host="127.0.0.1", port=8080, threads=16)
