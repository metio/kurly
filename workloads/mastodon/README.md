<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mastodon

[Mastodon](https://joinmastodon.org) — the leading self-hosted ActivityPub/Fediverse
microblogging platform. It runs as **three workloads** — a `web`/API server, a `streaming` server
for real-time timelines, and a `sidekiq` background worker — backed by an external PostgreSQL and
Redis, with media in S3-compatible object storage.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local web = import 'github.com/metio/kurly/workloads/mastodon/web.libsonnet';
local streaming = import 'github.com/metio/kurly/workloads/mastodon/streaming.libsonnet';
local sidekiq = import 'github.com/metio/kurly/workloads/mastodon/sidekiq.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='mastodon-db', database='mastodon')).items,
  kurly.list(web(localDomain='social.example.com')).items,
  kurly.list(streaming()).items,
  kurly.list(sidekiq()).items,
]))
```

`LOCAL_DOMAIN` is **baked into every `@handle` and cannot be changed** — set it deliberately. All
three stages share a Secret (`mastodon-secrets`) via `envFrom` holding the PostgreSQL/Redis
connection, `SECRET_KEY_BASE`, `OTP_SECRET`, the VAPID keys and the S3 settings — kurly authors
**no Secret**. The `web` stage serves on `:3000`, `streaming` on `:4000` (route
`/api/v1/streaming` to it), and `sidekiq` has no Service. Media goes to S3 (pair with
[seaweedfs](../seaweedfs/)), so all stages are stateless.
