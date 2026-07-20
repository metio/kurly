<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# jenkins

[Jenkins](https://www.jenkins.io) — the self-hosted automation server for building, testing and deploying software. A `kurly.http` workload on the official LTS image; `JENKINS_HOME` (jobs, plugins, config, history) on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local jenkins = import 'github.com/metio/kurly/workloads/jenkins/server.libsonnet';
kurly.list(jenkins())
```

Home at `/var/jenkins_home` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the UI on `:8080`; inbound agents connect over the same HTTP port (websocket).
