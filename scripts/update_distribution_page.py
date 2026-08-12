#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

URL_RE = re.compile(r"https://[-a-zA-Z0-9]+(?:\.[-a-zA-Z0-9]+)*\.trycloudflare\.com")
CONTACT = "wangao@163.com"


def render_html(url: str, updated_at: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MatNexus Access</title>
  <style>
    body {{ margin: 0; background: #f7f9fc; color: #17212b; font-family: Arial, Helvetica, sans-serif; }}
    main {{ max-width: 760px; margin: 0 auto; padding: 56px 22px; }}
    section {{ background: white; border: 1px solid #d9e2ea; border-radius: 8px; padding: 30px; box-shadow: 0 12px 28px rgba(30,50,80,.08); }}
    h1 {{ margin: 0 0 10px; font-size: 34px; letter-spacing: 0; }}
    p {{ line-height: 1.65; }}
    .muted {{ color: #5f6b76; }}
    .status {{ display: inline-flex; gap: 8px; align-items: center; color: #0a7f55; font-weight: 700; margin: 16px 0; }}
    .dot {{ width: 10px; height: 10px; border-radius: 50%; background: #0a7f55; }}
    .url {{ padding: 16px; border: 1px solid #d9e2ea; border-radius: 8px; background: #fbfdff; word-break: break-all; }}
    .url a {{ color: #0f63ce; font-size: 18px; font-weight: 700; text-decoration: none; }}
    .button {{ display: inline-flex; margin-top: 20px; min-height: 42px; align-items: center; padding: 0 16px; border-radius: 6px; color: white; background: #0f63ce; text-decoration: none; font-weight: 700; }}
    .meta {{ margin-top: 20px; color: #5f6b76; font-size: 14px; }}
  </style>
</head>
<body>
  <main>
    <section>
      <h1>MatNexus</h1>
      <p class="muted">Current public access page for the MatNexus polyurethane design platform.</p>
      <div class="status"><span class="dot"></span><span>Current address</span></div>
      <div class="url"><a href="{url}">{url}</a></div>
      <a class="button" href="{url}">Open MatNexus</a>
      <p class="meta">Updated at: <strong>{updated_at}</strong><br>Contact: <a href="mailto:{CONTACT}">{CONTACT}</a></p>
    </section>
  </main>
</body>
</html>
"""


def run(cmd: list[str], cwd: Path) -> None:
    subprocess.run(cmd, cwd=cwd, text=True, check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--site-dir", type=Path, required=True)
    parser.add_argument("--publish-repo", type=Path)
    parser.add_argument("--publish-subdir", default="matnexus")
    parser.add_argument("--push", action="store_true")
    args = parser.parse_args()

    url = args.url.strip()
    if not URL_RE.fullmatch(url):
        raise SystemExit(f"Invalid Cloudflare tunnel URL: {url}")

    updated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    args.site_dir.mkdir(parents=True, exist_ok=True)
    (args.site_dir / "index.html").write_text(render_html(url, updated_at), encoding="utf-8")
    (args.site_dir / "status.json").write_text(json.dumps({
        "platform": "MatNexus",
        "current_url": url,
        "updated_at": updated_at,
        "contact": CONTACT,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Local distribution page updated: {args.site_dir / 'index.html'}")

    if args.publish_repo:
        publish_subdir = args.publish_subdir.strip()
        target = args.publish_repo if publish_subdir in {"", "."} else args.publish_repo / publish_subdir
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.site_dir / "index.html", target / "index.html")
        shutil.copy2(args.site_dir / "status.json", target / "status.json")
        if args.push:
            add_paths = ["index.html", "status.json"] if publish_subdir in {"", "."} else [f"{publish_subdir}/index.html", f"{publish_subdir}/status.json"]
            run(["git", "add", *add_paths], args.publish_repo)
            diff = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=args.publish_repo)
            if diff.returncode == 0:
                print("DISTRIBUTION_STATUS=SUCCESS_NO_CHANGE")
                return
            run(["git", "commit", "-m", "Update MatNexus distribution URL"], args.publish_repo)
            run(["git", "-c", "core.sshCommand=ssh -p 443 -o StrictHostKeyChecking=accept-new", "push", "git@ssh.github.com:Wang-Ao-SCU/matnexus.git", "main"], args.publish_repo)
            print("DISTRIBUTION_STATUS=SUCCESS_PUSHED")


if __name__ == "__main__":
    main()
