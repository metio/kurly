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
local bollwerk = import '../bollwerk/bollwerk.libsonnet';
local expose = import '../lib/expose.libsonnet';
local features = import '../lib/features.libsonnet';
local migrations = import '../lib/migrations.libsonnet';
local network = import '../lib/network.libsonnet';
local resourcePresets = import '../lib/resource-presets.libsonnet';
local security = import '../lib/security.libsonnet';
local main = import '../main.libsonnet';
local ann = import './annotations.libsonnet';
local architectures = import './architectures.gen.libsonnet';
local bsiViolations = import './bsi.gen.libsonnet';
local forge = import './forge.gen.libsonnet';
local maturity = import './maturity.libsonnet';
local spdx = import './spdx.gen.libsonnet';
local upstream = import './upstream.gen.libsonnet';

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
  'grist/server': import 'github.com/metio/kurly/workloads/grist/server.libsonnet',
  'jenkins/server': import 'github.com/metio/kurly/workloads/jenkins/server.libsonnet',
  'alist/server': import 'github.com/metio/kurly/workloads/alist/server.libsonnet',
  'calibre-web-automated/server': import 'github.com/metio/kurly/workloads/calibre-web-automated/server.libsonnet',
  'readarr/server': import 'github.com/metio/kurly/workloads/readarr/server.libsonnet',
  'apprise/server': import 'github.com/metio/kurly/workloads/apprise/server.libsonnet',
  'chatpad/server': import 'github.com/metio/kurly/workloads/chatpad/server.libsonnet',
  'cobalt/server': import 'github.com/metio/kurly/workloads/cobalt/server.libsonnet',
  'davis/server': import 'github.com/metio/kurly/workloads/davis/server.libsonnet',
  'draw-io/server': import 'github.com/metio/kurly/workloads/draw-io/server.libsonnet',
  'ghostfolio/server': import 'github.com/metio/kurly/workloads/ghostfolio/server.libsonnet',
  'anythingllm/server': import 'github.com/metio/kurly/workloads/anythingllm/server.libsonnet',
  'hollama/server': import 'github.com/metio/kurly/workloads/hollama/server.libsonnet',
  'lobe-chat/server': import 'github.com/metio/kurly/workloads/lobe-chat/server.libsonnet',
  'leantime/server': import 'github.com/metio/kurly/workloads/leantime/server.libsonnet',
  'mailpit/server': import 'github.com/metio/kurly/workloads/mailpit/server.libsonnet',
  'maloja/server': import 'github.com/metio/kurly/workloads/maloja/server.libsonnet',
  'mermaid-live-editor/server': import 'github.com/metio/kurly/workloads/mermaid-live-editor/server.libsonnet',
  'mazanoke/server': import 'github.com/metio/kurly/workloads/mazanoke/server.libsonnet',
  'owntracks-recorder/server': import 'github.com/metio/kurly/workloads/owntracks-recorder/server.libsonnet',
  'gokapi/server': import 'github.com/metio/kurly/workloads/gokapi/server.libsonnet',
  'pingvin-share/server': import 'github.com/metio/kurly/workloads/pingvin-share/server.libsonnet',
  'pocketbase/server': import 'github.com/metio/kurly/workloads/pocketbase/server.libsonnet',
  'tandoor/server': import 'github.com/metio/kurly/workloads/tandoor/server.libsonnet',
  'smtp4dev/server': import 'github.com/metio/kurly/workloads/smtp4dev/server.libsonnet',
  'teable/server': import 'github.com/metio/kurly/workloads/teable/server.libsonnet',
  'cal-com/server': import 'github.com/metio/kurly/workloads/cal-com/server.libsonnet',
  'documenso/server': import 'github.com/metio/kurly/workloads/documenso/server.libsonnet',
  'kavita/server': import 'github.com/metio/kurly/workloads/kavita/server.libsonnet',
  'portainer/server': import 'github.com/metio/kurly/workloads/portainer/server.libsonnet',
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
  'guacamole/server': import 'github.com/metio/kurly/workloads/guacamole/server.libsonnet',
  'authentik/server': import 'github.com/metio/kurly/workloads/authentik/server.libsonnet',
  'authentik/worker': import 'github.com/metio/kurly/workloads/authentik/worker.libsonnet',
  'outline/server': import 'github.com/metio/kurly/workloads/outline/server.libsonnet',
  'penpot/backend': import 'github.com/metio/kurly/workloads/penpot/backend.libsonnet',
  'penpot/frontend': import 'github.com/metio/kurly/workloads/penpot/frontend.libsonnet',
  'penpot/exporter': import 'github.com/metio/kurly/workloads/penpot/exporter.libsonnet',
  'misskey/server': import 'github.com/metio/kurly/workloads/misskey/server.libsonnet',
  'lemmy/backend': import 'github.com/metio/kurly/workloads/lemmy/backend.libsonnet',
  'lemmy/ui': import 'github.com/metio/kurly/workloads/lemmy/ui.libsonnet',
  'lemmy/pictrs': import 'github.com/metio/kurly/workloads/lemmy/pictrs.libsonnet',
  'mastodon/web': import 'github.com/metio/kurly/workloads/mastodon/web.libsonnet',
  'mastodon/streaming': import 'github.com/metio/kurly/workloads/mastodon/streaming.libsonnet',
  'mastodon/sidekiq': import 'github.com/metio/kurly/workloads/mastodon/sidekiq.libsonnet',
  'oauth2-proxy/server': import 'github.com/metio/kurly/workloads/oauth2-proxy/server.libsonnet',
  'emqx/server': import 'github.com/metio/kurly/workloads/emqx/server.libsonnet',
  'nats/server': import 'github.com/metio/kurly/workloads/nats/server.libsonnet',
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
  'ente/server': import 'github.com/metio/kurly/workloads/ente/server.libsonnet',
  'ente/web': import 'github.com/metio/kurly/workloads/ente/web.libsonnet',
  'immich/server': import 'github.com/metio/kurly/workloads/immich/server.libsonnet',
  'immich/machine-learning': import 'github.com/metio/kurly/workloads/immich/machine-learning.libsonnet',
  'frigate/server': import 'github.com/metio/kurly/workloads/frigate/server.libsonnet',
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

