// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Which SQL engines a workload's software can actually run on, keyed by workload
// id. Hand-written from each project's own documentation, one project at a time,
// with the source recorded beside it.
//
// WHY THIS IS NOT DERIVED, and not the same question as `requires.database`:
//
// Most of these apps take a DSN and do not care what answers it — gitea, drupal,
// mediawiki, vikunja, freshrss, shiori and lldap all run on either engine. What is
// rare is the app that CANNOT: wordpress, prestashop, piwigo, leantime and baikal
// are MySQL-bound, and a few others are PostgreSQL-bound because they use its
// extensions. So "which engine does this workload use" is mostly a question about
// kurly's own default rather than about the software, and the useful fact is the
// narrower one — what it is able to use.
//
// It decides money, which is why it is worth the reading. A portal with a shared
// PostgreSQL pool can put every dual-engine workload in it and quote a dedicated
// cluster only where the software genuinely forces one. Publishing a bare engine
// instead would send workloads to their own cluster because of a default in a
// kurly source file, and the customer would pay for it.
//
// EVIDENCE RULE: an entry exists only if the project's documentation says so, and
// `source` names where. A workload nobody has read the docs for is ABSENT, which
// reads as unknown — never as "PostgreSQL only" and never as a guess. lychee is
// absent for exactly that reason: its docs page 404s and its compose file shows a
// MariaDB, which is what it ships with rather than what it supports.
//
// Engine names are SPDX-style lowercase and match what a consumer routes on:
// postgresql, mysql (covering MariaDB, which no project here distinguishes for
// this purpose), sqlite, mssql, oracle, h2.

{
  answer: { supports: ['postgresql', 'mysql', 'sqlite'], source: 'https://answer.apache.org/docs/installation/' },
  baikal: { supports: ['mysql', 'sqlite'], source: 'https://sabre.io/baikal/install/' },
  drupal: { supports: ['mysql', 'postgresql', 'sqlite'], source: 'https://www.drupal.org/docs/getting-started/system-requirements/database-server-requirements' },
  freshrss: { supports: ['postgresql', 'mysql', 'sqlite'], source: 'https://freshrss.github.io/FreshRSS/en/admins/02_Prerequisites.html' },
  gitea: { supports: ['postgresql', 'mysql', 'sqlite', 'mssql'], source: 'https://docs.gitea.com/installation/database-prep' },
  guacamole: { supports: ['mysql', 'postgresql', 'mssql'], source: 'https://guacamole.apache.org/doc/gug/jdbc-auth.html' },
  leantime: { supports: ['mysql'], source: 'https://github.com/Leantime/leantime' },
  lldap: { supports: ['sqlite', 'mysql', 'postgresql'], source: 'https://github.com/lldap/lldap' },
  mediawiki: { supports: ['mysql', 'postgresql', 'sqlite'], source: 'https://www.mediawiki.org/wiki/Compatibility' },
  // Oracle is supported too, but only under Nextcloud Enterprise, so it is not a
  // thing this catalogue's consumers can route to.
  nextcloud: { supports: ['mysql', 'postgresql'], source: 'https://docs.nextcloud.com/server/latest/admin_manual/configuration_database/linux_database_configuration.html' },
  piwigo: { supports: ['mysql'], source: 'https://piwigo.org/guides/install/requirements' },
  prestashop: { supports: ['mysql'], source: 'https://devdocs.prestashop-project.org/9/basics/installation/' },
  rundeck: { supports: ['mysql', 'postgresql', 'mssql', 'oracle', 'h2'], source: 'https://docs.rundeck.com/docs/administration/configuration/database/' },
  shiori: { supports: ['sqlite', 'postgresql', 'mysql'], source: 'https://github.com/go-shiori/shiori' },
  traccar: { supports: ['postgresql', 'mysql', 'mssql'], source: 'https://www.traccar.org/documentation/' },
  vikunja: { supports: ['sqlite', 'mysql', 'postgresql'], source: 'https://vikunja.io/docs/config-options/' },
  wordpress: { supports: ['mysql'], source: 'https://wordpress.org/about/requirements/' },
}
