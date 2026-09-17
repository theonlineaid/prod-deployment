# Sky Soft — Prod Deployment (3-VM Architecture)

This is the production layout of the same stack that runs as a single-VM
Docker Compose deployment in `../` (UAT). Prod splits it across **three
VMs**, sized as follows:

| VM | Role | vCPU | RAM (GB) | SSD (GB) |
|---|---|---|---|---|
| `monitoring-vm/` | Monitoring | 4 | 4 | 50 |
| `infra-vm/` | Infra (DB) | 8 | 16 | 350 |
| `app-vm/` | Application + Kafka + NGINX | 16 | 28 | 300 |
| **Total** | | **28** | **48** | **700** |

Each top-level folder here is deployed to its own VM — it is **not** one
Docker Compose project. There is no shared Docker network across VMs;
cross-VM traffic goes over the VMs' private LAN via published ports.

## What runs where, and why

- **`infra-vm/`** — MongoDB, PostgreSQL, and the three Redis caches
  (fix-cache, itch-cache, oms-cache). The stateful, storage-heavy tier —
  hence the 350 GB SSD. Kafka is **not** here; it's grouped with the App
  VM per the sizing table.
- **`app-vm/`** — Kafka (KRaft single broker), NGINX, and all app
  containers (`fix-initiator`, `frontend`, `itch-chart-service`,
  `itch-service`, `oms-admin` (+ its Celery worker/beat/flower/streaming
  sidecars), `oms-admin-front`). The compute-heavy tier — hence 16 vCPU.
  Kafka is co-located here because its producers/consumers
  (`oms-admin`, `fix-initiator`) are also here, keeping that traffic
  on the VM's own Docker network instead of crossing the LAN.
- **`monitoring-vm/`** — Prometheus, Grafana, blackbox-exporter only.
  node-exporter and cadvisor run **locally** on `infra-vm` and `app-vm`
  instead (that's the standard Prometheus pattern — agents run next to
  what they measure) and get scraped remotely from here. kafka-exporter
  is co-located with Kafka on `app-vm` for the same reason. This VM is
  deliberately light — it holds no application data.

```
┌─────────────────────┐        ┌──────────────────────────┐        ┌─────────────────────────────┐
│    monitoring-vm     │        │        infra-vm           │        │           app-vm            │
│  (4 vCPU/4GB/50GB)   │        │   (8 vCPU/16GB/350GB)     │        │   (16 vCPU/28GB/300GB)      │
│                      │        │                           │        │                              │
│  prometheus ─scrape──┼───────►│  node-exporter :9100      │        │  node-exporter :9100 ◄──────┼──scrape (prometheus)
│  grafana             │        │  cadvisor      :8080      │◄───────┼──scrape (prometheus)         │
│  blackbox-exporter   │        │                           │        │  cadvisor      :8080         │
│      │               │        │  mongodb    :27017 ◄──────┼────────┼──(oms-admin, fix-initiator,  │
│      │ probe (HTTPS) │        │  postgres   :5432  ◄──────┼────────┼── itch-*)                    │
│      ▼               │        │  fix-cache  :16379 ◄──────┼────────┼──                             │
│  public domains       │        │  itch-cache :16380 ◄──────┼────────┼──                             │
│  (via nginx on        │        │  oms-cache  :16381 ◄──────┼────────┼──                             │
│   app-vm)             │        │                           │        │  kafka :9092 (local only)    │
└──────────┬────────────┘        └───────────────────────────┘        │  kafka-exporter :9308 ◄───────┼──scrape (prometheus)
           │                                                          │  nginx :80 ◄──────────────────┼── internet (via Cloudflare)
           └──────────────────────── scrape (:9308) ───────────────────►                              │
                                                                       └──────────────────────────────┘
```

## Before deploying

1. **Provision 3 VMs** to the spec above, on a private network (VPC /
   private LAN) so they can reach each other's DB/exporter ports without
   traversing the public internet. Record each VM's private IP.