// The number of PersistentVolumes a stage's default render actually claims —
// owned PVCs plus a StatefulSet's per-pod volumeClaimTemplates. Derived by
// rendering the stage (the same function the catalog already imports), so it
// cannot drift from what the workload emits: `pvcs: 0` means the stage runs
// without a PVC (its state lives in a database, object storage, or nowhere),
// which is the fleet an operator with only S3 wants to find. A custom-resource
// stage whose operator provisions storage at runtime (a CNPG Cluster) claims no
// PVC in its own manifest and so reads 0 here — see its `requires` for the
// dependency it carries instead.
local pvcCount(fn) =
  local items = main.list(fn()).items;
  std.length([m for m in items if m.kind == 'PersistentVolumeClaim'])
  + std.foldl(
    function(acc, m) acc + std.length(std.get(m.spec, 'volumeClaimTemplates', [])),
    [m for m in items if m.kind == 'StatefulSet'],
    0
  );

// The pod templates a stage renders — where its security context lives.
local podTemplates(items) = [
  if m.kind == 'CronJob' then m.spec.jobTemplate.spec.template else m.spec.template
  for m in items
  if std.member(['Deployment', 'StatefulSet', 'DaemonSet', 'Job', 'CronJob'], m.kind)
];

// The multi-tenant security posture a stage's DEFAULT render carries, derived
// (like storage.pvcs) so it never drifts from what the workload emits — the
// portal reads it to refuse or gate the recipes that need root before hosting a
// stranger's workload on a shared node. `null` for a custom-resource stage whose
// pods the operator (not kurly) runs, so the posture is not kurly's to state.
//   runsAsRoot           — a pod without runAsNonRoot (kurly.rootUser / privileged)
//   writableRootFilesystem — a container without a read-only root fs
//   ownUserNamespace     — hostUsers:false, so a breakout lands unprivileged on the host
//   multiTenantSafe      — none of the above relaxations; the hardened default stands
local posture(fn) =
  local tmpls = podTemplates(main.list(fn()).items);
  if tmpls == [] then null
  else
    local containers = std.flattenArrays([std.get(t.spec, 'containers', []) for t in tmpls]);
    local nonRoot = std.all([std.get(std.get(t.spec, 'securityContext', {}), 'runAsNonRoot', false) for t in tmpls]);
    local readOnly = containers != [] && std.all([std.get(std.get(c, 'securityContext', {}), 'readOnlyRootFilesystem', false) for c in containers]);
    local ownUserNs = std.all([std.get(t.spec, 'hostUsers', true) == false for t in tmpls]);
    {
      runsAsRoot: !nonRoot,
      writableRootFilesystem: !readOnly,
      ownUserNamespace: ownUserNs,
      multiTenantSafe: nonRoot && readOnly && ownUserNs,
    };

