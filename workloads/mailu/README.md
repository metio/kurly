<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mailu

[Mailu](https://mailu.io/) — a full mail server: SMTP (Postfix), IMAP/POP3
(Dovecot), webmail (Roundcube), and antispam (Rspamd), administered through a web
UI. Six composable `kurly.http` stages that coordinate through a shared secret, a
shared domain, and one shared volume:

| Stage | Service | Role |
|---|---|---|
| `front` | nginx | the edge — terminates the mail protocols and web UI, proxies to the rest. **The only stage you expose.** |
| `admin` | admin | web admin, the internal API, the database, and the DKIM keys |
| `imap` | Dovecot | the mail store (maildirs) and local delivery |
| `smtp` | Postfix | the MTA |
| `antispam` | Rspamd | mail filtering and DKIM signing |
| `webmail` | Roundcube | the webmail client (optional) |

## Architecture: one instance, shared storage

Mailu is a **single-instance** mail server — the maildirs, the DKIM key, and the
database are local state that does not shard. Each stage is therefore **one
replica, recreated**, and the services share their coordinated data through **one
ReadWriteMany PersistentVolumeClaim** (`admin` writes the DKIM key at `/dkim`,
`antispam` reads it; each service mounts its own subpath). You provide that claim;
kurly does not mint it:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mailu-storage
spec:
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 20Gi
  storageClassName: your-rwx-class   # e.g. cephfs, nfs, efs
```

Mailu's images **run as root** (they bind privileged ports and `setuid`) and
**template their configuration into the root filesystem** at boot, so these stages
relax kurly's non-root and read-only-rootfs defaults — the hardening a mail server
cannot keep. They still drop all capabilities, block privilege escalation, keep the
seccomp profile, and run under their own ServiceAccount (so they admit under
[bollwerk](../../bollwerk/)).

## Compose

All six stages must share the same `namePrefix` (default `mailu`), `secretName`,
and `storageClaim` — that is how they find each other (peer Service names are
derived from `namePrefix`) and their shared state. Add a Redis with the
[valkey](../valkey/) `cache` stage named `mailu-cache` (it exposes a ClusterIP Service on :6379):

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local front = import 'github.com/metio/kurly/workloads/mailu/front.libsonnet';
local admin = import 'github.com/metio/kurly/workloads/mailu/admin.libsonnet';
local imap = import 'github.com/metio/kurly/workloads/mailu/imap.libsonnet';
local smtp = import 'github.com/metio/kurly/workloads/mailu/smtp.libsonnet';
local antispam = import 'github.com/metio/kurly/workloads/mailu/antispam.libsonnet';
local webmail = import 'github.com/metio/kurly/workloads/mailu/webmail.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

local d = 'example.com';
local h = ['mail.example.com'];

kurly.listOf(kurly.join([
  kurly.list(valkey(name='mailu-cache')).items,
  kurly.list(front(domain=d, hostnames=h)).items,
  kurly.list(admin(domain=d, hostnames=h)).items,
  kurly.list(imap(domain=d, hostnames=h)).items,
  kurly.list(smtp(domain=d, hostnames=h)).items,
  kurly.list(antispam(domain=d, hostnames=h)).items,
  kurly.list(webmail(domain=d, hostnames=h)).items,
]))
```

Each stage renders to its own `kind: List`, so in practice a consumer deploys each
as its own JaaS `JsonnetSnippet`/stageset stage; the snippet above is the all-in-one
render for reference.

Shared parameters (on every stage):

| Parameter | Default | Notes |
|---|---|---|
| `namePrefix` | `mailu` | peer Service names derive from it; keep it the same across stages |
| `domain` / `hostnames` | `example.com` / `[mail.example.com]` | your mail domain and its public hostnames |
| `secretName` | `mailu-secrets` | the Secret holding `SECRET_KEY` (read via `envFrom`) — see below |
| `storageClaim` | `mailu-storage` | the shared ReadWriteMany PVC |
| `subnet` | `10.0.0.0/8` | the trusted pod network (Mailu `SUBNET`); tighten to your pod CIDR |
| `redisAddress` | `mailu-cache` | the Redis/valkey Service |
| `resolverAddress` | unset | a recursive DNS resolver for DNSBL/DNSSEC (Mailu ships an `unbound`; leave unset to use cluster DNS) |

## The secret

kurly mints **no Secret**. Provide `mailu-secrets` carrying `SECRET_KEY` (a random
value ≥16 chars, stable for the life of the deployment — it protects auth cookies).
Fill it with [`kurly.externalSecret`](../../main.libsonnet) from your secret store.

## Exposing it

Expose **only `front`** — it fronts everything. Route its HTTP port through an
exposure, and its mail ports (`smtp`, `smtps`, `submission`, `imap`, `imaps`,
`pop3`, `pop3s`, `sieve`) as TCP through a LoadBalancer or Gateway TCPRoute:

```jsonnet
front(domain='example.com', hostnames=['mail.example.com'])
+ kurly.expose.ownGateway('mail.example.com', 'istio', tls='mailu-tls')
```

## Not included

ClamAV (antivirus), Radicale (webdav), the `unbound` resolver, and fetchmail are
Mailu options this recipe omits. Compose them as additional workloads and point
`ANTIVIRUS_ADDRESS` / `WEBDAV_ADDRESS` / `resolverAddress` at them through `env`.
