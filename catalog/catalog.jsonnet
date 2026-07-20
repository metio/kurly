// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Generates catalog.json: the machine-readable model of kurly's public API the
// assembler UI (and any docs renderer) reads. The annotations carry the prose,
// parameter types, and composition facets; this file cross-checks them against
// the REAL exported fields of each library module and fails to render if the two
// diverge — so a feature added without an annotation, or an annotation left
// behind after a feature is removed, breaks the build rather than shipping a
// catalog that lies. Render from the repo root:
//
//   jsonnet -J vendor catalog/catalog.jsonnet > catalog/catalog.json
local expose = import '../lib/expose.libsonnet';
local features = import '../lib/features.libsonnet';
local migrations = import '../lib/migrations.libsonnet';
local security = import '../lib/security.libsonnet';
local main = import '../main.libsonnet';
local ann = import './annotations.libsonnet';

// Each workload stage, imported by the canonical path a consumer's snippet uses
// (resolved via the vendor/github.com/metio/kurly symlink check-catalog creates).
// A stage that is renamed or removed fails the import here; the reconcile below
// fails if this map and the annotations fall out of step.
local stageImports = {
  'tik/backend': import 'github.com/metio/kurly/workloads/tik/backend.libsonnet',
  'forgejo/server': import 'github.com/metio/kurly/workloads/forgejo/server.libsonnet',
  'vaultwarden/server': import 'github.com/metio/kurly/workloads/vaultwarden/server.libsonnet',
  'netbox/server': import 'github.com/metio/kurly/workloads/netbox/server.libsonnet',
  'netbox/worker': import 'github.com/metio/kurly/workloads/netbox/worker.libsonnet',
  'mailu/front': import 'github.com/metio/kurly/workloads/mailu/front.libsonnet',
  'mailu/admin': import 'github.com/metio/kurly/workloads/mailu/admin.libsonnet',
  'mailu/imap': import 'github.com/metio/kurly/workloads/mailu/imap.libsonnet',
  'mailu/smtp': import 'github.com/metio/kurly/workloads/mailu/smtp.libsonnet',
  'mailu/antispam': import 'github.com/metio/kurly/workloads/mailu/antispam.libsonnet',
  'mailu/webmail': import 'github.com/metio/kurly/workloads/mailu/webmail.libsonnet',
  'uptime-kuma/server': import 'github.com/metio/kurly/workloads/uptime-kuma/server.libsonnet',
  'actualbudget/server': import 'github.com/metio/kurly/workloads/actualbudget/server.libsonnet',
  'homebox/server': import 'github.com/metio/kurly/workloads/homebox/server.libsonnet',
  'expenseowl/server': import 'github.com/metio/kurly/workloads/expenseowl/server.libsonnet',
  'radicale/server': import 'github.com/metio/kurly/workloads/radicale/server.libsonnet',
  'znc/server': import 'github.com/metio/kurly/workloads/znc/server.libsonnet',
  'kanboard/server': import 'github.com/metio/kurly/workloads/kanboard/server.libsonnet',
  'paisa/server': import 'github.com/metio/kurly/workloads/paisa/server.libsonnet',
  'cryptpad/server': import 'github.com/metio/kurly/workloads/cryptpad/server.libsonnet',
  'baikal/server': import 'github.com/metio/kurly/workloads/baikal/server.libsonnet',
  'passwordpusher/server': import 'github.com/metio/kurly/workloads/passwordpusher/server.libsonnet',
  'inspircd/server': import 'github.com/metio/kurly/workloads/inspircd/server.libsonnet',
  'ejabberd/server': import 'github.com/metio/kurly/workloads/ejabberd/server.libsonnet',
  'seatsurfing/server': import 'github.com/metio/kurly/workloads/seatsurfing/server.libsonnet',
  'endurain/server': import 'github.com/metio/kurly/workloads/endurain/server.libsonnet',
  'wger/server': import 'github.com/metio/kurly/workloads/wger/server.libsonnet',
  'paperless-ngx/server': import 'github.com/metio/kurly/workloads/paperless-ngx/server.libsonnet',
  'invoiceninja/server': import 'github.com/metio/kurly/workloads/invoiceninja/server.libsonnet',
  'mautic/server': import 'github.com/metio/kurly/workloads/mautic/server.libsonnet',
  'maybe/server': import 'github.com/metio/kurly/workloads/maybe/server.libsonnet',
  'peertube/server': import 'github.com/metio/kurly/workloads/peertube/server.libsonnet',
  'sonarqube/server': import 'github.com/metio/kurly/workloads/sonarqube/server.libsonnet',
  'twenty/server': import 'github.com/metio/kurly/workloads/twenty/server.libsonnet',
  'twenty/worker': import 'github.com/metio/kurly/workloads/twenty/worker.libsonnet',
  'bigcapital/server': import 'github.com/metio/kurly/workloads/bigcapital/server.libsonnet',
  'bigcapital/webapp': import 'github.com/metio/kurly/workloads/bigcapital/webapp.libsonnet',
  'bigcapital/gateway': import 'github.com/metio/kurly/workloads/bigcapital/gateway.libsonnet',
  'overleaf/server': import 'github.com/metio/kurly/workloads/overleaf/server.libsonnet',
  'memos/server': import 'github.com/metio/kurly/workloads/memos/server.libsonnet',
  'ntfy/server': import 'github.com/metio/kurly/workloads/ntfy/server.libsonnet',
  'gotify/server': import 'github.com/metio/kurly/workloads/gotify/server.libsonnet',
  'linkding/server': import 'github.com/metio/kurly/workloads/linkding/server.libsonnet',
  'shiori/server': import 'github.com/metio/kurly/workloads/shiori/server.libsonnet',
  'readeck/server': import 'github.com/metio/kurly/workloads/readeck/server.libsonnet',
  'dokuwiki/server': import 'github.com/metio/kurly/workloads/dokuwiki/server.libsonnet',
  'excalidraw/server': import 'github.com/metio/kurly/workloads/excalidraw/server.libsonnet',
  'homer/server': import 'github.com/metio/kurly/workloads/homer/server.libsonnet',
  'dashy/server': import 'github.com/metio/kurly/workloads/dashy/server.libsonnet',
  'stirling-pdf/server': import 'github.com/metio/kurly/workloads/stirling-pdf/server.libsonnet',
  'microbin/server': import 'github.com/metio/kurly/workloads/microbin/server.libsonnet',
  'komga/server': import 'github.com/metio/kurly/workloads/komga/server.libsonnet',
  'kavita/server': import 'github.com/metio/kurly/workloads/kavita/server.libsonnet',
  'navidrome/server': import 'github.com/metio/kurly/workloads/navidrome/server.libsonnet',
  'audiobookshelf/server': import 'github.com/metio/kurly/workloads/audiobookshelf/server.libsonnet',
  'beszel/server': import 'github.com/metio/kurly/workloads/beszel/server.libsonnet',
  'code-server/server': import 'github.com/metio/kurly/workloads/code-server/server.libsonnet',
  'silverbullet/server': import 'github.com/metio/kurly/workloads/silverbullet/server.libsonnet',
  'trilium/server': import 'github.com/metio/kurly/workloads/trilium/server.libsonnet',
  'flatnotes/server': import 'github.com/metio/kurly/workloads/flatnotes/server.libsonnet',
  'freshrss/server': import 'github.com/metio/kurly/workloads/freshrss/server.libsonnet',
  'miniflux/server': import 'github.com/metio/kurly/workloads/miniflux/server.libsonnet',
  'linkwarden/server': import 'github.com/metio/kurly/workloads/linkwarden/server.libsonnet',
  'umami/server': import 'github.com/metio/kurly/workloads/umami/server.libsonnet',
  'listmonk/server': import 'github.com/metio/kurly/workloads/listmonk/server.libsonnet',
  'vikunja/server': import 'github.com/metio/kurly/workloads/vikunja/server.libsonnet',
  'dex/server': import 'github.com/metio/kurly/workloads/dex/server.libsonnet',
  'hedgedoc/server': import 'github.com/metio/kurly/workloads/hedgedoc/server.libsonnet',
  'etherpad/server': import 'github.com/metio/kurly/workloads/etherpad/server.libsonnet',
  'wordpress/server': import 'github.com/metio/kurly/workloads/wordpress/server.libsonnet',
  'status-responder/responder': import 'github.com/metio/kurly/workloads/status-responder/responder.libsonnet',
  'cnpg-cluster/cluster': import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet',
  'mysql-cluster/cluster': import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet',
  'opensearch-cluster/cluster': import 'github.com/metio/kurly/workloads/opensearch-cluster/cluster.libsonnet',
  'mongodb-cluster/cluster': import 'github.com/metio/kurly/workloads/mongodb-cluster/cluster.libsonnet',
  'cassandra-cluster/cluster': import 'github.com/metio/kurly/workloads/cassandra-cluster/cluster.libsonnet',
  'neo4j/server': import 'github.com/metio/kurly/workloads/neo4j/server.libsonnet',
  'ferretdb/server': import 'github.com/metio/kurly/workloads/ferretdb/server.libsonnet',
  'directus/server': import 'github.com/metio/kurly/workloads/directus/server.libsonnet',
  'metabase/server': import 'github.com/metio/kurly/workloads/metabase/server.libsonnet',
  'ghost/server': import 'github.com/metio/kurly/workloads/ghost/server.libsonnet',
  'n8n/server': import 'github.com/metio/kurly/workloads/n8n/server.libsonnet',
  'wikijs/server': import 'github.com/metio/kurly/workloads/wikijs/server.libsonnet',
  'matomo/server': import 'github.com/metio/kurly/workloads/matomo/server.libsonnet',
  'bookstack/server': import 'github.com/metio/kurly/workloads/bookstack/server.libsonnet',
  'snipe-it/server': import 'github.com/metio/kurly/workloads/snipe-it/server.libsonnet',
  'nocodb/server': import 'github.com/metio/kurly/workloads/nocodb/server.libsonnet',
  'baserow/server': import 'github.com/metio/kurly/workloads/baserow/server.libsonnet',
  'rallly/server': import 'github.com/metio/kurly/workloads/rallly/server.libsonnet',
  'shlink/server': import 'github.com/metio/kurly/workloads/shlink/server.libsonnet',
  'roundcube/server': import 'github.com/metio/kurly/workloads/roundcube/server.libsonnet',
  'mediawiki/server': import 'github.com/metio/kurly/workloads/mediawiki/server.libsonnet',
  'firefly-iii/server': import 'github.com/metio/kurly/workloads/firefly-iii/server.libsonnet',
  'fider/server': import 'github.com/metio/kurly/workloads/fider/server.libsonnet',
  'monica/server': import 'github.com/metio/kurly/workloads/monica/server.libsonnet',
  'wallabag/server': import 'github.com/metio/kurly/workloads/wallabag/server.libsonnet',
  'glitchtip/server': import 'github.com/metio/kurly/workloads/glitchtip/server.libsonnet',
  'glitchtip/worker': import 'github.com/metio/kurly/workloads/glitchtip/worker.libsonnet',
  'commafeed/server': import 'github.com/metio/kurly/workloads/commafeed/server.libsonnet',
  'lychee/server': import 'github.com/metio/kurly/workloads/lychee/server.libsonnet',
  'photoprism/server': import 'github.com/metio/kurly/workloads/photoprism/server.libsonnet',
  'answer/server': import 'github.com/metio/kurly/workloads/answer/server.libsonnet',
  'blinko/server': import 'github.com/metio/kurly/workloads/blinko/server.libsonnet',
  'bugsink/server': import 'github.com/metio/kurly/workloads/bugsink/server.libsonnet',
  'docmost/server': import 'github.com/metio/kurly/workloads/docmost/server.libsonnet',
  'greenlight/server': import 'github.com/metio/kurly/workloads/greenlight/server.libsonnet',
  'pilos/server': import 'github.com/metio/kurly/workloads/pilos/server.libsonnet',
  'spegel/mirror': import 'github.com/metio/kurly/workloads/spegel/mirror.libsonnet',
  'homarr/server': import 'github.com/metio/kurly/workloads/homarr/server.libsonnet',
  'mattermost/server': import 'github.com/metio/kurly/workloads/mattermost/server.libsonnet',
  'rocketchat/server': import 'github.com/metio/kurly/workloads/rocketchat/server.libsonnet',
  'wekan/server': import 'github.com/metio/kurly/workloads/wekan/server.libsonnet',
  'activepieces/server': import 'github.com/metio/kurly/workloads/activepieces/server.libsonnet',
  'automatisch/server': import 'github.com/metio/kurly/workloads/automatisch/server.libsonnet',
  'automatisch/worker': import 'github.com/metio/kurly/workloads/automatisch/worker.libsonnet',
  'karakeep/server': import 'github.com/metio/kurly/workloads/karakeep/server.libsonnet',
  'homepage/server': import 'github.com/metio/kurly/workloads/homepage/server.libsonnet',
  'changedetection/server': import 'github.com/metio/kurly/workloads/changedetection/server.libsonnet',
  'calibre-web/server': import 'github.com/metio/kurly/workloads/calibre-web/server.libsonnet',
  'owncast/server': import 'github.com/metio/kurly/workloads/owncast/server.libsonnet',
  'grav/server': import 'github.com/metio/kurly/workloads/grav/server.libsonnet',
  'rss-bridge/server': import 'github.com/metio/kurly/workloads/rss-bridge/server.libsonnet',
  'sonarr/server': import 'github.com/metio/kurly/workloads/sonarr/server.libsonnet',
  'radarr/server': import 'github.com/metio/kurly/workloads/radarr/server.libsonnet',
  'lidarr/server': import 'github.com/metio/kurly/workloads/lidarr/server.libsonnet',
  'prowlarr/server': import 'github.com/metio/kurly/workloads/prowlarr/server.libsonnet',
  'bazarr/server': import 'github.com/metio/kurly/workloads/bazarr/server.libsonnet',
  'jackett/server': import 'github.com/metio/kurly/workloads/jackett/server.libsonnet',
  'flaresolverr/server': import 'github.com/metio/kurly/workloads/flaresolverr/server.libsonnet',
  'heimdall/server': import 'github.com/metio/kurly/workloads/heimdall/server.libsonnet',
  'grocy/server': import 'github.com/metio/kurly/workloads/grocy/server.libsonnet',
  'librespeed/server': import 'github.com/metio/kurly/workloads/librespeed/server.libsonnet',
  'it-tools/server': import 'github.com/metio/kurly/workloads/it-tools/server.libsonnet',
  'drawio/server': import 'github.com/metio/kurly/workloads/drawio/server.libsonnet',
  'filebrowser/server': import 'github.com/metio/kurly/workloads/filebrowser/server.libsonnet',
  'siyuan/server': import 'github.com/metio/kurly/workloads/siyuan/server.libsonnet',
  'gitea/server': import 'github.com/metio/kurly/workloads/gitea/server.libsonnet',
  'gogs/server': import 'github.com/metio/kurly/workloads/gogs/server.libsonnet',
  'mealie/server': import 'github.com/metio/kurly/workloads/mealie/server.libsonnet',
  'tautulli/server': import 'github.com/metio/kurly/workloads/tautulli/server.libsonnet',
  'ombi/server': import 'github.com/metio/kurly/workloads/ombi/server.libsonnet',
  'overseerr/server': import 'github.com/metio/kurly/workloads/overseerr/server.libsonnet',
  'jellyseerr/server': import 'github.com/metio/kurly/workloads/jellyseerr/server.libsonnet',
  'metube/server': import 'github.com/metio/kurly/workloads/metube/server.libsonnet',
  'docuseal/server': import 'github.com/metio/kurly/workloads/docuseal/server.libsonnet',
  'shaarli/server': import 'github.com/metio/kurly/workloads/shaarli/server.libsonnet',
  'piwigo/server': import 'github.com/metio/kurly/workloads/piwigo/server.libsonnet',
  'pyload-ng/server': import 'github.com/metio/kurly/workloads/pyload-ng/server.libsonnet',
  'pairdrop/server': import 'github.com/metio/kurly/workloads/pairdrop/server.libsonnet',
  'privatebin/server': import 'github.com/metio/kurly/workloads/privatebin/server.libsonnet',
  'lldap/server': import 'github.com/metio/kurly/workloads/lldap/server.libsonnet',
  'qbittorrent/server': import 'github.com/metio/kurly/workloads/qbittorrent/server.libsonnet',
  'transmission/server': import 'github.com/metio/kurly/workloads/transmission/server.libsonnet',
  'sabnzbd/server': import 'github.com/metio/kurly/workloads/sabnzbd/server.libsonnet',
  'nzbget/server': import 'github.com/metio/kurly/workloads/nzbget/server.libsonnet',
  'deluge/server': import 'github.com/metio/kurly/workloads/deluge/server.libsonnet',
  'syncthing/server': import 'github.com/metio/kurly/workloads/syncthing/server.libsonnet',
  'jellyfin/server': import 'github.com/metio/kurly/workloads/jellyfin/server.libsonnet',
  'calibre/server': import 'github.com/metio/kurly/workloads/calibre/server.libsonnet',
  'gotosocial/server': import 'github.com/metio/kurly/workloads/gotosocial/server.libsonnet',
  'flame/server': import 'github.com/metio/kurly/workloads/flame/server.libsonnet',
  'gatus/server': import 'github.com/metio/kurly/workloads/gatus/server.libsonnet',
  'traccar/server': import 'github.com/metio/kurly/workloads/traccar/server.libsonnet',
  'healthchecks/server': import 'github.com/metio/kurly/workloads/healthchecks/server.libsonnet',
  'searxng/server': import 'github.com/metio/kurly/workloads/searxng/server.libsonnet',
  'airsonic-advanced/server': import 'github.com/metio/kurly/workloads/airsonic-advanced/server.libsonnet',
  'mylar3/server': import 'github.com/metio/kurly/workloads/mylar3/server.libsonnet',
  'netbootxyz/server': import 'github.com/metio/kurly/workloads/netbootxyz/server.libsonnet',
  'focalboard/server': import 'github.com/metio/kurly/workloads/focalboard/server.libsonnet',
  'wallos/server': import 'github.com/metio/kurly/workloads/wallos/server.libsonnet',
  'adguardhome/server': import 'github.com/metio/kurly/workloads/adguardhome/server.libsonnet',
  'convertx/server': import 'github.com/metio/kurly/workloads/convertx/server.libsonnet',
  'cyberchef/server': import 'github.com/metio/kurly/workloads/cyberchef/server.libsonnet',
  'joplin/server': import 'github.com/metio/kurly/workloads/joplin/server.libsonnet',
  'pgadmin/server': import 'github.com/metio/kurly/workloads/pgadmin/server.libsonnet',
  'tachidesk/server': import 'github.com/metio/kurly/workloads/tachidesk/server.libsonnet',
  'pihole/server': import 'github.com/metio/kurly/workloads/pihole/server.libsonnet',
  'kimai/server': import 'github.com/metio/kurly/workloads/kimai/server.libsonnet',
  'adminer/server': import 'github.com/metio/kurly/workloads/adminer/server.libsonnet',
  'phpmyadmin/server': import 'github.com/metio/kurly/workloads/phpmyadmin/server.libsonnet',
  'redmine/server': import 'github.com/metio/kurly/workloads/redmine/server.libsonnet',
  'nzbhydra2/server': import 'github.com/metio/kurly/workloads/nzbhydra2/server.libsonnet',
  'duplicati/server': import 'github.com/metio/kurly/workloads/duplicati/server.libsonnet',
  'resilio-sync/server': import 'github.com/metio/kurly/workloads/resilio-sync/server.libsonnet',
  'davos/server': import 'github.com/metio/kurly/workloads/davos/server.libsonnet',
  'foldingathome/server': import 'github.com/metio/kurly/workloads/foldingathome/server.libsonnet',
  'projectsend/server': import 'github.com/metio/kurly/workloads/projectsend/server.libsonnet',
  'whoogle/server': import 'github.com/metio/kurly/workloads/whoogle/server.libsonnet',
  'mongo-express/server': import 'github.com/metio/kurly/workloads/mongo-express/server.libsonnet',
  'thelounge/server': import 'github.com/metio/kurly/workloads/thelounge/server.libsonnet',
  'mumble/server': import 'github.com/metio/kurly/workloads/mumble/server.libsonnet',
  'victoriametrics/server': import 'github.com/metio/kurly/workloads/victoriametrics/server.libsonnet',
  'openobserve/server': import 'github.com/metio/kurly/workloads/openobserve/server.libsonnet',
  'meilisearch/server': import 'github.com/metio/kurly/workloads/meilisearch/server.libsonnet',
  'qdrant/server': import 'github.com/metio/kurly/workloads/qdrant/server.libsonnet',
  'typesense/server': import 'github.com/metio/kurly/workloads/typesense/server.libsonnet',
  'browserless/server': import 'github.com/metio/kurly/workloads/browserless/server.libsonnet',
  'tika/server': import 'github.com/metio/kurly/workloads/tika/server.libsonnet',
  'gotenberg/server': import 'github.com/metio/kurly/workloads/gotenberg/server.libsonnet',
  'open-webui/server': import 'github.com/metio/kurly/workloads/open-webui/server.libsonnet',
  'glance/server': import 'github.com/metio/kurly/workloads/glance/server.libsonnet',
  'node-red/server': import 'github.com/metio/kurly/workloads/node-red/server.libsonnet',
  'esphome/server': import 'github.com/metio/kurly/workloads/esphome/server.libsonnet',
  '2fauth/server': import 'github.com/metio/kurly/workloads/2fauth/server.libsonnet',
  'influxdb/server': import 'github.com/metio/kurly/workloads/influxdb/server.libsonnet',
  'couchdb/server': import 'github.com/metio/kurly/workloads/couchdb/server.libsonnet',
  'home-assistant/server': import 'github.com/metio/kurly/workloads/home-assistant/server.libsonnet',
  'nextcloud/server': import 'github.com/metio/kurly/workloads/nextcloud/server.libsonnet',
  'rundeck/server': import 'github.com/metio/kurly/workloads/rundeck/server.libsonnet',
  'mosquitto/server': import 'github.com/metio/kurly/workloads/mosquitto/server.libsonnet',
  'authelia/server': import 'github.com/metio/kurly/workloads/authelia/server.libsonnet',
  'clickhouse/server': import 'github.com/metio/kurly/workloads/clickhouse/server.libsonnet',
  'matrix-conduit/server': import 'github.com/metio/kurly/workloads/matrix-conduit/server.libsonnet',
  'kutt/server': import 'github.com/metio/kurly/workloads/kutt/server.libsonnet',
  'emby/server': import 'github.com/metio/kurly/workloads/emby/server.libsonnet',
  'webtrees/server': import 'github.com/metio/kurly/workloads/webtrees/server.libsonnet',
  'mariadb/server': import 'github.com/metio/kurly/workloads/mariadb/server.libsonnet',
  'mysql/server': import 'github.com/metio/kurly/workloads/mysql/server.libsonnet',
  'postgres/server': import 'github.com/metio/kurly/workloads/postgres/server.libsonnet',
  'redis/server': import 'github.com/metio/kurly/workloads/redis/server.libsonnet',
  'mongo/server': import 'github.com/metio/kurly/workloads/mongo/server.libsonnet',
  'nginx-proxy-manager/server': import 'github.com/metio/kurly/workloads/nginx-proxy-manager/server.libsonnet',
  'minio/server': import 'github.com/metio/kurly/workloads/minio/server.libsonnet',
  'rabbitmq/server': import 'github.com/metio/kurly/workloads/rabbitmq/server.libsonnet',
  'formbricks/server': import 'github.com/metio/kurly/workloads/formbricks/server.libsonnet',
  'plex/server': import 'github.com/metio/kurly/workloads/plex/server.libsonnet',
  'ollama/server': import 'github.com/metio/kurly/workloads/ollama/server.libsonnet',
  'odoo/server': import 'github.com/metio/kurly/workloads/odoo/server.libsonnet',
  'technitium/server': import 'github.com/metio/kurly/workloads/technitium/server.libsonnet',
  'docker-registry-ui/server': import 'github.com/metio/kurly/workloads/docker-registry-ui/server.libsonnet',
  'element-web/server': import 'github.com/metio/kurly/workloads/element-web/server.libsonnet',
  'planka/server': import 'github.com/metio/kurly/workloads/planka/server.libsonnet',
  'photoview/server': import 'github.com/metio/kurly/workloads/photoview/server.libsonnet',
  'yourls/server': import 'github.com/metio/kurly/workloads/yourls/server.libsonnet',
  'pocket-id/server': import 'github.com/metio/kurly/workloads/pocket-id/server.libsonnet',
  'openproject/server': import 'github.com/metio/kurly/workloads/openproject/server.libsonnet',
  'joomla/server': import 'github.com/metio/kurly/workloads/joomla/server.libsonnet',
  'drupal/server': import 'github.com/metio/kurly/workloads/drupal/server.libsonnet',
  'prestashop/server': import 'github.com/metio/kurly/workloads/prestashop/server.libsonnet',
  'nocobase/server': import 'github.com/metio/kurly/workloads/nocobase/server.libsonnet',
  'synapse/server': import 'github.com/metio/kurly/workloads/synapse/server.libsonnet',
  'onlyoffice/server': import 'github.com/metio/kurly/workloads/onlyoffice/server.libsonnet',
  'registry/server': import 'github.com/metio/kurly/workloads/registry/server.libsonnet',
  'xwiki/server': import 'github.com/metio/kurly/workloads/xwiki/server.libsonnet',
  'redis-commander/server': import 'github.com/metio/kurly/workloads/redis-commander/server.libsonnet',
  'linkstack/server': import 'github.com/metio/kurly/workloads/linkstack/server.libsonnet',
  'snappymail/server': import 'github.com/metio/kurly/workloads/snappymail/server.libsonnet',
  'tvheadend/server': import 'github.com/metio/kurly/workloads/tvheadend/server.libsonnet',
  'organizr/server': import 'github.com/metio/kurly/workloads/organizr/server.libsonnet',
  'filestash/server': import 'github.com/metio/kurly/workloads/filestash/server.libsonnet',
  'mailhog/server': import 'github.com/metio/kurly/workloads/mailhog/server.libsonnet',
  'openhab/server': import 'github.com/metio/kurly/workloads/openhab/server.libsonnet',
  'cnpg-image-catalog/namespaced': import 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet',
  'cnpg-image-catalog/cluster': import 'github.com/metio/kurly/workloads/cnpg-image-catalog/cluster.libsonnet',
  'dragonfly/instance': import 'github.com/metio/kurly/workloads/dragonfly/instance.libsonnet',
  'otel-collector/agent': import 'github.com/metio/kurly/workloads/otel-collector/agent.libsonnet',
  'blackbox-exporter/server': import 'github.com/metio/kurly/workloads/blackbox-exporter/server.libsonnet',
  'alertmanager/server': import 'github.com/metio/kurly/workloads/alertmanager/server.libsonnet',
  'keycloak/server': import 'github.com/metio/kurly/workloads/keycloak/server.libsonnet',
  'thanos/query': import 'github.com/metio/kurly/workloads/thanos/query.libsonnet',
  'thanos/store': import 'github.com/metio/kurly/workloads/thanos/store.libsonnet',
  'thanos/compact': import 'github.com/metio/kurly/workloads/thanos/compact.libsonnet',
  'thanos/receive': import 'github.com/metio/kurly/workloads/thanos/receive.libsonnet',
  'thanos/query-frontend': import 'github.com/metio/kurly/workloads/thanos/query-frontend.libsonnet',
  'thanos/ruler': import 'github.com/metio/kurly/workloads/thanos/ruler.libsonnet',
  'loki/server': import 'github.com/metio/kurly/workloads/loki/server.libsonnet',
  'tempo/server': import 'github.com/metio/kurly/workloads/tempo/server.libsonnet',
  'grafana/server': import 'github.com/metio/kurly/workloads/grafana/server.libsonnet',
  'prometheus/server': import 'github.com/metio/kurly/workloads/prometheus/server.libsonnet',
  'opencost/server': import 'github.com/metio/kurly/workloads/opencost/server.libsonnet',
  'metrics-server/server': import 'github.com/metio/kurly/workloads/metrics-server/server.libsonnet',
  'seaweedfs/server': import 'github.com/metio/kurly/workloads/seaweedfs/server.libsonnet',
  'seaweedfs/master': import 'github.com/metio/kurly/workloads/seaweedfs/master.libsonnet',
  'seaweedfs/volume': import 'github.com/metio/kurly/workloads/seaweedfs/volume.libsonnet',
  'seaweedfs/filer': import 'github.com/metio/kurly/workloads/seaweedfs/filer.libsonnet',
  'memcached/cache': import 'github.com/metio/kurly/workloads/memcached/cache.libsonnet',
  'valkey/instance': import 'github.com/metio/kurly/workloads/valkey/instance.libsonnet',
  'valkey/cache': import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet',
};

