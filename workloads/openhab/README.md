<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# openhab

[openHAB](https://www.openhab.org) — a vendor-neutral, self-hosted home-automation platform integrating a huge range of devices behind one engine, UI and rule system. A `kurly.http` workload on the official image; its three persistent directories each get their own PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openhab = import 'github.com/metio/kurly/workloads/openhab/server.libsonnet';
kurly.list(openhab())
```

openHAB keeps config at `/openhab/conf`, runtime userdata at `/openhab/userdata`, and add-ons at `/openhab/addons`, so the workload composes `kurly.store` **three times** (sized by `confSize`/`userdataSize`/`addonsSize`), one PVC each. USB/serial radios are hardware and not modelled — use a network coordinator. All volumes are ReadWriteOnce, so **one replica, recreated**. Serves on `:8080`.
