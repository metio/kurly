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
}