// Fails if the annotated names and the exported names are not the same set,
// naming exactly which side is out of step.
local reconcile(section, annotated, exported) =
  local a = std.set(annotated);
  local e = std.set(exported);
  local unannotated = [name for name in e if !std.member(a, name)];
  local stale = [name for name in a if !std.member(e, name)];
  assert unannotated == [] :
         section + ': exported but not annotated in annotations.libsonnet: ' + std.join(', ', unannotated);
  assert stale == [] :
         section + ': annotated but not exported (stale annotation): ' + std.join(', ', stale);
  true;

// One catalog entry per annotated field, id-keyed and sorted for a stable diff.
local entries(section) = [
  { id: name } + section[name]
  for name in std.objectFields(section)
];

// Flattens the annotated workloads into catalog entries, checking every stage
// against stageImports: the annotated stage keys and the imported stage keys
// must be the same set, and each import must resolve to a function.
local stageKeys = std.set([
  workload + '/' + stage
  for workload in std.objectFields(ann.workloads)
  for stage in std.objectFields(ann.workloads[workload].stages)
]);
local workloadEntries =
  assert reconcile('workload stages', stageKeys, std.objectFields(stageImports));
  assert std.all([
    std.isFunction(stageImports[key])
    for key in std.objectFields(stageImports)
  ]) : 'workloads: every stage import must resolve to a function(params) app';
  [
    {
      id: workload,
      summary: ann.workloads[workload].summary,
      stages: [
        { id: stage } + ann.workloads[workload].stages[stage]
        for stage in std.objectFields(ann.workloads[workload].stages)
      ],
    }
    for workload in std.objectFields(ann.workloads)
  ];