2. **Fill in every `.env.example` → `.env`**, replacing:

   Run `app-vm/scripts/setup.sh` and `infra-vm/scripts/setup.sh` first —
   each copies that VM's own `*.env.example` files into place without
   touching a file that already exists (pass `--force` to regenerate from
   the template anyway), then prints exactly which of the newly-created
   files still contain a placeholder. It never invents secrets or IPs —
   you still edit the values below by hand. `monitoring-vm` has no
   `setup.sh`: it has a single env var, just `cp env/monitoring.env.example
   env/monitoring.env` and set `GRAFANA_ADMIN_PASSWORD` directly.

   `app-vm/configs/` (`config.yml`, `fix-client.cfg`, `spec/*`) isn't
   templated by `setup.sh` — fill those in by hand too (see step 4 below
   for `fix-client.cfg`).
   - `<INFRA_VM_PRIVATE_IP>` / `<APP_VM_PRIVATE_IP>` — the private IPs
     from step 1.
   - `<CHANGE_ME>` — **generate fresh secrets.** Do not reuse UAT's
     credentials in prod.
   - `<PROD_DOMAIN_*>` — the real production domains.
   - Redis/Mongo/Postgres passwords must match **exactly** between
     `infra-vm/env/infra.env` and every app-vm/monitoring-vm file that
     references them (called out in each `.example` file).
3. **Firewall rules** (per VM's security group / ufw):
   - `infra-vm`: allow 27017, 5432, 16379-16381 from `app-vm`'s IP only;
     allow 9100, 8080 from `monitoring-vm`'s IP only.
   - `app-vm`: allow 9100, 8080, 9308 from `monitoring-vm`'s IP only;
     allow 80/443 from the internet (or from Cloudflare's ranges, same as
     UAT — TLS is terminated at Cloudflare, not here).
   - `monitoring-vm`: allow 3005 (Grafana) from admin IPs / VPN only —
     never expose it publicly. 9090 (Prometheus) similarly restricted.
4. Confirm `app-vm/configs/fix-client.cfg`'s exchange endpoint is the real
   prod endpoint (not a sandbox) before starting `fix-initiator` — same
   warning as UAT's `README.md`.

## Deploy order

```bash
# 1. Infra VM first — everything else depends on it being reachable.
ssh <infra-vm>
cd prod/infra-vm && ./scripts/setup.sh && ./scripts/up.sh

# 2. App VM — brings up Kafka + all apps + nginx + local monitoring agents.
ssh <app-vm>
cd prod/app-vm && ./scripts/setup.sh && ./scripts/up-all.sh

# 3. Monitoring VM last, once it has real targets to scrape.
ssh <monitoring-vm>
cd prod/monitoring-vm && ./scripts/up.sh
```

`setup.sh` (`app-vm`, `infra-vm` only) materializes `.env` files from their
committed templates — run it, fill in the placeholders it reports, then run
`up.sh` (or `up-all.sh`).

Install each VM's cron schedule once deployed:
`infra-vm/scripts/install-cron.sh` (backups + safety-net restart) and
`app-vm/scripts/install-cron.sh` (safety-net restart + log rotation).

## Backups

Same tooling as UAT, run from `infra-vm/`:

```bash
infra-vm/scripts/backup-mongo.sh
infra-vm/scripts/backup-postgres.sh
```

Output goes to `infra-vm/backups/` (gitignored — real data) with 7-day
retention by default (`RETENTION_DAYS`). Restore with the matching
`restore-*.sh` script.

## Known limitation of this layout

Docker Compose's `depends_on: condition: service_healthy` only works
within one compose project. Since `mongodb`/`postgres`/the Redis caches
now live on a different VM from the containers that use them, the app-vm
compose files can't express that dependency in Compose itself — they
just point at `infra-vm`'s private IP via env vars. **Always start
`infra-vm` first and confirm it's healthy** (`docker compose ps` there)
before starting `app-vm`; a few services (`oms-admin`'s
`create_kafka_topics`/`migrate` at container start) will fail fast if the
DB isn't reachable yet.
