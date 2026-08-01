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
  emby: 'proprietary (LicenseRef-Proprietary); no published source repository',
  plex: 'proprietary (LicenseRef-Proprietary); no published source repository',
  'resilio-sync': 'proprietary (LicenseRef-Proprietary); no published source repository',

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
  browserless: 'SSPL-1.0 (or a commercial licence); forbids offering the software as a service',
  bugsink: 'PolyForm Shield 1.0.0; forbids use in a competing product or service',
  directus: 'BUSL-1.1; forbids offering the software as a service for the licence term',
  dragonfly: 'BUSL-1.1; forbids offering the software as a service for the licence term',
  emqx: 'BUSL-1.1; forbids offering the software as a service for the licence term',
  invoiceninja: 'Elastic-2.0; forbids providing the software to others as a managed service',
  mongo: 'SSPL-1.0; forbids offering the software as a service without releasing the service source',
  'mongodb-cluster': 'SSPL-1.0; same, via the operator that runs it',
  n8n: 'n8n Sustainable Use Licence; forbids offering the software as a service',
  nocodb: 'NocoDB Sustainable Use Licence; forbids offering the software as a service',
  outline: 'BUSL-1.1; forbids offering the software as a service for the licence term',
  planka: 'PLANKA Community licence; forbids offering the software as a service',

  // Software whose OWN authors sell hosting for it. A portal charging to host these
  // competes with the project it depends on, and takes the money that funds it —
  // which is the opposite of helping. Each entry names the offering and where it
  // was read, because "upstream sells hosting" is a claim about somebody else's
  // business and goes stale.
  //
  // A THIRD PARTY hosting it is not this: elest.io and a dozen VPS shops sell most
  // of the catalogue, and that takes nothing from the authors. What is excluded is
  // the project's own paid service.
  'cal-com': 'upstream sells hosting (cal.com paid plans) — https://cal.com/pricing',
  clickhouse: 'upstream sells hosting (ClickHouse Cloud) — https://clickhouse.com/cloud',
  ghost: 'upstream sells hosting (Ghost Pro) — https://ghost.org/pricing/',
  gitea: 'upstream sells hosting (Gitea Cloud) — https://about.gitea.com/pricing',
  glitchtip: 'upstream sells hosting (app.glitchtip.com) — https://glitchtip.com/pricing',
  grafana: 'upstream sells hosting (Grafana Cloud) — https://grafana.com/products/cloud/',
  healthchecks: 'upstream sells hosting (healthchecks.io, by the project authors) — https://healthchecks.io/pricing/',
  influxdb: 'upstream sells hosting (InfluxDB Cloud) — https://www.influxdata.com/products/influxdb-cloud/',
  matomo: 'upstream sells hosting (Matomo Cloud) — https://matomo.org/pricing/',
  meilisearch: 'upstream sells hosting (Meilisearch Cloud) — https://www.meilisearch.com/pricing',
  metabase: 'upstream sells hosting (Metabase Cloud) — https://www.metabase.com/pricing/',
  miniflux: 'upstream sells hosting (miniflux.app, $15/year) — https://miniflux.app/hosting.html',
  mattermost: 'upstream sells hosting (Mattermost Cloud) — https://mattermost.com/pricing/',
  odoo: 'upstream sells hosting (Odoo Online / Odoo.sh) — https://www.odoo.com/pricing',
  openproject: 'upstream sells hosting (OpenProject cloud) — https://www.openproject.org/pricing/',
  sonarqube: 'upstream sells hosting (SonarQube Cloud) — https://www.sonarsource.com/products/sonarcloud/',
  typesense: 'upstream sells hosting (Typesense Cloud) — https://cloud.typesense.org/',
  umami: 'upstream sells hosting (Umami Cloud) — https://umami.is/pricing',

  // Second pass over the same test, each checked against the project's own site.
  anythingllm: 'upstream sells hosting (AnythingLLM cloud, $50/mo) — https://anythingllm.com/pricing',
  baserow: 'upstream sells hosting (Baserow Premium/Advanced) — https://baserow.io/pricing',
  documenso: 'upstream sells hosting (Documenso cloud plans) — https://documenso.com/pricing',
  formbricks: 'upstream sells hosting (Formbricks Cloud) — https://formbricks.com/pricing',
  grist: 'upstream sells hosting (Grist Labs cloud plans) — https://www.getgrist.com/pricing/',
  linkwarden: 'upstream sells hosting (Linkwarden cloud, $3/mo) — https://linkwarden.app/pricing',
  mariadb: 'upstream sells hosting (MariaDB Cloud) — https://mariadb.com/products/skysql/',
  mysql: 'upstream sells hosting (Oracle MySQL HeatWave Service) — https://www.oracle.com/mysql/',
  ntfy: 'upstream sells hosting (ntfy.sh paid plans, by the author) — https://ntfy.sh/',
  openobserve: 'upstream sells hosting (OpenObserve Cloud) — https://openobserve.ai/pricing',
  penpot: 'upstream sells hosting (Penpot paid tiers) — https://penpot.app/pricing',
  qdrant: 'upstream sells hosting (Qdrant Cloud) — https://qdrant.tech/pricing/',
  redis: 'upstream sells hosting (Redis Cloud) — https://redis.io/pricing/',
  teable: 'upstream sells hosting (Teable Pro/Business) — https://teable.ai/pricing',
  twenty: 'upstream sells hosting (Twenty cloud, $9/user/mo) — https://twenty.com/pricing',
  victoriametrics: 'upstream sells hosting (VictoriaMetrics Cloud) — https://victoriametrics.com/products/cloud/',

  // Upstream is no longer maintained. A catalogue that keeps offering an archived
  // project is selling something nobody will fix — every future CVE in it stays
  // open, and the operator who deployed it from here has no upstream to go to.
  //
  // This is checkable rather than remembered: gen-forge already asks each GitHub
  // repository about itself, and `archived` is one field further. Worth deriving
  // so the next one is caught rather than noticed.
  minio: 'upstream archived on 2026-04-24 — https://github.com/minio/minio (repository is read-only)',
}