// Whether a stage is a CLUSTER add-on rather than something a tenant runs: it
// holds cluster-wide RBAC, reaches the node it lands on, or runs on every node.
// Each of those is visible in what the stage renders, so this is a fact rather
// than a judgement — a consumer deciding who may run what reads it instead of
// keeping a list of exceptions that ages.
//
// The reasons are reported alongside the verdict, because "cluster-scoped" is
// acted on and an unexplained boolean invites a hand-maintained override.
// The kinds kurly renders that live outside a namespace. RBAC and the add-on
// kinds are Kubernetes' own; ClusterImageCatalog is CNPG's cluster-scoped
// counterpart to the namespaced ImageCatalog, and a stage that renders one
// configures the cluster rather than a tenant.
local clusterScopedKinds = [
  'APIService',
  'ClusterImageCatalog',
  'ClusterRole',
  'ClusterRoleBinding',
  'CustomResourceDefinition',
  'IngressClass',
  'MutatingWebhookConfiguration',
  'Namespace',
  'PriorityClass',
  'StorageClass',
  'ValidatingAdmissionPolicy',
  'ValidatingAdmissionPolicyBinding',
  'ValidatingWebhookConfiguration',
];

local clusterScoped(fn) =
  local items = main.list(fn()).items;
  local tmpls = podTemplates(items);
  local kinds = std.set([item.kind for item in items]);
  local clusterRbac = std.setInter(kinds, ['ClusterRole', 'ClusterRoleBinding']) != [];
  local apiService = std.member(kinds, 'APIService');
  // A stage whose every object lives outside a namespace configures the cluster
  // itself — a CNPG ClusterImageCatalog names the images every tenant's database
  // may run, and belongs to whoever runs the cluster.
  local clusterObjects = std.setInter(kinds, std.set(clusterScopedKinds)) == kinds;
  local daemonSet = std.member(kinds, 'DaemonSet');
  local hostNetwork = std.any([std.get(t.spec, 'hostNetwork', false) for t in tmpls]);
  local hostPid = std.any([std.get(t.spec, 'hostPID', false) || std.get(t.spec, 'hostIPC', false) for t in tmpls]);
  local hostPath = std.any([
    std.objectHas(volume, 'hostPath')
    for t in tmpls
    for volume in std.get(t.spec, 'volumes', [])
  ]);
  local reasons = std.prune([
    if clusterRbac then 'clusterRbac' else null,
    if apiService then 'apiService' else null,
    if clusterObjects then 'clusterScopedObjects' else null,
    if daemonSet then 'daemonSet' else null,
    if hostNetwork then 'hostNetwork' else null,
    if hostPid then 'hostNamespaces' else null,
    if hostPath then 'hostPath' else null,
  ]);
  { clusterScoped: reasons != [] } + (if reasons == [] then {} else { clusterScopedBecause: reasons });

