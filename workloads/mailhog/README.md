<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mailhog

[MailHog](https://github.com/mailhog/MailHog) — a self-hosted email-testing tool for developers: it captures the mail your apps send and shows it in a web inbox instead of delivering it. A **stateless** `kurly.http` workload on the official image (pinned by digest — Renovate maintains it).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mailhog = import 'github.com/metio/kurly/workloads/mailhog/server.libsonnet';
kurly.list(mailhog())
```

Apps send mail to its SMTP listener on `:1025` (needs an extra Service). Serves the web inbox on `:8025`.
