# MatNexus

Standalone public distribution page for the MatNexus polyurethane design platform.

This repository only hosts the current access page. It is intentionally separated from AutoCG source code.

## Fixed Distribution Page

After GitHub Pages is enabled for this repository, use:

```text
https://wang-ao-scu.github.io/MatNexus/
```

The page shows:

- current public MatNexus address
- update date
- contact email: `wangao@163.com`

## One-Command Start And Publish

Run on the local MatNexus host:

```bash
cd /media/wang/58AFBE741F4D5555/第四章/matnexus_public_page
bash start_and_publish.sh
```

The script starts or detects the internal Streamlit service, starts a Cloudflare temporary tunnel, updates this repository's distribution page, and prints whether publishing succeeded.
It also starts a lightweight watchdog that checks the local service, Cloudflare tunnel, and distribution URL every 120 seconds. If the public tunnel becomes unreachable, the watchdog confirms the failure 3 times at 20-second intervals, then restarts the tunnel and republishes the distribution page.
Run this from a normal local terminal on the MatNexus host. Do not start the watchdog from an isolated sandbox because it must be able to see the host's `127.0.0.1:8501` service.

Expected output fields:

```text
INTERNAL_URL=http://127.0.0.1:8501
EXTERNAL_URL=https://*.trycloudflare.com
DISTRIBUTION_PUBLISH=SUCCESS
DISTRIBUTION_PAGE=https://wang-ao-scu.github.io/MatNexus/
WATCHDOG_STATUS=STARTED
WATCHDOG_INTERVAL_SECONDS=120
```

To use a different watchdog interval:

```bash
MATNEXUS_WATCH_INTERVAL=60 bash start_and_publish.sh
```

Useful runtime files:

```text
logs/healthcheck.log
logs/current_status.json
logs/watchdog_restart.log
```

Stop processes started by the script:

```bash
bash stop_matnexus_public.sh
```
