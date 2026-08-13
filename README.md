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

Expected output fields:

```text
INTERNAL_URL=http://127.0.0.1:8501
EXTERNAL_URL=https://*.trycloudflare.com
DISTRIBUTION_PUBLISH=SUCCESS
DISTRIBUTION_PAGE=https://wang-ao-scu.github.io/MatNexus/
```

Stop processes started by the script:

```bash
bash stop_matnexus_public.sh
```
