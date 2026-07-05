// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// migrations: recipes for authoring a stageset-controller migration ladder —
// the serialized []Migration a StageSet consumes via spec.migrationsSourceRef.
// A ladder is a plain Jsonnet array of migration(...) calls; the workload
// artifact pipeline packs it into its own layer of the workload's OCI image
// (media type application/vnd.metio.migrations.tar+gzip).
//
// Migrations are version-gated action ladders, not manifests: `to` is the
// exact version boundary the migration crosses up to, `from` optionally
// constrains the currently deployed version (a semver constraint like
// ">=1.0.0, <2.0.0"), and `stage` anchors it before a named stage's
// pre-actions (omit to anchor before the first stage). Actions are
// stageset-controller Action objects (job / delete / apply / patch / http /
// wait) passed through verbatim — their schema is owned by
// stageset-controller, see its StageSet API reference.
{
  migration(name, to, from=null, stage=null, actions=[])::
    std.prune({
      name: name,
      to: to,
      from: from,
      stage: stage,
      actions: actions,
    }),
}
