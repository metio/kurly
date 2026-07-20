<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# phpmyadmin

[phpMyAdmin](https://www.phpmyadmin.net) — the classic web UI for administering MySQL and MariaDB. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local phpmyadmin = import 'github.com/metio/kurly/workloads/phpmyadmin/server.libsonnet';
kurly.list(phpmyadmin(dbHost='mysql'))
```

Point it at the MySQL/MariaDB host through `dbHost` (`PMA_HOST`). Serves on `:80`.
