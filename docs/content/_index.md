---
title: kurly
description: A Jsonnet library of composable Kubernetes workload recipes.
---

kurly is a Jsonnet library of Kubernetes workload recipes. Start from a base
kind — `http`, `worker`, `cron`, `daemon` — and add capabilities as composable
`+` features: storage, config, exposure, security hardening, and more. Each
feature is a small mixin, so they compose in any order and multiply into many
workloads.

The **[Assembler](/assembler/)** lets you start from a published workload, add
features by clicking, wire each input as a hard-coded value or a pass-through
parameter, and copy out the Jsonnet snippet and JaaS manifests to deploy it.
