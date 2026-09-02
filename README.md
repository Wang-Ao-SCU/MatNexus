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
By default, this is a manual restart workflow. It does not start the watchdog automatically.
Run this from a normal local terminal on the MatNexus host.

Expected output fields:

```text
INTERNAL_URL=http://127.0.0.1:8501
EXTERNAL_URL=https://*.trycloudflare.com
DISTRIBUTION_PUBLISH=SUCCESS
DISTRIBUTION_PAGE=https://wang-ao-scu.github.io/MatNexus/
WATCHDOG_STATUS=DISABLED_MANUAL_RESTART
```

## Optional Hourly Public Monitor

If you want an independent process to check the public URL every hour and recover it automatically, run:

```bash
cd /media/wang/58AFBE741F4D5555/第四章/matnexus_public_page
setsid ./monitor_matnexus_hourly.sh > logs/hourly_monitor.stdout.log 2>&1 < /dev/null &
echo $! > logs/hourly_monitor.pid
```

The monitor reads `status.json`, tests the current public `trycloudflare.com` URL, and only if the public check fails after rechecks it runs:

```bash
bash stop_matnexus_public.sh
bash start_and_publish.sh
```

Test once without starting the long-running monitor:

```bash
./monitor_matnexus_hourly.sh --once
```

To change the interval, for example to 30 minutes:

```bash
MATNEXUS_MONITOR_INTERVAL=1800 setsid ./monitor_matnexus_hourly.sh > logs/hourly_monitor.stdout.log 2>&1 < /dev/null &
echo $! > logs/hourly_monitor.pid
```

Useful runtime files:

```text
logs/hourly_monitor.log
logs/hourly_monitor.pid
```

Stop processes started by the script:

```bash
bash stop_matnexus_public.sh
```
