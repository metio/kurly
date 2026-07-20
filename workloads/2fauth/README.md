<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# 2fauth

[2FAuth](https://github.com/Bubka/2FAuth) — a self-hosted web app to manage your TOTP/HOTP two-factor-authentication accounts and generate one-time codes. A `kurly.http` workload on the official image; with the default SQLite backend its database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local twofauth = import 'github.com/metio/kurly/workloads/2fauth/server.libsonnet';
kurly.list(twofauth(appUrl='https://2fa.example.com'))
```

`APP_KEY` (encrypts stored 2FA secrets) comes from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/2fauth` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8000`.