// Flattens the annotated workloads into catalog entries, checking every stage
// against stageImports: the annotated stage keys and the imported stage keys
// must be the same set, and each import must resolve to a function.
local stageKeys = std.set([
  workload + '/' + stage
  for workload in std.objectFields(ann.workloads)
  for stage in std.objectFields(ann.workloads[workload].stages)
]);
// What KIND of software a workload is, as opposed to how it is deployed (which
// `stage.kind` already says). A consumer that presents this catalogue to people
// needs the difference: adminer, phpmyadmin and redis-commander are ordinary
// `http` stages, but nobody hosts a database console as their product — they run
// it beside one. The vocabulary is deliberately small; a workload states one.
// Kept fine-grained on purpose: a consumer grouping three hundred entries needs
// sections a reader recognises, and one bucket holding every database, cache and
// identity provider is no more useful than no bucket at all.
local categories = [
  'admin',
  'application',
  'cache',
  'database',
  'identity',
  'messaging',
  'networking',
  'observability',
  'search',
  'storage',
  'tool',
];

// The licence, checked against the SPDX register rather than against a shape.
// The labels state project names (`ESPHome`), spellings SPDX does not use
// (`AGPLv3`), and identifiers that mean something other than intended
// (`BSL-1.1` is the Boost licence; an image carrying it beside an
// `emqx-enterprise` title means the Business Source one, `BUSL-1.1`). Each of
// those reads as a licence to anyone rendering the field, and a source-offer
// obligation keyed on identifiers would miss the case entirely.
//
// So a label SPDX does not recognise is dropped — the same rule the rest of
// these facts follow, since a value nobody can act on is not better than
// silence, and the label is somebody else's data to fix. An ANNOTATION that
// SPDX does not recognise fails the build instead: that one is ours, a
// maintainer wrote it having checked, and a typo there should never quietly
// become an absent licence. check-catalog lists what was dropped, so a junk
// label stays visible rather than merely absent.
//
// Two things travel with the identifier because the string alone does not carry
// them. Whether it is OSI-approved: a platform that says it hosts open source
// has to be able to tell that `BUSL-1.1` is source-available and not open
// source. And whether SPDX has deprecated the spelling: `GPL-3.0` says neither
// `-only` nor `-or-later`, so it is genuinely ambiguous — worth saying, never
// worth resolving by guessing, since only the project's own LICENSE file
// settles it.
//
// `NOASSERTION` is not a licence but SPDX's word for a publisher who was asked
// and declined to say. That is a different fact from nobody having asked, which
// is what an absent field means, so it is published as its own flag rather than
// as a licence string every consumer has to know to special-case.
local licenseFacts(workload, value, attested) =
  // A licence field may hold an expression rather than one identifier
  // (`EPL-2.0 OR BSD-3-Clause`). Every identifier in it must be one SPDX knows;
  // the operators are not identifiers, and a trailing `+` is part of the
  // spelling rather than of the name.
  local rawIdentifiers = [
    std.rstripChars(std.stripChars(token, '()'), '+')
    for token in std.split(value, ' ')
    if !std.member(['AND', 'OR', 'WITH'], token) && std.stripChars(token, '()') != ''
  ];
  // SPDX's own escape for a licence its register does not carry. Software that
  // is simply proprietary has no identifier and never will, and saying so is a
  // fact worth publishing — a platform that pays the projects it hosts needs to
  // tell "closed, deliberately" from "nobody has looked yet", which is what an
  // absent licence means.
  // A forge may report the identifier in its own casing — GitLab answers `mit`
  // where SPDX writes `MIT`. The register's identifiers are unique ignoring
  // case, so the spelling is recovered rather than treated as unknown.
  local canonicalOf = {
    [std.asciiLower(id)]: id
    for id in std.objectFields(spdx)
  };
  local canonical(id) =
    if std.startsWith(id, 'LicenseRef-') then id
    else std.get(canonicalOf, std.asciiLower(id), id);
  local identifiers = [canonical(id) for id in rawIdentifiers];
  local known = [
    id
    for id in identifiers
    if std.objectHas(spdx, id) || std.startsWith(id, 'LicenseRef-')
  ];
  if value == null then {}
  else if value == 'NOASSERTION' then { licenseNotAsserted: true }
  else if std.length(known) != std.length(identifiers) && !attested then {}
  else
    assert std.length(known) == std.length(identifiers) :
           'workloads: %s is annotated with the licence %s, which SPDX does not know' % [workload, value];
    {
      license: std.join(' ', [
        if std.member(['AND', 'OR', 'WITH'], token) then token else canonical(std.stripChars(token, '()'))
        for token in std.split(value, ' ')
      ]),
    }
    // Only a single identifier answers "is this open source" on its own. An
    // expression needs reading — an OR of a permissive and a proprietary
    // licence is a choice, an AND is a conjunction — so the flag is left off
    // rather than resolved to a side.
    + (
      if std.length(identifiers) == 1 then
        { licenseOsiApproved: if std.objectHas(spdx, identifiers[0]) then spdx[identifiers[0]].osiApproved else false }
      else {}
    )
    + (if std.any([std.objectHas(spdx, id) && spdx[id].deprecated for id in identifiers]) then { licenseDeprecated: true } else {});