{
  // Drift gates — object-level asserts fire when this object is manifested.
  assert reconcile('features', std.objectFields(ann.features), std.objectFieldsAll(features)),
  assert reconcile('expose', std.objectFields(ann.expose), std.objectFieldsAll(expose)),
  assert reconcile('security', std.objectFields(ann.security), std.objectFieldsAll(security)),
  assert reconcile('migrations', std.objectFields(ann.migrations), std.objectFieldsAll(migrations)),
  // Kinds live in separate files; assert the annotated set is exactly the four
  // main exposes as callables.
  assert reconcile('kinds', std.objectFields(ann.kinds), ['http', 'worker', 'cron', 'daemon', 'stateful', 'job']),
  assert std.all([std.objectHasAll(main, kind) for kind in std.objectFields(ann.kinds)]) :
         'kinds: main.libsonnet must expose every annotated kind',
  // Helpers are top-level fields of main alongside the kinds; assert the
  // annotated set is exactly the rendering terminals main exposes.
  assert reconcile('helpers', std.objectFields(ann.helpers), ['certificate', 'externalSecret', 'join', 'list', 'listOf', 'mirror']),
  assert std.all([std.objectHasAll(main, helper) for helper in std.objectFields(ann.helpers)]) :
         'helpers: main.libsonnet must expose every annotated helper',

  schemaVersion: 1,
  workloads: workloadEntries,
  kinds: entries(ann.kinds),
  features: entries(ann.features),
  expose: entries(ann.expose),
  security: entries(ann.security),
  helpers: entries(ann.helpers),
  migrations: entries(ann.migrations),
}
