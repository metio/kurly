// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Software this catalogue will not carry, and why. catalog.jsonnet REFUSES TO
// BUILD if an id named here reappears in annotations.libsonnet, so a workload
// removed on purpose cannot drift back in unnoticed — which is the whole point of
// writing the decision down rather than deleting a directory and hoping.
//
// THE LINE: kurly packages software whose SOURCE is published. That is narrower
// than "open source" in one direction and wider in another, and both are
// deliberate:
//
//   - Source-available licences STAY. BUSL, SSPL, Elastic, PolyForm and the
//     various sustainable-use licences are not OSI-approved, and 13 workloads
//     carry one. Their source is published, they are self-hostable, and the
//     catalogue already says `licenseOsiApproved: false` so a consumer selling
//     open source can see exactly what it is looking at. Removing them would be
//     deciding somebody else's licensing policy for them.
//   - `licenseOsiApproved` is NOT the test. privatebin is zlib-acknowledgement,
//     which SPDX does not list as OSI-approved and which is plainly free
//     software. A flag derived from a list is evidence, not a verdict.
//
// What is excluded is software with no published source at all.
//
// REMOVING SOMETHING DOES NOT UNPUBLISH IT: images already released under
// ghcr.io/metio/kurly/workloads/<name> stay where they are, and a consumer pinning
// one by digest is unaffected. This list stops the catalogue carrying it, nothing
// more.
{
  // Proprietary media servers and a proprietary sync tool. Each publishes a
  // container image and no source, so the `upstream` field a consumer would use to
  // read, audit or fund the software has nothing to point at — the absence is not
  // a gap in kurly's annotations, it is the shape of the thing.
  emby: { reason: 'no-published-source', note: 'proprietary (LicenseRef-Proprietary); no published source repository' },
  plex: { reason: 'no-published-source', note: 'proprietary (LicenseRef-Proprietary); no published source repository' },
  'resilio-sync': { reason: 'no-published-source', note: 'proprietary (LicenseRef-Proprietary); no published source repository' },

  // Licences that forbid, or are designed to forbid, exactly what a hosting portal
  // does: offer the software as a service to third parties. SSPL and the
  // sustainable-use and commons-clause-style licences say so outright; BUSL says it
  // for a term of years; Elastic-2.0 forbids providing the software "to others as a
  // managed service". Whatever a court would make of each, the intent is not in
  // doubt, and packaging them for a portal to sell would be working against their
  // authors' stated wishes.
  //
  // Note this is a decision about HOSTING them commercially, not a judgement on the
  // licences. Anyone may still run these themselves; kurly simply is not the thing
  // that helps them do it.
  browserless: { reason: 'licence-forbids-saas', note: 'SSPL-1.0 (or a commercial licence); forbids offering the software as a service' },
  bugsink: { reason: 'licence-forbids-saas', note: 'PolyForm Shield 1.0.0; forbids use in a competing product or service' },
  directus: { reason: 'licence-forbids-saas', note: 'BUSL-1.1; forbids offering the software as a service for the licence term' },
  dragonfly: { reason: 'licence-forbids-saas', note: 'BUSL-1.1; forbids offering the software as a service for the licence term' },
  emqx: { reason: 'licence-forbids-saas', note: 'BUSL-1.1; forbids offering the software as a service for the licence term' },
  invoiceninja: { reason: 'licence-forbids-saas', note: 'Elastic-2.0; forbids providing the software to others as a managed service' },
  mongo: { reason: 'licence-forbids-saas', note: 'SSPL-1.0; forbids offering the software as a service without releasing the service source' },
  'mongodb-cluster': { reason: 'licence-forbids-saas', note: 'SSPL-1.0; same, via the operator that runs it' },
  n8n: { reason: 'licence-forbids-saas', note: 'n8n Sustainable Use Licence; forbids offering the software as a service' },
  nocodb: { reason: 'licence-forbids-saas', note: 'NocoDB Sustainable Use Licence; forbids offering the software as a service' },
  outline: { reason: 'licence-forbids-saas', note: 'BUSL-1.1; forbids offering the software as a service for the licence term' },
  planka: { reason: 'licence-forbids-saas', note: 'PLANKA Community licence; forbids offering the software as a service' },

  // Software whose OWN authors sell hosting for it. A portal charging to host these
  // competes with the project it depends on, and takes the money that funds it —
  // which is the opposite of helping. Each entry names the offering and where it
  // was read, because "upstream sells hosting" is a claim about somebody else's
  // business and goes stale.
  //
  // A THIRD PARTY hosting it is not this: elest.io and a dozen VPS shops sell most
  // of the catalogue, and that takes nothing from the authors. What is excluded is
  // the project's own paid service.
  'cal-com': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (cal.com paid plans) — https://cal.com/pricing' },
  clickhouse: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (ClickHouse Cloud) — https://clickhouse.com/cloud' },
  ghost: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Ghost Pro) — https://ghost.org/pricing/' },
  gitea: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Gitea Cloud) — https://about.gitea.com/pricing' },
  glitchtip: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (app.glitchtip.com) — https://glitchtip.com/pricing' },
  grafana: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Grafana Cloud) — https://grafana.com/products/cloud/' },
  healthchecks: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (healthchecks.io, by the project authors) — https://healthchecks.io/pricing/' },
  influxdb: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (InfluxDB Cloud) — https://www.influxdata.com/products/influxdb-cloud/' },
  matomo: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Matomo Cloud) — https://matomo.org/pricing/' },
  meilisearch: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Meilisearch Cloud) — https://www.meilisearch.com/pricing' },
  metabase: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Metabase Cloud) — https://www.metabase.com/pricing/' },
  miniflux: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (miniflux.app, $15/year) — https://miniflux.app/hosting.html' },
  mattermost: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Mattermost Cloud) — https://mattermost.com/pricing/' },
  odoo: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Odoo Online / Odoo.sh) — https://www.odoo.com/pricing' },
  openproject: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (OpenProject cloud) — https://www.openproject.org/pricing/' },
  sonarqube: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (SonarQube Cloud) — https://www.sonarsource.com/products/sonarcloud/' },
  typesense: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Typesense Cloud) — https://cloud.typesense.org/' },
  umami: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Umami Cloud) — https://umami.is/pricing' },

  // Second pass over the same test, each checked against the project's own site.
  anythingllm: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (AnythingLLM cloud, $50/mo) — https://anythingllm.com/pricing' },
  baserow: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Baserow Premium/Advanced) — https://baserow.io/pricing' },
  documenso: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Documenso cloud plans) — https://documenso.com/pricing' },
  formbricks: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Formbricks Cloud) — https://formbricks.com/pricing' },
  grist: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Grist Labs cloud plans) — https://www.getgrist.com/pricing/' },
  linkwarden: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Linkwarden cloud, $3/mo) — https://linkwarden.app/pricing' },
  mariadb: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (MariaDB Cloud) — https://mariadb.com/products/skysql/' },
  mysql: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Oracle MySQL HeatWave Service) — https://www.oracle.com/mysql/' },
  ntfy: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (ntfy.sh paid plans, by the author) — https://ntfy.sh/' },
  openobserve: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (OpenObserve Cloud) — https://openobserve.ai/pricing' },
  penpot: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Penpot paid tiers) — https://penpot.app/pricing' },
  qdrant: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Qdrant Cloud) — https://qdrant.tech/pricing/' },
  redis: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Redis Cloud) — https://redis.io/pricing/' },
  teable: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Teable Pro/Business) — https://teable.ai/pricing' },
  twenty: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Twenty cloud, $9/user/mo) — https://twenty.com/pricing' },
  victoriametrics: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (VictoriaMetrics Cloud) — https://victoriametrics.com/products/cloud/' },

  // Third pass, over a batch of candidates that reached triage before anybody
  // read their pricing pages. Seven of eleven failed this test, which is the
  // argument for reading them FIRST: each of these would otherwise have been
  // authored, catalogued and booted before anyone noticed it should not be here.
  bytebase: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Bytebase Cloud, $20/user/mo at cloud.bytebase.com) — https://www.bytebase.com/pricing/' },
  lago: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Lago Premium, cloud deployment) — https://www.getlago.com/pricing' },
  mathesar: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Mathesar Cloud, run by the same nonprofit that develops it) — https://mathesar.org/' },
  opnform: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (OpnForm cloud, $25-220/mo) — https://opnform.com/pricing' },
  plane: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Plane cloud, $6-13/seat/mo) — https://plane.so/pricing' },
  taiga: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (tree.taiga.io, €5-60/mo) — https://www.taiga.io/deployment-pricing-options/' },
  // The one in this batch whose evidence is weaker than the rest, recorded as such
  // rather than tidied up. Datasette Cloud is the author's own SaaS built on the
  // project — "the SaaS platform built on the Datasette open source project" in its
  // own words — but it published no pricing page when this was read, so the paid
  // plans every other entry here cites could not be shown. It is excluded on what
  // the bar is FOR (carrying it competes with the person who wrote it) rather than
  // on a price list.
  datasette: { reason: 'upstream-sells-hosting', note: "upstream sells hosting (Datasette Cloud, the author's own SaaS built on the project; no public pricing at time of reading) — https://www.datasette.cloud/" },

  // Fourth pass, working awesome-selfhosted from the most-starred end. Every one
  // of the first six checked sells its own cloud, which is worth recording as a
  // pattern rather than six separate facts: the top of that list by popularity is
  // largely commercial open source whose business IS hosting. Popularity is
  // therefore a poor way to choose what to carry here, and the carryable software
  // sits further down.
  affine: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (AFFiNE cloud, $6.75/mo) — https://affine.pro/pricing' },
  appflowy: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (AppFlowy cloud, $10-12.50/user/mo) — https://appflowy.com/pricing' },
  appwrite: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Appwrite Cloud, from $25/mo) — https://appwrite.io/pricing' },
  discourse: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Discourse hosting, $100-500/mo) — https://www.discourse.org/pricing' },
  hoppscotch: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Hoppscotch Organization, $6/user/mo) — https://hoppscotch.com/pricing' },
  strapi: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Strapi Cloud, $35-450/project/mo) — https://strapi.io/pricing-cloud' },
  flipt: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Flipt Pro cloud, $200/mo) — https://flipt.io/pricing' },
  'tileserver-gl': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (MapTiler Cloud, the maps API by the same company that maintains tileserver-gl) — https://www.maptiler.com/cloud/' },
  onetimesecret: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Onetime Secret Identity Plus, EUR 35/mo) — https://onetimesecret.com/en/pricing' },

  // Projects that run a FREE instance of their own software. Not a criticism of
  // any of them — the opposite: they have already given away what a hosting
  // offer would sell, at a price nothing undercuts. Carrying these would cost an
  // operator real work and hand a user nothing they cannot already have.
  ihatemoney: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free hosted instance for general use, funded by donations — https://ihatemoney.org' },
  screego: { reason: 'upstream-hosts-it-free', note: "upstream runs a free public instance — its README calls it a 'Demo / Public Instance' and screego keeps no state, so there is nothing a demo would reset — https://app.screego.net/" },
  wbo: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free instance whose state is persisted and whose boards are in general use, described as a demonstration server — https://wbo.ophir.dev' },

  // Upstream is no longer maintained. A catalogue that keeps offering an archived
  // project is selling something nobody will fix — every future CVE in it stays
  // open, and the operator who deployed it from here has no upstream to go to.
  //
  // This is checkable rather than remembered: gen-forge already asks each GitHub
  // repository about itself, and `archived` is one field further. Worth deriving
  // so the next one is caught rather than noticed.
  minio: { reason: 'upstream-archived', note: 'upstream archived on 2026-04-24 — https://github.com/minio/minio (repository is read-only)' },
  maybe: { reason: 'upstream-archived', note: 'upstream archived on 2025-07-24 — https://github.com/maybe-finance/maybe' },
  overseerr: { reason: 'upstream-archived', note: 'upstream archived on 2026-02-15 — https://github.com/sct/overseerr' },
  'pingvin-share': { reason: 'upstream-archived', note: 'upstream archived on 2026-05-18 — https://github.com/stonith404/pingvin-share' },
  readarr: { reason: 'upstream-archived', note: 'upstream archived on 2025-06-27 — https://github.com/Readarr/Readarr' },

  // Undeployable as packaged: an image it needs does not exist. Not a licence or a
  // maintenance judgement — the thing simply cannot start.
  bigcapital: { reason: 'undeployable', note: 'docker.io/bigcapitalhq/gateway does not exist (siblings server and webapp do); the workload cannot run without its gateway' },

  // Triaged from the awesome-selfhosted list. Each was rejected at gate 0,
  // before anything was authored, and the URL is the page the decision was
  // read from rather than an inference from the licence or the repository.
  aleph: { reason: 'upstream-archived', note: 'upstream archived — https://www.occrp.org/en/announcement/aleph-pro-frequently-asked-questions-on-the-future-of-occrps-investigative-data-platform' },
  asciinema: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://asciinema.org/' },
  bentopdf: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://www.bentopdf.com/' },
  chartdb: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://chartdb.io/pricing' },
  dawarich: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://dawarich.app/' },
  donetick: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://donetick.com' },
  languagetool: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://languagetool.org/premium' },
  'libre-translate': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://portal.libretranslate.com' },
  linkace: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://hosting.linkace.org/' },
  misago: { reason: 'no-published-source', note: 'no image built from the published source — https://github.com/rafalp/misago_docker/blob/master/docker-compose.yaml' },
  movim: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://movim.eu/' },
  myip: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://github.com/jason5ng32/MyIP' },
  octoprint: { reason: 'undeployable', note: 'needs hardware a cluster cannot give it — https://github.com/OctoPrint/octoprint-docker' },
  openemr: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://www.open-emr.org/blog/openemr-offers-panel-of-turn-key-solutions-with-amazons-cloud-services/' },
  'reactive-resume': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://rxresu.me/' },
  rsshub: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://docs.rsshub.app' },
  ryot: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://ryot.io/terms/' },
  saltcorn: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://saltcorn.com/tenant/create' },
  wakapi: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://wakapi.dev' },
  hasura: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Hasura Cloud) — https://hasura.io/pricing' },
  // Triaged from selfhost.directory's Kubernetes-platform list. The rest of that
  // batch passed this gate — a paid SELF-HOSTED licence is not a hosting offer,
  // and dagu, imgproxy, semaphore-ui, onedev, sablier and krakend all sell one.
  'kill-bill': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Aviate, "cloud-hosted, auto-scaling, monitoring included", built on the Kill Bill core by the same people) — https://killbill.io/' },
  azimutt: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (azimutt.app Solo $7/mo, Team $35/user/mo; self-hosting is an Enterprise option) — https://azimutt.app/pricing' },

  // Working selfhost.directory's Kubernetes list downward by score. Every entry
  // below was read from the project's own pricing page, and every one of them
  // sells its own managed service — the same pattern the fourth pass found in
  // awesome-selfhosted, and the reason the top of a popularity ranking is a poor
  // place to look for software this catalogue can carry.
  netdata: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Netdata Cloud SaaS, $4.50/node/mo Business) — https://www.netdata.cloud/pricing/' },
  temporal: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Temporal Cloud, from $100/mo) — https://temporal.io/pricing' },
  signoz: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (SigNoz Cloud, from $49/mo plus ingest) — https://signoz.io/pricing/' },
  chatwoot: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Chatwoot cloud, $19-99/agent/mo) — https://www.chatwoot.com/pricing' },
  posthog: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (PostHog Cloud, usage-based) — https://posthog.com/pricing' },
  thingsboard: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (ThingsBoard Cloud, $49-749/mo) — https://thingsboard.io/pricing/' },
  kestra: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Kestra Cloud, the fully managed version; pay-as-you-scale, no published rates) — https://kestra.io/pricing' },
  livekit: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (LiveKit Cloud, $50-500/mo) — https://livekit.com/pricing' },
  infisical: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (app.infisical.com, $20-40/identity/mo) — https://infisical.com/pricing' },
  zitadel: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Zitadel Cloud, $100/mo PRO) — https://zitadel.com/pricing' },
  windmill: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (app.windmill.dev, from $120/mo plus per-seat) — https://www.windmill.dev/pricing' },
  trigger: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Trigger.dev cloud, $10-50/mo plus per-run) — https://trigger.dev/pricing' },
  juicefs: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (JuiceFS Cloud Service, beside the Community and Enterprise editions) — https://juicefs.com/en/' },
  weaviate: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Weaviate Cloud, $45-400/mo) — https://weaviate.io/pricing' },
  oneuptime: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (OneUptime cloud, $22-99/mo) — https://oneuptime.com/pricing' },
  cratedb: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (CrateDB Cloud, from $0.073/hour) — https://cratedb.com/pricing' },
  memgraph: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Memgraph Cloud, AWS-hosted managed instances) — https://memgraph.com/pricing' },
  openreplay: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (OpenReplay Dedicated, "fully managed by OpenReplay", from $199/mo) — https://openreplay.com/pricing/' },
  vendure: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Vendure Cloud, quoted per project) — https://www.vendure.io/pricing' },
  hatchet: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Hatchet cloud, $500-1000/mo plus per-run) — https://hatchet.run/pricing' },
  keep: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Keep Cloud at platform.keephq.dev, $199/mo Growth) — https://keephq.dev/pricing' },
  dify: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Dify Cloud, $590-1590 per workspace/year) — https://dify.ai/pricing' },
  opik: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Comet runs Opik in the cloud, $19/mo Pro) — https://www.comet.com/site/pricing/' },
  'flowise-ai': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (cloud.flowiseai.com, $35-65/mo) — https://flowiseai.com/' },
  'onyx-community-edition': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Onyx cloud, $20/user/mo Business) — https://www.onyx.app/pricing' },
  timescaledb: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Tiger Cloud, from $30/mo) — https://www.tigerdata.com/pricing' },
  // The client daemon is free and the coordination plane it cannot work without
  // is the paid product, so hosting the one means selling a front end for the
  // other. Recorded under the same reason because the distinction does not change
  // what a consumer should do with it.
  tailscale: { reason: 'upstream-sells-hosting', note: 'upstream sells the hosted coordination service the client requires (Personal/Standard/Premium/Enterprise plans); the container here is only the node agent — https://tailscale.com/pricing' },
  hyperdx: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (HyperDX cloud, $20/mo Starter plus per-GB) — https://www.hyperdx.io/pricing' },
  parseable: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Parseable Cloud, $0.39/GB ingested) — https://www.parseable.com/pricing' },
  cerbos: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Cerbos Hub, $25-933/mo) — https://www.cerbos.dev/pricing' },
  rudderstack: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (RudderStack cloud, $265/mo Growth) — https://www.rudderstack.com/pricing/' },
  lightdash: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Cloud Pro, $3000/mo) — https://www.lightdash.com/pricing' },
  openmeter: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (OpenMeter Cloud, now Konnect Metering & Billing; no published rates) — https://openmeter.io/pricing' },
  meteroid: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Meteroid cloud, 0.5% of managed revenue or EUR 219/mo) — https://meteroid.com/pricing' },
  bunkerweb: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (BunkerWeb CLOUD, "fully managed BunkerWeb (SaaS)", from EUR 639/mo) — https://www.bunkerweb.io/pricing' },
  gravitl: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Netmaker SaaS, usage-based per device/network/user) — https://www.netmaker.io/pricing' },
  terrateam: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Terrateam Pro, $12,000/yr, cloud or self-hosted) — https://www.terrateam.io/pricing' },
  // OpenFaaS passes the hosting test — the paid tiers are self-hosted — and fails
  // on the licence instead, which is why both gates exist. The Community Edition
  // EULA caps commercial use at one installation per company for 60 days and says
  // the software "cannot be resold, distributed to, or installed for a client for
  // commercial purposes", which is exactly what a hosting portal does.
  faas: { reason: 'licence-forbids-saas', note: 'OpenFaaS CE EULA: commercial use limited to one installation per company for 60 days, and no installation for a client for commercial purposes — https://github.com/openfaas/faas/blob/master/EULA.md' },
  convoy: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Convoy Cloud, "we handle hosting, scaling, and uptime") — https://www.getconvoy.io/pricing' },
  rivet: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Rivet Cloud, $20-200/mo plus usage) — https://www.rivet.dev/pricing' },
  // Grafana Cloud sells each of these as a managed service in its own right, the
  // same test grafana itself already failed. Alloy is deliberately absent: it is
  // an agent that ships data TO a backend, so running one competes with nothing.
  grafanamimir: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Grafana Cloud Metrics, "fully-managed... metrics service", from $6.50/1k series) — https://grafana.com/pricing/' },
  pyroscope: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Grafana Cloud Profiles, "fully-managed continuous profiling", per-GB) — https://grafana.com/pricing/' },
  automq: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (AutoMQ cloud, $300/mo Pro plus per-GiB) — https://www.automq.com/pricing' },
  // Passes the hosting test and fails the licence one: Arize sells AX, a separate
  // product, and says Phoenix stays local — but Phoenix itself is Elastic-2.0,
  // which forbids providing the software to others as a managed service.
  // The container is MIT and the thing it runs is not: each of these packages a
  // proprietary payload it downloads or expects you to supply, so the source a
  // consumer would read, audit or fund is the wrapper rather than the software.
  // Same reasoning as emby and plex, one layer further out.
  macos: { reason: 'no-published-source', note: 'the image is a wrapper; the operating system it runs is proprietary Apple software — https://github.com/dockur/macos' },
  'virtual-dsm': { reason: 'no-published-source', note: 'the image is a wrapper; the DSM it runs is proprietary Synology software — https://github.com/vdsm/virtual-dsm' },
  satisfactory: { reason: 'no-published-source', note: 'the image is a wrapper; the Satisfactory dedicated server it runs is proprietary — https://github.com/wolveix/satisfactory-server' },
  'minecraft-bedrock-server': { reason: 'no-published-source', note: 'the image is a wrapper; the Bedrock dedicated server it runs is proprietary Mojang software — https://github.com/itzg/docker-minecraft-bedrock-server' },

  // Deployable somewhere, but not as a workload in a tenant's namespace.
  'nextcloud-aio-mastercontainer': { reason: 'undeployable', note: 'the AIO master container drives a Docker socket to start and manage sibling containers, which a cluster does not give it — the nextcloud workload is the one that runs here — https://github.com/nextcloud/all-in-one' },
  cozystack: { reason: 'undeployable', note: 'a Kubernetes distribution that installs and owns the whole cluster, not a workload inside one — https://cozystack.io' },
  castsponsorskip: { reason: 'undeployable', note: 'discovers Chromecasts by mDNS on the local network and needs the host network to see them — https://github.com/gabe565/CastSponsorSkip' },

  // Upstream has stopped. rexray's last commit is 2023 and its own README points
  // users elsewhere; magnetissimo's is 2024. Neither is marked archived on GitHub,
  // which is why the date is the evidence rather than the flag.
  rexray: { reason: 'upstream-archived', note: 'no commit since 2023-09-02; the CSI drivers it predates are what a cluster uses now — https://github.com/rexray/rexray' },
  magnetissimo: { reason: 'upstream-archived', note: 'no commit since 2024-01-19 — https://github.com/sergiotapia/magnetissimo' },
  'quant-ux': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free hosted instance anyone can sign up to — https://quant-ux.com/' },
  openlit: { reason: 'upstream-sells-hosting', note: 'upstream is launching hosting ("OpenLIT Cloud is the fully hosted version"; coming soon, rates unannounced) — https://openlit.io/pricing' },
  semaphore: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Semaphore cloud CI, pay-per-use compute, beside the Community Edition) — https://semaphore.io/pricing' },
  beam: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Beam serverless GPU and sandboxes, per-second billing plus $89/mo Team) — https://www.beam.cloud/pricing' },
  aisoc: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting ("start free and connect a source in minutes" beside a sovereign self-hosted deployment) — https://tryaisoc.com/' },
  'llm-gateway': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (llmgateway.io, 5% platform fee on credits) — https://llmgateway.io/pricing' },
  wundergraph: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Cosmo managed service, $3499/mo Scale) — https://www.wundergraph.com/pricing' },
  'big-agi': { reason: 'upstream-sells-hosting', note: 'upstream both runs a free hosted tier and sells Pro at $9/mo — https://big-agi.com/' },
  'domain-locker': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (domain-locker.com cloud, $5-20/mo) — https://domain-locker.com/about/pricing' },
  distr: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Distr Cloud, $80-160/mo and up) — https://distr.sh/pricing/' },
  probo: { reason: 'upstream-sells-hosting', note: 'upstream sells a managed programme run by its own compliance officers alongside the self-hosted deployment; no published rates — https://www.probo.com/' },
  datalens: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Yandex Cloud DataLens, $8.11/seat/mo) — https://yandex.cloud/en/services/datalens' },
  // Announced rather than running: the hosted tiers are described as coming, not
  // sold today. Recorded now because the decision does not change when they open,
  // and re-reading this page later is exactly the work the note exists to save.
  serviceradar: { reason: 'upstream-sells-hosting', note: 'upstream is launching hosting ("Hosted ServiceRadar Cloud is coming", Standard and Enterprise tiers) — https://serviceradar.cloud/' },
  'red-hat-quay': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Quay.io, "a fully-managed hosted container image registry", priced per private repository) — https://www.redhat.com/en/technologies/cloud-computing/quay' },
  boxyhq: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Ory Network, $770-9350/yr; BoxyHQ is now Ory Polis) — https://www.ory.com/pricing' },
  suna: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Kortix Team, $40/seat/mo with managed models) — https://www.kortix.com/pricing' },
  latitude: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Latitude Pro, $99/mo) — https://latitude.so/pricing' },
  traceloop: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Traceloop cloud, free tier plus Enterprise) — https://www.traceloop.com/pricing' },
  highlight: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Highlight cloud, $50-800/mo) — https://www.highlight.io/pricing' },
  superplane: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting ("Self-host or use the cloud"; no published rates at time of reading) — https://superplane.com/pricing' },
  fastgpt: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (cloud.fastgpt.io, CNY 99-599/mo) — https://fastgpt.io/price' },
  kaneo: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Kaneo Cloud, $40/yr Personal, $50/user/yr Team) — https://kaneo.app/pricing' },
  bagisto: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Bagisto Hosting, by Webkul who maintain it) — https://bagisto.com/en/cloud-hosting/' },
  // Weaker evidence than the rest, recorded as such: casdoor.ai links its
  // enterprise offering to casdoor.com, which is titled "Casdoor Identity Cloud",
  // and no pricing page was published when this was read. Excluded on what the bar
  // is FOR — carrying it competes with the people who wrote it — rather than on a
  // price list, the same way datasette is.
  casdoor: { reason: 'upstream-sells-hosting', note: "upstream sells hosting (Casdoor Identity Cloud, the project's own hosted offering; no public pricing at time of reading) — https://casdoor.com/" },
  'arize-phoenix': { reason: 'licence-forbids-saas', note: 'Elastic License 2.0; forbids providing the software to others as a managed service — https://github.com/Arize-ai/phoenix/blob/main/LICENSE' },
  bytechef: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (ByteChef cloud, $29-169/mo) — https://www.bytechef.io/pricing' },
  flowforge: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (FlowFuse Cloud instances; prices on request) — https://flowfuse.com/pricing/' },
  formance: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Formance Private Cloud, "provisions and manages a dedicated, single-tenant environment"; prices on request) — https://formance.com/pricing' },
  manyfold: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://manyfold.app/' },
  tolgee: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://tolgee.io/pricing' },
  'personal-management-system': { reason: 'no-published-source', note: 'no image built from the published source — https://github.com/Volmarg/personal-management-system' },
  'speed-test-by-openspeedtest': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://openspeedtest.com/' },
  globaleaks: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://www.globaleaks.org/' },
  farmos: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (farmOS.host, by the project) — https://farmos.org/hosting/' },
  // The declared licence is Apache-2.0 — in the OCI label AND in package.json
  // — and the LICENSE file appends a Commons Clause forbidding paid hosted or
  // managed services. Every source header says so; only the metadata does not.
  fredy: { reason: 'licence-forbids-saas', note: 'Apache-2.0 plus a Commons Clause forbidding paid hosted or managed services — https://github.com/orangecoding/fredy/blob/master/LICENSE' },
  aptabase: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Aptabase Cloud) — https://aptabase.com/pricing' },
  hemmelig: { reason: 'licence-forbids-saas', note: 'the licence forbids offering it as a service — https://github.com/HemmeligOrg/Hemmelig.app' },
  automad: { reason: 'licence-forbids-saas', note: 'the licence forbids offering it as a service — https://github.com/marcantondahmen/automad/blob/v2/LICENSE.md' },
  osem: { reason: 'no-published-source', note: 'no image built from the published source — https://github.com/openSUSE/osem' },
  claper: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://claper.co/en/' },
  superdesk: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://www.superdesk.org/offer/managed-services' },
  dpaste: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://dpaste.org/' },
  cloudlog: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://github.com/magicbug/Cloudlog#want-cloudlog-hosting' },
  para: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://paraio.org' },
  paaster: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://paaster.io' },
  papermerge: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://papermerge.com/join' },
  wingfit: { reason: 'licence-forbids-saas', note: 'the licence forbids offering it as a service — https://github.com/itskovacs/wingfit/blob/main/license.txt' },
  titra: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://titra.io/' },
  plugnmeet: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://www.plugnmeet.cloud' },
  'mirotalk-c2c': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://c2c.mirotalk.com' },
  readflow: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://about.readflow.app/terms' },
  gathio: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://gath.io/' },
  pastefy: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://github.com/interaapps/pastefy' },
  snikket: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://snikket.org/start/' },
  'f-droid': { reason: 'undeployable', note: 'needs something a cluster cannot give it — https://f-droid.org/docs/Installing_the_Server_and_Repo_Tools/' },
  'daily-stars-explorer': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://emanuelef.github.io/daily-stars-explorer' },
  foodsoft: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://foodcoops.net/foodsoft-hosting/' },
  socialhome: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://socialhome.network/nodeinfo/1.0' },
  '015': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://send.fudaoyuan.icu' },
  surmai: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://surmai.app/documentation/surmai-go' },
  'mere-medical': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://meremedical.co/' },
  ziit: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://github.com/0pandadev/ziit#how-to-use-ziit' },
  'gramps-web': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Gramps Web hosted plans) — https://www.grampsweb.org/install_setup/setup/' },
  'fmd-server': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://fmd-foss.org/docs/fmd-server/overview/' },
  amusewiki: { reason: 'no-published-source', note: 'no image built from the published source — https://github.com/melmothx/amusewiki' },
  inginious: { reason: 'undeployable', note: 'needs a Docker socket to run student code in sibling containers — https://github.com/INGInious/INGInious/blob/master/docker-compose.yml' },
  hiccup: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://test.designedbyashw.in/hiccup' },
  flexisip: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Linphone services) — https://www.linphone.org/en/services/' },
  homebutler: { reason: 'undeployable', note: 'needs host access for Wake-on-LAN and a Docker socket to manage services — https://github.com/Higangssh/homebutler' },
  tamari: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://tamariapp.com' },
  jarr: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://github.com/jaesivsm/JARR' },
  privydrop: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://www.privydrop.app' },
  localess: { reason: 'undeployable', note: 'needs Firebase (Auth, Firestore, Cloud Functions), which a cluster cannot supply — https://localess.org/docs/setup/docker' },
  'fork-recipes': { reason: 'no-published-source', note: 'no image built from the published source — https://hub.docker.com/u/mikebgrep' },
  nimbus: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://nimbus.turboot.com/' },
  foodcoopshop: { reason: 'no-published-source', note: 'no image built from the published source — https://github.com/foodcoopshop/foodcoopshop-docker' },
  'rero-ils': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (RERO ILS as a service) — https://www.rero.ch/en/products/ils' },
  tine: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://www.tine-groupware.de/shop' },
  trackwatch: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://trackwatch.emlopezr.com/' },
  'zero-totp': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://zero-totp.com' },
  plugnpin: { reason: 'undeployable', note: 'needs a Docker socket to read container labels — https://github.com/deepspace2/plugnpin' },
  lesma: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://lesma.eu' },
  'request-inbox': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://request-inbox.com/' },
  helium: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://www.heliumedu.com' },
  castopod: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Castopod Host) — https://castopod.com/en' },
  akkoma: { reason: 'no-published-source', note: 'no image built from the published source — https://docs.akkoma.dev/stable/installation/docker_en/' },
  haproxy: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (HAProxy Edge) — https://www.haproxy.com/products/haproxy-edge' },
  geeftlist: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://www.geeftlist.com/' },
  'kasm-workspaces': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://kasm.com/pricing' },
  lighttpd: { reason: 'no-published-source', note: 'no image built from the published source — https://www.lighttpd.net/' },
  piefed: { reason: 'no-published-source', note: 'no image built from the published source — https://codeberg.org/rimu/pyfedi/src/branch/main/INSTALL-docker.md' },
  pagure: { reason: 'no-published-source', note: 'no image built from the published source — https://github.com/Pagure/pagure' },
  mobilizon: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://mobilizon.org' },
  passit: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://passit.io/pricing/' },
  tooljet: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://tooljet.com/pricing' },
  appsmith: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://www.appsmith.com/pricing' },
  novu: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://novu.co/pricing/' },
  postiz: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://postiz.com' },
  hyperswitch: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://hyperswitch.io/pricing' },
  erpnext: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Frappe Cloud) — https://frappe.io/erpnext' },
  'jitsi-meet': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Jitsi as a Service) — https://jitsi.org/' },
  'eclipse-che': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://eclipse.dev/che/' },
  kong: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Kong Konnect) — https://konghq.com/pricing' },
  tyk: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Tyk Cloud) — https://tyk.io/pricing/' },
  bitwarden: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting — https://bitwarden.com/pricing/' },
  gitlab: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (GitLab.com) — https://about.gitlab.com/pricing/' },
  teleport: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Teleport Cloud) — https://goteleport.com/docs/get-started/deploy-cloud/' },
  pomerium: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Pomerium Zero) — https://www.pomerium.com/pricing' },
  puter: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (puter.com paid plans) — https://puter.com/' },
  mailcow: { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (mailcow: hosted) — https://mailcow.email/' },
  habitica: { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://habitica.com' },
  'countly-community-edition': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (Countly Enterprise) — https://count.ly/' },
  'sipcapture-homer': { reason: 'upstream-sells-hosting', note: 'upstream sells hosting (QXIP/HOMER cloud) — https://www.sipcapture.org/' },
  'uusec-waf': { reason: 'no-published-source', note: 'no image built from the published source — https://github.com/Safe3/uusec-waf' },
  'mirotalk-p2p': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://p2p.mirotalk.com' },
  'canary-tokens': { reason: 'upstream-hosts-it-free', note: 'upstream runs a free public instance — https://canarytokens.org' },
  openttd: { reason: 'no-published-source', note: 'no image built from the published source — https://wiki.openttd.org/en/Manual/Dedicated%20server' },
  sunshine: { reason: 'undeployable', note: 'streams a desktop session and needs a GPU and a display server — https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html' },
}