// A repository that packages software for a registry, rather than the software's
// own home. `github.com/linuxserver/docker-jellyfin` builds a Jellyfin image; it
// is not Jellyfin, and its maintainers are not Jellyfin's. An image label points
// at whichever of the two built the image, so the two facts have to be told
// apart before either is published: naming a packager as the upstream project
// sends anyone acting on the field — crediting, funding, reporting a bug — to
// the wrong people. The shape is the tell: a packaging repository is almost
// always named for the tool that consumes it.
local packagingRepo(url) =
  local repo = std.reverse(std.split(url, '/'))[0];
  std.startsWith(url, 'https://github.com/linuxserver/')
  || std.startsWith(url, 'https://hub.docker.com/')
  || std.startsWith(repo, 'docker-')
  || std.endsWith(repo, '-docker')
  // A repository that exists to build the image, named for that job. Firefly
  // III keeps one on Azure DevOps called MainImage; it is the packaging
  // repository by another name, on another forge.
  || std.endsWith(repo, 'Image')
  || std.endsWith(repo, '-image');

// A label often points into the repository rather than at it — at a tree, a
// blob, or a commit that was current when the image was built. The project is
// the repository, and a link that pins a year-old commit reads as though that
// is where the project lives.
local repoRoot(url) =
  local cut(u, marker) = if std.length(std.findSubstr(marker, u)) > 0 then std.split(u, marker)[0] else u;
  cut(cut(cut(url, '/tree/'), '/blob/'), '/-/');

// What the catalogue says about the software, and separately about the image
// that packages it. The two are different facts and the labels only sometimes
// agree with the one wanted: `org.opencontainers.image.title` documents the
// image, so it holds taglines, base images and editions as often as a product
// name. So the image's own claims are published as the image's, and the
// software's `name` is stated by a maintainer or absent — a wrong display name
// is worse than none, because nobody can tell it is wrong by looking at it.
//
// `upstream` sits between the two: the image's source repository is the
// software's own repository often enough to be worth deriving, so it is —
// except where it is recognisably a packaging repository, where it is dropped
// rather than guessed. An annotation always wins: a maintainer who checked
// beats a label written by a build pipeline.
local softwareFacts(workload) =
  local ann_ = ann.workloads[workload];
  local derived = std.get(upstream, workload, {});
  // What the upstream repository itself said when it was last asked (gen-forge).
  local repoSays = std.get(forge, workload, {});
  local imageEntries =
    (local t = std.get(derived, 'title', null); if t == null then {} else { title: t })
    + (local s = std.get(derived, 'source', null); if s == null then {} else { source: s })
    + (local h = std.get(derived, 'homepage', null); if h == null then {} else { homepage: h });
  (if imageEntries == {} then {} else { image: imageEntries })
  + (local n = std.get(ann_, 'name', null); if n == null then {} else { name: n })
  + licenseFacts(
    workload,
    // The forge beats the image: it resolved the project's own LICENSE file,
    // where the label repeats whatever the build pipeline was told. An
    // annotation beats both, for the cases neither can get right — software
    // that publishes no licence at all, or an identifier the label misspells.
    std.get(ann_, 'license', std.get(repoSays, 'license', std.get(derived, 'license', null))),
    attested=std.objectHas(ann_, 'license'),
  )
  + (
    local labelled = local raw = std.get(derived, 'source', null); if raw == null then null else repoRoot(raw);
    local repo = std.get(
      std.get(ann_, 'upstream', {}),
      'repo',
      if labelled != null && !packagingRepo(labelled) then labelled else null
    );
    local homepage = std.get(std.get(ann_, 'upstream', {}), 'homepage', std.get(repoSays, 'homepage', null));
    local entries = (if repo == null then {} else { repo: repo })
                    + (if homepage == null then {} else { homepage: homepage })
                    // A repository the forge reports as archived says the
                    // project has stopped, which is the kind of thing somebody
                    // deciding whether to run it for years wants told rather
                    // than discovered.
                    + (if std.get(repoSays, 'archived', false) then { archived: true } else {});
    if entries == {} then {} else { upstream: entries }
  )
  + (
    // Every workload states one: a consumer presenting this catalogue decides
    // what to show from it, and an absent category would silently read as
    // "unclassified" for something that is simply new.
    local category = std.get(ann_, 'category', null);
    assert category != null : 'workloads: %s declares no category (one of %s)' % [workload, std.join(', ', categories)];
    assert std.member(categories, category) :
           'workloads: %s declares an unknown category %s' % [workload, category];
    { category: category }
  );

