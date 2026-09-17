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
- **`monitoring-vm/`** — Prometheus, Grafana, blackbox-exporter, Loki.
  node-exporter, cadvisor, and Grafana Alloy run **locally** on `infra-vm`
  and `app-vm` instead (that's the standard Prometheus/Loki pattern —
  agents run next to what they measure/collect). Prometheus scrapes the
  exporters remotely from here; Alloy runs the other direction, pushing
  each VM's Docker container logs to Loki here. kafka-exporter is
  co-located with Kafka on `app-vm` for the same reason as the other
  exporters. This VM is deliberately light — it holds no application
  data, only metrics/log storage.

  Loki + Alloy are the log pipeline (`Alloy → Loki`) for this stack;
  they're deployed now, ahead of any log-consuming tooling, so logs are
  already centralized when that's added later. Alloy (not Promtail) is
  used here since Promtail is Grafana's deprecated log shipper — Alloy is
  its replacement and can also collect metrics/traces later if this
  stack adds Tempo.

```
┌─────────────────────┐        ┌──────────────────────────┐        ┌─────────────────────────────┐
│    monitoring-vm     │        │        infra-vm           │        │           app-vm            │
│  (4 vCPU/4GB/50GB)   │        │   (8 vCPU/16GB/350GB)     │        │   (16 vCPU/28GB/300GB)      │
│                      │        │                           │        │                              │
│  prometheus ─scrape──┼───────►│  node-exporter :9100      │        │  node-exporter :9100 ◄──────┼──scrape (prometheus)
│  grafana             │        │  cadvisor      :8080      │◄───────┼──scrape (prometheus)         │
│  blackbox-exporter   │        │  alloy         :12345     │◄───────┼──scrape (prometheus)         │
│  loki       :3100 ◄──┼────────┼──push (alloy)             │        │  cadvisor      :8080         │
│      │           ▲   │        │                           │        │  alloy         :12345        │
│      │           └───┼────────┼───────────────────────────┼────────┼──push (alloy)                 │
│      │ probe (HTTPS) │        │  mongodb    :27017 ◄──────┼────────┼──(oms-admin, fix-initiator,  │
│      ▼               │        │  postgres   :5432  ◄──────┼────────┼── itch-*)                    │
│  public domains       │        │  fix-cache  :16379 ◄──────┼────────┼──                             │
│  (via nginx on        │        │  itch-cache :16380 ◄──────┼────────┼──                             │
│   app-vm)             │        │  oms-cache  :16381 ◄──────┼────────┼──                             │
│                      │        │                           │        │  kafka :9092 (local only)    │
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
   - `<MONITORING_VM_PRIVATE_IP>` in `app-vm/monitoring/config.alloy` and
     `infra-vm/monitoring/config.alloy` — same hand-edit as
     `prometheus.yml`'s IP placeholders (no env-var substitution here
     either).
3. **Firewall rules** (per VM's security group / ufw):
   - `infra-vm`: allow 27017, 5432, 16379-16381 from `app-vm`'s IP only;
     allow 9100, 8080, 12345 from `monitoring-vm`'s IP only; allow
     OUTBOUND 3100 to `monitoring-vm`'s IP (alloy's log push).
   - `app-vm`: allow 9100, 8080, 9308, 12345 from `monitoring-vm`'s IP
     only; allow OUTBOUND 3100 to `monitoring-vm`'s IP (alloy's log
     push); allow 80/443 from the internet (or from Cloudflare's ranges,
     same as UAT — TLS is terminated at Cloudflare, not here).
   - `monitoring-vm`: allow 3005 (Grafana) from admin IPs / VPN only —
     never expose it publicly. 9090 (Prometheus) similarly restricted.
     Allow INBOUND 3100 (Loki) from `infra-vm`'s and `app-vm`'s IPs only.
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