// What bollwerk checks, straight from the policies themselves: their ids, whether
// each is a must or a should, and the BSI requirement it implements. Nothing here
// is transcribed — the annotations are the policies' own.
local bsiPolicies = {
  [item.metadata.name]: {
    id: item.metadata.annotations['policies.opencode.de/ID'],
    category: item.metadata.annotations['policies.opencode.de/category'],
    requirement: item.metadata.annotations['policies.opencode.de/bsi-requirement'],
    protectionRequirement: item.metadata.annotations['policies.opencode.de/bsi-protection-requirement'],
  }
  for item in bollwerk.list.items
  if item.kind == 'ValidatingAdmissionPolicy'
};

// Which of them a stage breaks, as an API server judged it (gen-bsi). A stage the
// generator could not judge — a custom resource whose CRD it does not install —
// carries null rather than an empty list, because "not measured" is not "clean".
local bsiOf(key) =
  if !std.objectHas(bsiViolations, key) then null
  else {
    violates: bsiViolations[key],
    // The requirements those violations touch, deduplicated: a consumer showing
    // a compliance summary wants the requirement, not the policy id.
    requirements: std.set([bsiPolicies[name].requirement for name in bsiViolations[key]]),
  };

local workloadEntries =
  assert reconcile('workload stages', stageKeys, std.objectFields(stageImports));
  // Every generated architecture entry maps to a real stage — a renamed or
  // removed workload leaves no stale arch data behind. (Missing entries are
  // allowed: a new workload reads null until gen-architectures is rerun.)
  assert std.all([std.member(stageKeys, key) for key in std.objectFields(architectures)]) :
         'architectures.gen.libsonnet names a stage that does not exist — rerun gen-architectures';
  // Same discipline for the derived software facts: a renamed or removed
  // workload leaves no stale licence or upstream behind.
  assert std.all([std.objectHas(ann.workloads, key) for key in std.objectFields(upstream)]) :
         'upstream.gen.libsonnet names a workload that does not exist — rerun gen-upstream';
  assert std.all([std.objectHas(ann.workloads, key) for key in std.objectFields(forge)]) :
         'forge.gen.libsonnet names a workload that does not exist — rerun gen-forge';
  assert std.all([std.member(stageKeys, key) for key in std.objectFields(bsiViolations)]) :
         'bsi.gen.libsonnet names a stage that does not exist — rerun gen-bsi';
  assert std.all([
    std.objectHas(bsiPolicies, name)
    for key in std.objectFields(bsiViolations)
    for name in bsiViolations[key]
  ]) : 'bsi.gen.libsonnet names a policy bollwerk no longer ships — rerun gen-bsi';
  assert std.all([
    std.isFunction(stageImports[key])
    for key in std.objectFields(stageImports)
  ]) : 'workloads: every stage import must resolve to a function(params) app';
  [
    {
      id: workload,
      summary: ann.workloads[workload].summary,
      maturity: maturity.of(workload),
    }
    + softwareFacts(workload)
    + {
      // The external infrastructure the workload depends on, hand-annotated —
      // a database (with any PostgreSQL extensions it needs, like vchord), a
      // cache/Redis, and whether it needs S3-compatible object storage
      // (required/optional). Absent when the workload carries none. Backfilled
      // per workload; the derived per-stage `storage.pvcs` below is automatic.
      requires: std.get(ann.workloads[workload], 'requires', {}),
      stages: [
        { id: stage }
        + ann.workloads[workload].stages[stage]
        + { storage: { pvcs: pvcCount(stageImports[workload + '/' + stage]) } }
        + { posture: posture(stageImports[workload + '/' + stage]) }
        + clusterScoped(stageImports[workload + '/' + stage])
        // Which bollwerk policies the stage breaks, from bsi.gen.libsonnet.
        + { bsi: bsiOf(workload + '/' + stage) }
        // The linux CPU architectures the stage's pinned image publishes, from
        // architectures.gen.libsonnet (generated by gen-architectures). null when
        // the image has no entry yet (a new workload before a regen) or the stage
        // pins no image of its own (an operator picks it).
        + { architectures: std.get(architectures, workload + '/' + stage, null) }
        for stage in std.objectFields(ann.workloads[workload].stages)
      ],
    }
    for workload in std.objectFields(ann.workloads)
  ];

{
  // Drift gates — object-level asserts fire when this object is manifested.
  assert reconcile('features', std.objectFields(ann.features), std.objectFieldsAll(features)),
  assert reconcile('expose', std.objectFields(ann.expose), std.objectFieldsAll(expose)),
  assert reconcile('network', std.objectFields(ann.network), std.objectFieldsAll(network)),
  assert reconcile('security', std.objectFields(ann.security), std.objectFieldsAll(security)),
  assert reconcile('migrations', std.objectFields(ann.migrations), std.objectFieldsAll(migrations)),
  // Kinds live in separate files; assert the annotated set is exactly the four
  // main exposes as callables.
  assert reconcile('kinds', std.objectFields(ann.kinds), ['http', 'worker', 'cron', 'daemon', 'stateful', 'job']),
  assert std.all([std.objectHasAll(main, kind) for kind in std.objectFields(ann.kinds)]) :
         'kinds: main.libsonnet must expose every annotated kind',
  // Helpers are top-level fields of main alongside the kinds; assert the
  // annotated set is exactly the rendering terminals main exposes.
  assert reconcile('helpers', std.objectFields(ann.helpers), ['certificate', 'externalSecret', 'join', 'limitRange', 'list', 'mirror', 'priorityClass', 'production', 'resourceQuota']),
  // Every operator-attested production workload must be a real, annotated one —
  // a dangling claim (a typo or a renamed workload) fails here.
  assert std.all([std.objectHas(ann.workloads, name) for name in maturity.productionNames]) :
         'maturity: production.libsonnet names a workload that does not exist',
  assert std.all([std.objectHasAll(main, helper) for helper in std.objectFields(ann.helpers)]) :
         'helpers: main.libsonnet must expose every annotated helper',

  schemaVersion: 1,
  // The values behind kurly.resourcePreset's names, so a consumer sizing (or
  // costing) a deployment reads them instead of keeping its own copy.
  resourcePresets: resourcePresets,
  // The policy set every stage's `bsi` field refers to, with the BSI requirement
  // each one implements.
  bsiPolicies: bsiPolicies,
  workloads: workloadEntries,
  kinds: entries(ann.kinds),
  features: entries(ann.features),
  expose: entries(ann.expose),
  network: entries(ann.network),
  security: entries(ann.security),
  helpers: entries(ann.helpers),
  migrations: entries(ann.migrations),
}
