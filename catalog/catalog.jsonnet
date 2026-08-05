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
local mesh = import '../lib/mesh.libsonnet';
local backup = import '../lib/backup.libsonnet';
local security = import '../lib/security.libsonnet';
local main = import '../main.libsonnet';
local ann = import './annotations.libsonnet';
local architectures = import './architectures.gen.libsonnet';
local bsiViolations = import './bsi.gen.libsonnet';
local bsiOperatorPods = import './bsi-operator.gen.libsonnet';
local pssOperatorPods = import './pss-operator.gen.libsonnet';
local bollwerk = import '../bollwerk/bollwerk.libsonnet';
local excluded = import './excluded.libsonnet';
local consent = import './consent.libsonnet';
local trademark = import './trademark.libsonnet';
local forge = import './forge.gen.libsonnet';
local maturity = import './maturity.libsonnet';
local signatures = import './signatures.gen.libsonnet';
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
  'mautic/server': import 'github.com/metio/kurly/workloads/mautic/server.libsonnet',
  'peertube/server': import 'github.com/metio/kurly/workloads/peertube/server.libsonnet',
  'overleaf/server': import 'github.com/metio/kurly/workloads/overleaf/server.libsonnet',
  'memos/server': import 'github.com/metio/kurly/workloads/memos/server.libsonnet',
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
  'jenkins/server': import 'github.com/metio/kurly/workloads/jenkins/server.libsonnet',
  'alist/server': import 'github.com/metio/kurly/workloads/alist/server.libsonnet',
  'calibre-web-automated/server': import 'github.com/metio/kurly/workloads/calibre-web-automated/server.libsonnet',
  'apprise/server': import 'github.com/metio/kurly/workloads/apprise/server.libsonnet',
  'chatpad/server': import 'github.com/metio/kurly/workloads/chatpad/server.libsonnet',
  'cobalt/server': import 'github.com/metio/kurly/workloads/cobalt/server.libsonnet',
  'davis/server': import 'github.com/metio/kurly/workloads/davis/server.libsonnet',
  'draw-io/server': import 'github.com/metio/kurly/workloads/draw-io/server.libsonnet',
  'ghostfolio/server': import 'github.com/metio/kurly/workloads/ghostfolio/server.libsonnet',
  'hollama/server': import 'github.com/metio/kurly/workloads/hollama/server.libsonnet',
  'lobe-chat/server': import 'github.com/metio/kurly/workloads/lobe-chat/server.libsonnet',
  'leantime/server': import 'github.com/metio/kurly/workloads/leantime/server.libsonnet',
  'mailpit/server': import 'github.com/metio/kurly/workloads/mailpit/server.libsonnet',
  'maloja/server': import 'github.com/metio/kurly/workloads/maloja/server.libsonnet',
  'mermaid-live-editor/server': import 'github.com/metio/kurly/workloads/mermaid-live-editor/server.libsonnet',
  'mazanoke/server': import 'github.com/metio/kurly/workloads/mazanoke/server.libsonnet',
  'owntracks-recorder/server': import 'github.com/metio/kurly/workloads/owntracks-recorder/server.libsonnet',
  'gokapi/server': import 'github.com/metio/kurly/workloads/gokapi/server.libsonnet',
  'pocketbase/server': import 'github.com/metio/kurly/workloads/pocketbase/server.libsonnet',
  'tandoor/server': import 'github.com/metio/kurly/workloads/tandoor/server.libsonnet',
  'smtp4dev/server': import 'github.com/metio/kurly/workloads/smtp4dev/server.libsonnet',
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
  'cassandra-cluster/cluster': import 'github.com/metio/kurly/workloads/cassandra-cluster/cluster.libsonnet',
  'neo4j/server': import 'github.com/metio/kurly/workloads/neo4j/server.libsonnet',
  'ferretdb/server': import 'github.com/metio/kurly/workloads/ferretdb/server.libsonnet',
  'wikijs/server': import 'github.com/metio/kurly/workloads/wikijs/server.libsonnet',
  'bookstack/server': import 'github.com/metio/kurly/workloads/bookstack/server.libsonnet',
  'snipe-it/server': import 'github.com/metio/kurly/workloads/snipe-it/server.libsonnet',
  'rallly/server': import 'github.com/metio/kurly/workloads/rallly/server.libsonnet',
  'shlink/server': import 'github.com/metio/kurly/workloads/shlink/server.libsonnet',
  'roundcube/server': import 'github.com/metio/kurly/workloads/roundcube/server.libsonnet',
  'mediawiki/server': import 'github.com/metio/kurly/workloads/mediawiki/server.libsonnet',
  'firefly-iii/server': import 'github.com/metio/kurly/workloads/firefly-iii/server.libsonnet',
  'fider/server': import 'github.com/metio/kurly/workloads/fider/server.libsonnet',
  'monica/server': import 'github.com/metio/kurly/workloads/monica/server.libsonnet',
  'wallabag/server': import 'github.com/metio/kurly/workloads/wallabag/server.libsonnet',
  'commafeed/server': import 'github.com/metio/kurly/workloads/commafeed/server.libsonnet',
  'lychee/server': import 'github.com/metio/kurly/workloads/lychee/server.libsonnet',
  'photoprism/server': import 'github.com/metio/kurly/workloads/photoprism/server.libsonnet',
  'answer/server': import 'github.com/metio/kurly/workloads/answer/server.libsonnet',
  'blinko/server': import 'github.com/metio/kurly/workloads/blinko/server.libsonnet',
  'docmost/server': import 'github.com/metio/kurly/workloads/docmost/server.libsonnet',
  'greenlight/server': import 'github.com/metio/kurly/workloads/greenlight/server.libsonnet',
  'pilos/server': import 'github.com/metio/kurly/workloads/pilos/server.libsonnet',
  'spegel/mirror': import 'github.com/metio/kurly/workloads/spegel/mirror.libsonnet',
  'homarr/server': import 'github.com/metio/kurly/workloads/homarr/server.libsonnet',
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
  'gogs/server': import 'github.com/metio/kurly/workloads/gogs/server.libsonnet',
  'mealie/server': import 'github.com/metio/kurly/workloads/mealie/server.libsonnet',
  'tautulli/server': import 'github.com/metio/kurly/workloads/tautulli/server.libsonnet',
  'ombi/server': import 'github.com/metio/kurly/workloads/ombi/server.libsonnet',
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
  'davos/server': import 'github.com/metio/kurly/workloads/davos/server.libsonnet',
  'foldingathome/server': import 'github.com/metio/kurly/workloads/foldingathome/server.libsonnet',
  'projectsend/server': import 'github.com/metio/kurly/workloads/projectsend/server.libsonnet',
  'whoogle/server': import 'github.com/metio/kurly/workloads/whoogle/server.libsonnet',
  'mongo-express/server': import 'github.com/metio/kurly/workloads/mongo-express/server.libsonnet',
  'thelounge/server': import 'github.com/metio/kurly/workloads/thelounge/server.libsonnet',
  'mumble/server': import 'github.com/metio/kurly/workloads/mumble/server.libsonnet',
  'tika/server': import 'github.com/metio/kurly/workloads/tika/server.libsonnet',
  'gotenberg/server': import 'github.com/metio/kurly/workloads/gotenberg/server.libsonnet',
  'open-webui/server': import 'github.com/metio/kurly/workloads/open-webui/server.libsonnet',
  'glance/server': import 'github.com/metio/kurly/workloads/glance/server.libsonnet',
  'node-red/server': import 'github.com/metio/kurly/workloads/node-red/server.libsonnet',
  'esphome/server': import 'github.com/metio/kurly/workloads/esphome/server.libsonnet',
  '2fauth/server': import 'github.com/metio/kurly/workloads/2fauth/server.libsonnet',
  'couchdb/server': import 'github.com/metio/kurly/workloads/couchdb/server.libsonnet',
  'home-assistant/server': import 'github.com/metio/kurly/workloads/home-assistant/server.libsonnet',
  'nextcloud/server': import 'github.com/metio/kurly/workloads/nextcloud/server.libsonnet',
  'rundeck/server': import 'github.com/metio/kurly/workloads/rundeck/server.libsonnet',
  'mosquitto/server': import 'github.com/metio/kurly/workloads/mosquitto/server.libsonnet',
  'authelia/server': import 'github.com/metio/kurly/workloads/authelia/server.libsonnet',
  'matrix-conduit/server': import 'github.com/metio/kurly/workloads/matrix-conduit/server.libsonnet',
  'kutt/server': import 'github.com/metio/kurly/workloads/kutt/server.libsonnet',
  'webtrees/server': import 'github.com/metio/kurly/workloads/webtrees/server.libsonnet',
  'postgres/server': import 'github.com/metio/kurly/workloads/postgres/server.libsonnet',
  'nginx-proxy-manager/server': import 'github.com/metio/kurly/workloads/nginx-proxy-manager/server.libsonnet',
  'rabbitmq/server': import 'github.com/metio/kurly/workloads/rabbitmq/server.libsonnet',
  'ollama/server': import 'github.com/metio/kurly/workloads/ollama/server.libsonnet',
  'technitium/server': import 'github.com/metio/kurly/workloads/technitium/server.libsonnet',
  'docker-registry-ui/server': import 'github.com/metio/kurly/workloads/docker-registry-ui/server.libsonnet',
  'element-web/server': import 'github.com/metio/kurly/workloads/element-web/server.libsonnet',
  'photoview/server': import 'github.com/metio/kurly/workloads/photoview/server.libsonnet',
  'yourls/server': import 'github.com/metio/kurly/workloads/yourls/server.libsonnet',
  'pocket-id/server': import 'github.com/metio/kurly/workloads/pocket-id/server.libsonnet',
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
  'misskey/server': import 'github.com/metio/kurly/workloads/misskey/server.libsonnet',
  'lemmy/backend': import 'github.com/metio/kurly/workloads/lemmy/backend.libsonnet',
  'lemmy/ui': import 'github.com/metio/kurly/workloads/lemmy/ui.libsonnet',
  'lemmy/pictrs': import 'github.com/metio/kurly/workloads/lemmy/pictrs.libsonnet',
  'mastodon/web': import 'github.com/metio/kurly/workloads/mastodon/web.libsonnet',
  'mastodon/streaming': import 'github.com/metio/kurly/workloads/mastodon/streaming.libsonnet',
  'mastodon/sidekiq': import 'github.com/metio/kurly/workloads/mastodon/sidekiq.libsonnet',
  'oauth2-proxy/server': import 'github.com/metio/kurly/workloads/oauth2-proxy/server.libsonnet',
  'nats/server': import 'github.com/metio/kurly/workloads/nats/server.libsonnet',
  'volsync/backup': import 'github.com/metio/kurly/workloads/volsync/backup.libsonnet',
  'volsync/restore': import 'github.com/metio/kurly/workloads/volsync/restore.libsonnet',
  'k8up/schedule': import 'github.com/metio/kurly/workloads/k8up/schedule.libsonnet',
  'k8up/backup': import 'github.com/metio/kurly/workloads/k8up/backup.libsonnet',
  'k8up/restore': import 'github.com/metio/kurly/workloads/k8up/restore.libsonnet',
  'cnpg-image-catalog/namespaced': import 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet',
  'cnpg-image-catalog/cluster': import 'github.com/metio/kurly/workloads/cnpg-image-catalog/cluster.libsonnet',
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
  'opengist/server': import 'github.com/metio/kurly/workloads/opengist/server.libsonnet',
  'cloudbeaver/server': import 'github.com/metio/kurly/workloads/cloudbeaver/server.libsonnet',
  'invoiceshelf/server': import 'github.com/metio/kurly/workloads/invoiceshelf/server.libsonnet',
  'srs/server': import 'github.com/metio/kurly/workloads/srs/server.libsonnet',
  'archivebox/server': import 'github.com/metio/kurly/workloads/archivebox/server.libsonnet',
  'centrifugo/server': import 'github.com/metio/kurly/workloads/centrifugo/server.libsonnet',
  'manticore/server': import 'github.com/metio/kurly/workloads/manticore/server.libsonnet',
  'omnitools/server': import 'github.com/metio/kurly/workloads/omnitools/server.libsonnet',
  'warpgate/server': import 'github.com/metio/kurly/workloads/warpgate/server.libsonnet',
  'screego/server': import 'github.com/metio/kurly/workloads/screego/server.libsonnet',
  'cloudreve/server': import 'github.com/metio/kurly/workloads/cloudreve/server.libsonnet',
  'ezbookkeeping/server': import 'github.com/metio/kurly/workloads/ezbookkeeping/server.libsonnet',
  'remark42/server': import 'github.com/metio/kurly/workloads/remark42/server.libsonnet',
  'pinchflat/server': import 'github.com/metio/kurly/workloads/pinchflat/server.libsonnet',
  'isso/server': import 'github.com/metio/kurly/workloads/isso/server.libsonnet',
  'restreamer/server': import 'github.com/metio/kurly/workloads/restreamer/server.libsonnet',
  'speedtest-tracker/server': import 'github.com/metio/kurly/workloads/speedtest-tracker/server.libsonnet',
  'wetty/server': import 'github.com/metio/kurly/workloads/wetty/server.libsonnet',
  'picoshare/server': import 'github.com/metio/kurly/workloads/picoshare/server.libsonnet',
  'wbo/server': import 'github.com/metio/kurly/workloads/wbo/server.libsonnet',
  'spoolman/server': import 'github.com/metio/kurly/workloads/spoolman/server.libsonnet',
  'sqlpage/server': import 'github.com/metio/kurly/workloads/sqlpage/server.libsonnet',
  'myspeed/server': import 'github.com/metio/kurly/workloads/myspeed/server.libsonnet',
  'lubelogger/server': import 'github.com/metio/kurly/workloads/lubelogger/server.libsonnet',
  'yt-dlp-web-ui/server': import 'github.com/metio/kurly/workloads/yt-dlp-web-ui/server.libsonnet',
  'tubesync/server': import 'github.com/metio/kurly/workloads/tubesync/server.libsonnet',
  'libredesk/server': import 'github.com/metio/kurly/workloads/libredesk/server.libsonnet',
  'matchering/server': import 'github.com/metio/kurly/workloads/matchering/server.libsonnet',
  'otterwiki/server': import 'github.com/metio/kurly/workloads/otterwiki/server.libsonnet',
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
// The dependency kinds a workload may declare. A CLOSED list: a consumer that
// PROVISIONS from these has to fail loudly on a term it does not know rather than
// skip it silently, since a dependency nobody stood up is a workload that does not
// run. Published rather than implied by whatever happens to appear.
local requiresKinds = ['database', 'cache', 'objectStorage', 'broker'];

local pssLib = import './pss.libsonnet';
local podTemplates(items) = pssLib.podTemplates(items);

// Which database engine a workload connects to, established rather than guessed.
// Absent when nothing establishes it — which a consumer must read as unknown, and
// never as "the usual one".
//
// The precedence is the one the delivery harness arrived at by being wrong twice:
//
//   1. a DECLARED SQL url in the workload's secretKeys. postgresUrl/mysqlUrl is
//      somebody stating what the app connects to. It wins outright, and that is
//      load-bearing rather than tidy: ferretdb speaks the MongoDB PROTOCOL while
//      storing in PostgreSQL, so its stage and its Secret are full of Mongo and
//      its generator says postgresUrl. Reading the protocol takes its database
//      away.
//   2. otherwise MONGO in a Secret key or an env var NAME the stage sets.
//      rocketchat and wekan are MongoDB and neither declares a url generator; both
//      were handed a PostgreSQL until this was read.
//   3. otherwise POSTGRES/PG or MYSQL/MARIADB in an env var name the stage sets.
//      An env var is the workload being wired to something; prose in a comment is
//      a sentence about it, and grepping that misclassified 28 of 37 workloads.
local envNames(fn) = std.flattenArrays([
  [std.get(e, 'name', '') for e in std.get(c, 'env', [])]
  for t in podTemplates(main.list(fn()).items)
  for c in std.get(t.spec, 'containers', [])
]);
local anyContains(names, needle) = std.any([std.length(std.findSubstr(needle, n)) > 0 for n in names]);
local databaseEngine(workload, stageFns) =
  local gens = [
    std.get(k, 'generate', '')
    for stage in std.objectFields(ann.workloads[workload].stages)
    for k in std.get(ann.workloads[workload].stages[stage], 'secretKeys', [])
  ];
  local keys = [
    std.get(k, 'key', '')
    for stage in std.objectFields(ann.workloads[workload].stages)
    for k in std.get(ann.workloads[workload].stages[stage], 'secretKeys', [])
  ];
  local names = std.flattenArrays([envNames(fn) for fn in stageFns]) + keys;
  if std.member(gens, 'postgresUrl') then 'postgresql'
  else if std.member(gens, 'mysqlUrl') then 'mysql'
  // Declaring an extension states the engine: every extension named in this
  // catalogue is a PostgreSQL one, and immich's vchord is why the field exists.
  else if std.objectHas(std.get(ann.workloads[workload], 'requires', {}), 'databaseExtensions') then 'postgresql'
  else if anyContains(names, 'MONGO') then 'mongodb'
  else if anyContains(names, 'POSTGRES') || anyContains(names, 'PGHOST') then 'postgresql'
  else if anyContains(names, 'MYSQL') || anyContains(names, 'MARIADB') then 'mysql'
  else null;

// v1's `requires` object becomes a LIST, because a workload can need two of the
// same kind and an object cannot say so: bigcapital needs a MySQL AND a MongoDB,
// and an object keyed by kind can only name one — so a consumer provisioning from
// it stands up one server and the workload never starts.
local requiresV2(workload, stageFns) =
  local declared = std.get(ann.workloads[workload], 'requires', {});
  // A workload may state the list outright, for what derivation cannot reach: two
  // dependencies of the SAME kind. bigcapital needs a MySQL and a MongoDB, and an
  // object keyed by kind can only say "a database".
  if std.isArray(declared) then declared else
    local v1 = declared;
    local engine = databaseEngine(workload, stageFns);
    [
      { kind: kind, required: v1[kind] == 'required' }
      + (
        if kind == 'database' then
          (if engine != null then { engine: engine } else {})
          + (if std.objectHas(v1, 'databaseExtensions') then { extensions: v1.databaseExtensions } else {})
        else {}
      )
      for kind in requiresKinds
      if std.objectHas(v1, kind)
    ];


// What a stage would actually run, derived by rendering it — so it cannot drift
// from the pin, and nobody transcribes a version into the catalogue. Two shapes,
// deliberately not flattened into one:
//
//   image   — the reference the stage's own container carries, tag and digest
//             exactly as pinned. This is what a consumer compares against the
//             upstream release to say "you are on 34.0.1, 34.0.2 is out"; the
//             digest, where the pin carries one, answers the different question
//             of whether the bits changed while the version did not.
//   version — what a stage asks an OPERATOR for, where the operator resolves it
//             to an image (a MySQL InnoDBCluster's serverVersion, an
//             OpenSearch cluster's version). Calling that an image would be a
//             lie: kurly never names one, and which image the operator picks is
//             the operator's business.
//
// Both are absent for a stage that states neither — a CNPG Cluster or a
// LokiStack takes whatever image its operator defaults to, and inventing a
// version for it would be worse than saying nothing.
local containersOf(tmpl) = std.get(tmpl.spec, 'containers', []) + std.get(tmpl.spec, 'initContainers', []);

// The two facts an image reference carries, published separately so that no
// consumer takes a reference apart. They drive opposite behaviour: a changed tag
// is new software and deserves a change window, while a changed digest alone is
// the same software rebuilt — usually a patched base image — which deserves to
// be applied promptly and belongs to nobody's "hold major versions" setting.
// Deriving that distinction by string surgery is how a tenant who asked to defer
// a feature change silently defers a security patch instead.
//
// The splitting happens ONCE, here, because it is easy to get wrong: a registry
// with a port puts a colon in the host, and a digest-pinned reference carries
// `:tag@sha256:…`, so a split on the first colon yields `1.2@sha256`. That
// happened in this repository, to a workload that handed the result to an
// operator as the version to run.
//
// `digest` appears only where the REFERENCE carries one, which makes it a
// guarantee about what will be deployed rather than an observation of what a
// registry happened to hold when it was last asked. Those are different facts
// and do not share a field.
local referenceParts(reference) =
  local withoutDigest = std.split(reference, '@')[0];
  local digestParts = std.split(reference, '@sha256:');
  local tagParts = std.split(withoutDigest, ':');
  // A reference need not carry a tag at all — a bare name, or name@digest.
  (if std.length(tagParts) > 1 then { tag: tagParts[std.length(tagParts) - 1] } else {})
  + (if std.length(digestParts) > 1 then { digest: 'sha256:' + digestParts[1] } else {});

local runs(fn) =
  local items = main.list(fn()).items;
  local tmpls = podTemplates(items);
  // The workload's own container is the first one: the kinds build the pod from
  // `container::` and features append beside it, so a sidecar or an init never
  // displaces it.
  local own = if tmpls == [] then [] else std.get(tmpls[0].spec, 'containers', []);
  local everyImage = std.set([c.image for t in tmpls for c in containersOf(t) if std.objectHas(c, 'image')]);
  if own != [] then
    { image: own[0].image } + referenceParts(own[0].image)
    // A stage that also runs a sidecar or an init container ships more than one
    // image, and each is its own update to track — a rebuilt nginx beside an
    // unchanged application is exactly the case a single field would hide.
    + (
      local rest = [i for i in everyImage if i != own[0].image];
      if rest == [] then {} else { alsoRuns: rest }
    )
  else
    // A custom resource: find the version it states, wherever the operator's
    // schema puts it. Only the fields kurly itself writes are read, so this
    // reports a pin rather than guessing at an operator's defaulting.
    local specs = [m.spec for m in items if std.objectHas(m, 'spec')];
    local stated = [
      spec[field]
      for spec in specs
      for field in ['version', 'serverVersion', 'opensearchVersion']
      if std.objectHas(spec, field) && std.isString(spec[field])
    ];
    local nested = [
      spec.general.version
      for spec in specs
      if std.objectHas(spec, 'general') && std.objectHas(spec.general, 'version')
    ];
    local images = [
      entry.image
      for spec in specs
      for entry in std.get(spec, 'images', [])
      if std.isObject(entry) && std.objectHas(entry, 'image')
    ];
    local direct = [spec.image for spec in specs if std.objectHas(spec, 'image') && std.isString(spec.image)];
    if direct != [] then { image: direct[0] } + referenceParts(direct[0])
    else if images != [] then
      { image: images[0] } + referenceParts(images[0])
      + (if std.length(images) > 1 then { alsoRuns: images[1:] } else {})
    else if stated + nested != [] then { version: (stated + nested)[0] }
    else {};

// The multi-tenant security posture a stage's DEFAULT render carries, derived
// (like storage.pvcs) so it never drifts from what the workload emits — the
// portal reads it to refuse or gate the recipes that need root before hosting a
// stranger's workload on a shared node. `null` for a custom-resource stage whose
// pods the operator (not kurly) runs, so the posture is not kurly's to state.
//   runsAsRoot           — a pod without runAsNonRoot (kurly.rootUser / privileged)
//   writableRootFilesystem — a container without a read-only root fs
//   ownUserNamespace     — hostUsers:false, so a breakout lands unprivileged on the host
//   multiTenantSafe      — none of the above relaxations; the hardened default stands
// What a stage's DEFAULT render ASKS THE SCHEDULER FOR, container by container.
//
// Deliberately not called a minimum, because it is not one. A request is hand-set
// by whoever wrote the stage, and asking is not needing in either direction: most
// of these would run in less than they ask for, and baserow asked for less than it
// needed and would not start until it was given 4Gi. The only floor anybody here
// has established was established by a failure, not by a number in a source file.
//
// So a consumer may use this to PRE-SELECT a size — round up to something that
// covers it — and must not use it to refuse one. Refusing below this would forbid
// a knowledgeable operator from running a workload in less than its packaging
// asks for, which is legitimate, while still admitting the one case known to
// fail. A limit that has actually been PROVEN too small is a different fact and
// lives in resource-floors.libsonnet. Null where a stage runs no pods of kurly's
// (an operator's custom resource).
local declaredRequests(fn) =
  local tmpls = podTemplates(main.list(fn()).items);
  if tmpls == [] then null
  else
    // PER CONTAINER, with which kind each one is, rather than one number for the
    // pod. A pod's effective request is not the sum of its containers':
    //
    //     max( sum(regular containers), max(init containers) )
    //
    // because init containers run to completion before the others start, so their
    // requests overlap rather than add, while a sidecar (a restartable init
    // container) runs alongside and counts in the sum. Plain addition over a pod
    // with a heavy init container overstates it, sometimes badly.
    //
    // That rule is a DERIVATION, and deriving it here would also mean parsing and
    // adding Kubernetes quantities ('250m' + '1', '768Mi' + '1Gi') — two ways to be
    // confidently wrong about a number somebody sizes an order from. So the parts
    // are published and the arithmetic belongs to whoever needs the total.
    local kindOf(t, c) =
      if std.member([i.name for i in std.get(t.spec, 'initContainers', [])], c.name) then
        (if std.get(c, 'restartPolicy', '') == 'Always' then 'sidecar' else 'init')
      else 'regular';
    local entries(t) = [
      { name: c.name, kind: kindOf(t, c) }
      + (
        local reqs = std.get(std.get(c, 'resources', {}), 'requests', {});
        (if std.objectHas(reqs, 'cpu') then { cpu: reqs.cpu } else {})
        + (if std.objectHas(reqs, 'memory') then { memory: reqs.memory } else {})
      )
      for c in std.get(t.spec, 'containers', []) + std.get(t.spec, 'initContainers', [])
    ];
    std.flattenArrays([entries(t) for t in tmpls]);

// What the stage's STORAGE TOPOLOGY permits by way of replicas — the fact any
// "production profile" has to consult before it does anything, because on most
// of this catalogue "make it highly available" is not a setting.
//
// A Deployment that owns a ReadWriteOnce claim cannot run a second replica: the
// volume attaches to one node, so the second pod sits Pending forever. Handing
// such a workload replicas=3 does not make it available, it makes it down. That
// is the common case here, not the exception.
//
// Read from what the stage RENDERS, like posture and storage.pvcs:
//
//   stateless     no owned volume stands in the way
//   singleWriter  a Deployment owning a ReadWriteOnce claim — one replica, full stop
//   sharedVolume  a Deployment owning a ReadWriteMany claim — the volume allows
//                 more than one; whether the APPLICATION does is not ours to say
//   perPod        a StatefulSet with volumeClaimTemplates — each replica its own
//   perNode       a DaemonSet — one per node by definition
//   oneOff        a Job or CronJob, where replicas is not the question
//
// `horizontal` is the single bit a caller needs: whether more than one replica
// is possible WITHOUT changing the storage. It is deliberately false for
// sharedVolume too — a ReadWriteMany volume makes concurrency possible, and
// plenty of applications corrupt themselves given it. Saying "yes" there would
// be inferring an application property from a storage one.
// What kurly.production() actually DOES to this stage — rendered by CALLING it,
// never written down beside it.
//
// The distinction is the whole value of the field. A table of recommended
// settings maintained next to the function is a second implementation, and the
// day the two disagree a consumer shows somebody a preview of a deployment that
// does not happen — a promise made in the one place a reader has every reason to
// trust, about the one thing they came to check. So this asks the function and
// records its answer.
//
// The ask is CANONICAL and stated, not a recommendation: three replicas, a
// disruption budget of two, one spread constraint. Nobody should read `asked` as
// advice about how many replicas a workload wants. It is a probe, chosen high
// enough that every clamp fires.
//
// `clamped` is the interesting half. Without it a reader learns that vaultwarden
// gets one replica; with it they learn that three were asked for and the software
// cannot take them, which is the sentence a tenant actually needs — and
// reconstructing it by diffing against an invented profile would be guessing at
// this logic from outside, which is the drift again by another route.
// Every Secret a stage CONSUMES, and how — derived by rendering it.
//
// `secretKeys` says what a Secret must CONTAIN and how to mint each key. It
// does not say that a Secret is needed at all, which is the question a portal
// asks first, and 12 stages mount one while declaring no keys — so the catalogue
// was silent about a hard prerequisite for exactly the workloads that cannot be
// deployed without a human writing something.
//
// The two facts are complementary rather than overlapping:
//
//   secrets     WHICH Secrets this stage reads, and whether as environment or as
//               files at a path. Derived, so it cannot drift from the manifest.
//   secretKeys  what to put in them, where kurly can say. Hand-annotated,
//               because an application's env contract is not derivable.
//
// A Secret in `secrets` with no matching `secretKeys` is the honest signal that
// somebody must author its contents: thanos/store wants an objstore.yml naming a
// bucket, dex/server a config with its connectors. Neither is a password a
// generator can mint, and pretending otherwise by inventing a `generate: document`
// would hand a portal a job it cannot do while telling it the job was done.
local secretsOf(fn) =
  local items = main.list(fn()).items;
  local tmpls = pssLib.podTemplates(items);
  if tmpls == [] then null
  else
    // A Secret mounted as files: the volume names it, and the mount that carries
    // that volume gives the path the application reads it from.
    local mounted = std.set(std.flattenArrays([
      [
        {
          name: v.secret.secretName,
          as: 'file',
          path: m.mountPath,
        }
        for v in std.get(t.spec, 'volumes', [])
        if std.objectHas(v, 'secret')
        for c in std.get(t.spec, 'containers', [])
        for m in std.get(c, 'volumeMounts', [])
        if m.name == v.name
      ]
      for t in tmpls
    ]), function(e) e.name + e.path);
    // A Secret read as environment, whole (envFrom) or one key at a time.
    local fromEnv = std.set(std.flattenArrays([
      [
        { name: e.secretRef.name, as: 'environment' }
        for c in std.get(t.spec, 'containers', [])
        for e in std.get(c, 'envFrom', [])
        if std.objectHas(e, 'secretRef')
      ]
      + [
        { name: v.valueFrom.secretKeyRef.name, as: 'environment' }
        for c in std.get(t.spec, 'containers', [])
        for v in std.get(c, 'env', [])
        if std.objectHas(v, 'valueFrom') && std.objectHas(v.valueFrom, 'secretKeyRef')
      ]
      for t in tmpls
    ]), function(e) e.name);
    local all = mounted + fromEnv;
    if all == [] then [] else std.sort(all, function(e) e.as + e.name);

local profileAsk = { replicas: 3, podDisruptionBudget: 2, topologySpreadConstraints: 1 };
local profile(fn) =
  local app = fn();
  // A stage that renders plain manifests rather than composing a kurly base
  // rejects every feature, so production() cannot be asked about it at all.
  if !std.objectHasAll(app, 'config') then null
  else
    local rendered = main.list(main.production(
      app,
      replicas=profileAsk.replicas,
      pdb=profileAsk.podDisruptionBudget,
      spread=['kubernetes.io/hostname'],
    )).items;
    // Every controller kind that carries a pod template, DaemonSet included — a
    // list that stopped at Deployment and StatefulSet read a DaemonSet's spread
    // constraints as absent and reported them clamped, which is a measurement
    // reporting itself as a finding.
    local controllers = [
      i
      for i in rendered
      if std.member(['Deployment', 'StatefulSet', 'DaemonSet'], std.get(i, 'kind', ''))
    ];
    local budgets = [i for i in rendered if std.get(i, 'kind', '') == 'PodDisruptionBudget'];
    local got = {
      replicas:
        if controllers == [] then null
        else std.get(controllers[0].spec, 'replicas', null),
      podDisruptionBudget:
        if budgets == [] then null else std.get(budgets[0].spec, 'minAvailable', null),
      topologySpreadConstraints:
        if controllers == [] then 0
        else std.length(std.get(controllers[0].spec.template.spec, 'topologySpreadConstraints', [])),
    };
    {
      asked: profileAsk,
      got: got,
      // A null in `got` means the workload HAS NO SUCH KNOB — a DaemonSet has no
      // replica count — which is a different thing from an ask that was reduced,
      // and must not be reported as one.
      clamped: [
        k
        for k in std.objectFields(profileAsk)
        if got[k] != null && got[k] != profileAsk[k]
      ],
    };

local scaling(fn) =
  local items = main.list(fn()).items;
  local controllers = [i for i in items if std.member(['Deployment', 'StatefulSet', 'DaemonSet', 'Job', 'CronJob'], std.get(i, 'kind', ''))];
  local ownedClaims = [i for i in items if std.get(i, 'kind', '') == 'PersistentVolumeClaim'];
  local anyRWX = std.any([
    std.member(std.get(std.get(c, 'spec', {}), 'accessModes', []), 'ReadWriteMany')
    for c in ownedClaims
  ]);
  local kinds = std.set([c.kind for c in controllers]);
  if controllers == [] then null
  else
    local topology =
      if std.member(kinds, 'DaemonSet') then 'perNode'
      else if std.member(kinds, 'StatefulSet') then 'perPod'
      else if std.member(kinds, 'Deployment') && ownedClaims != [] then (if anyRWX then 'sharedVolume' else 'singleWriter')
      else if std.member(kinds, 'Deployment') then 'stateless'
      else 'oneOff';
    {
      topology: topology,
      horizontal: std.member(['stateless', 'perPod'], topology),
      replicas: std.foldl(
        function(acc, c) if std.objectHas(std.get(c, 'spec', {}), 'replicas') then c.spec.replicas else acc,
        controllers,
        null
      ),
    };

local posture(fn) =
  local items = main.list(fn()).items;
  local tmpls = podTemplates(items);
  // A custom resource whose schema takes a POD securityContext, which kurly
  // fills in — the Prometheus operator's CRD is one. The operator creates the
  // pod, but what that pod runs as is stated here, in kurly's manifest, so the
  // posture IS kurly's to report. Reading it as "not ours to state" published a
  // null for a stage that says runAsNonRoot: true in plain sight.
  //
  // Only a pod-level securityContext counts. A CR field of the same name that
  // configures something else would be a different thing wearing the word.
  local crPodSecurity = [
    item.spec.securityContext
    for item in items
    if std.objectHas(item, 'spec')
       && std.isObject(std.get(item.spec, 'securityContext', null))
       && !std.objectHas(item.spec, 'template')
       && std.length(std.setInter(
         std.set(std.objectFields(item.spec.securityContext)),
         ['runAsNonRoot', 'runAsUser', 'fsGroup', 'seccompProfile']
       )) > 0
  ];
  if tmpls == [] && crPodSecurity != [] then
    // No container list to read, so the container-level halves are unknown
    // rather than false: the operator decides them.
    local nonRoot = std.all([std.get(c, 'runAsNonRoot', false) for c in crPodSecurity]);
    {
      runsAsRoot: !nonRoot,
      writableRootFilesystem: null,
      ownUserNamespace: null,
      multiTenantSafe: null,
    }
  else if tmpls == [] then null
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
  // A deprecated GPL-family identifier does not say whether the project chose
  // "version N only" or "version N or, at your option, any later version" — the
  // reason SPDX deprecated the bare spelling.
  //
  // Where a project does not say, the resolved value is -only, because the later
  // -version permission is something a licence GRANTS: absent the grant, only the
  // stated version applies, and reading a broader permission into silence is the
  // one direction of error that lets somebody combine code in ways the licence
  // does not allow. It is also what SPDX advises for a notice without the
  // or-later wording. Every workload that DOES say — thirty of them, from a
  // REUSE licence filename, a package manifest, a python classifier, an SPDX
  // header or the boilerplate in a source file — carries an annotation stating
  // which, and an annotation always wins.
  local resolveVariant(id) =
    if std.objectHas(spdx, id) && spdx[id].deprecated && std.objectHas(spdx, id + '-only')
    then id + '-only'
    else id;
  local identifiers = [resolveVariant(canonical(id)) for id in rawIdentifiers];
  local assumed = [canonical(id) for id in rawIdentifiers] != identifiers;
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
        if std.member(['AND', 'OR', 'WITH'], token) then token
        else resolveVariant(canonical(std.stripChars(token, '()')))
        for token in std.split(value, ' ')
      ]),
    }
    // Only a single identifier answers "is this open source" on its own. An
    // expression needs reading — an OR of a permissive and a proprietary
    // licence is a choice, an AND is a conjunction — so the flag is left off
    // rather than resolved to a side.
    + (
      // Whether a licensee ends up under an OSI-approved licence, evaluated over
      // the OPERANDS rather than over the string. `A OR B` gives the licensee
      // the choice, so one approved operand is enough; `A AND B` binds them to
      // every operand, so all must be. A LicenseRef- is by definition on no
      // list, which is the point of the namespace — so it is never approved,
      // and that is what makes `SSPL-1.0 OR LicenseRef-…` come out false rather
      // than true on the presence of an OR.
      //
      // `WITH` attaches an exception to the licence before it, so the licence
      // decides. Anything this cannot read — parentheses, or AND and OR mixed
      // without them, where precedence is genuinely ambiguous — leaves the field
      // ABSENT. A determination that was not made must not be published as
      // false: a consumer cannot tell a fabricated false from a real one.
      local approvedOperand(id) = std.objectHas(spdx, id) && spdx[id].osiApproved;
      local operators = [t for t in std.split(value, ' ') if std.member(['AND', 'OR', 'WITH'], t)];
      local ops = std.set(operators);
      local withOperands = [
        // `A WITH e` is decided by A, so the exception is dropped before the
        // operands are weighed.
        identifiers[i]
        for i in std.range(0, std.length(identifiers) - 1)
        if i == 0 || operators[i - 1] != 'WITH'
      ];
      local parenthesised = std.length(std.findSubstr('(', value)) > 0;
      local ambiguous = std.length(std.setInter(ops, ['AND', 'OR'])) > 1;
      if parenthesised || ambiguous then {}
      else if std.member(ops, 'OR') then
        { licenseOsiApproved: std.any([approvedOperand(id) for id in withOperands]) }
      else
        { licenseOsiApproved: std.all([approvedOperand(id) for id in withOperands]) }
    )
    + (if std.any([std.objectHas(spdx, id) && spdx[id].deprecated for id in identifiers]) then { licenseDeprecated: true } else {})
    + (if assumed then { licenseVariantAssumed: true } else {});

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
  || std.endsWith(repo, '-image')
  // A project that keeps its packaging beside itself names the repository for
  // the job rather than for the software: hedgedoc/container, jenkinsci/docker,
  // monicahq/docker, phpmyadmin/docker. Same org, still not the application.
  || repo == 'docker'
  || repo == 'container'
  || repo == 'containers';

// A label often points into the repository rather than at it — at a tree, a
// blob, or a commit that was current when the image was built. The project is
// the repository, and a link that pins a year-old commit reads as though that
// is where the project lives.
local repoRoot(url) =
  // Cut at the EARLIEST marker present rather than at each in turn: GitLab nests
  // one inside another (`…/immich/-/tree/main`), so cutting at `/tree/` first
  // leaves `…/immich/-`, and the later `/-/` pass no longer matches — yielding a
  // repository with a stray `/-` on the end.
  local at(marker) =
    local found = std.findSubstr(marker, url);
    if found == [] then null else found[0];
  local positions = std.sort([p for p in [at('/-/'), at('/tree/'), at('/blob/')] if p != null]);
  if positions == [] then url else url[0:positions[0]];

// The repository the SOFTWARE lives in: an annotation where a maintainer stated
// one, otherwise the image's own source label — unless that label points at a
// packaging repository, which credits the wrong people and is dropped instead of
// guessed. null where nothing establishes it.
//
// Shared, because two things need the same answer: the `upstream` a consumer
// reads, and the signature check asking whether the signer is this project. Two
// derivations of the same repository could disagree, and the one that disagreed
// would decide whether a supply chain marker is shown.
local upstreamRepo(workload) =
  local labelled =
    local raw = std.get(std.get(upstream, workload, {}), 'source', null);
    if raw == null then null else repoRoot(raw);
  std.get(
    std.get(ann.workloads[workload], 'upstream', {}),
    'repo',
    if labelled != null && !packagingRepo(labelled) then labelled else null
  );

// Whether the stage's image carries a verifiable sigstore signature, and whether
// the thing that signed it is the project itself.
//
// The claim is published only while the measured digest is still the stage's
// pin. A signature covers specific bytes; carried forward onto an image Renovate
// bumped afterwards it would be a supply chain assurance about bits nobody
// checked — so the claim goes null and the sweep is what brings it back.
//
// `signedByUpstream` is the one worth a marker in a user interface. `signed`
// alone says a signature verified, which any publisher of any image can arrange
// for their own; only the comparison against the repository the software lives
// in says the project released this. Where either side is unknown the field is
// ABSENT, because "we could not tell" and "signed by somebody else" are opposite
// answers and a consumer must not read one as the other.
local signatureOf(workload, stage, pinnedDigest) =
  local entry = std.get(signatures, workload + '/' + stage, null);
  local normalize(url) = std.asciiLower(std.stripChars(std.stripChars(url, '/'), '.git'));
  if entry == null || pinnedDigest == null || std.get(entry, 'digest', null) != pinnedDigest then null
  else if !entry.signed then { signed: false }
  else
    local signer = std.get(entry, 'sourceRepository', null);
    local ours = upstreamRepo(workload);
    { signed: true }
    + (local v = std.get(entry, 'identity', null); if v == null then {} else { identity: v })
    + (local v = std.get(entry, 'issuer', null); if v == null then {} else { issuer: v })
    + (if signer == null then {} else { sourceRepository: signer })
    + (
      if signer == null || ours == null then {}
      else { signedByUpstream: normalize(signer) == normalize(ours) }
    );

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
    local repo = upstreamRepo(workload);
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
// The Kubernetes kinds bollwerk's policies select. Derived from the policies
// themselves rather than listed by hand, so a new matchConstraint widens this
// automatically — with a map from the plural resource name to the kind, because
// `daemonsets` -> `DaemonSet` is not a rule any string function knows.
local kindOfResource = bollwerk.resourceKinds;
local bollwerkResources = std.set([
  resource
  for policy in bollwerk.list.items
  if policy.kind == 'ValidatingAdmissionPolicy'
  for rule in policy.spec.matchConstraints.resourceRules
  for resource in rule.resources
]);
// A resource bollwerk started matching that this file cannot name is a silent
// narrowing of scope — every stage rendering only that kind would quietly read
// as out of scope. Fail instead.
assert std.all([std.objectHas(kindOfResource, r) for r in bollwerkResources]) :
       'catalog: bollwerk matches a resource kindOfResource does not name — %s' % [
  [r for r in bollwerkResources if !std.objectHas(kindOfResource, r)],
];
local bollwerkKinds = std.set([kindOfResource[r] for r in bollwerkResources]);

// What the bollwerk policies say about a stage, in three states rather than two.
//
// A stage that renders ONLY custom resources — a Prometheus, a LokiStack, a CNPG
// Cluster — is not unmeasured: no policy has a matchConstraint that selects any
// of it, so there is nothing for them to say. Installing the operator would not
// change that. `applicable: false` states it, where a null would leave a
// consumer unable to tell "no rule reaches this" from "nobody asked".
//
// null still means nobody asked, and still must never be read as compliant.
local bsiOf(key, fn) =
  local kinds = std.set([item.kind for item in main.list(fn()).items]);
  local inScope = std.setInter(kinds, bollwerkKinds);
  // What the operator's pods were measured to violate, where that was measured.
  // It rides on both branches: a stage out of scope for its own manifest still
  // has pods, and a stage whose manifest IS judged may ALSO have an operator
  // making more of them.
  local operatorPods =
    local m = std.get(bsiOperatorPods, key, null);
    if m == null then {} else { operatorPods: m };
  if std.length(inScope) == 0 then { applicable: false } + operatorPods
  else if !std.objectHas(bsiViolations, key) then null
  else {
    violates: bsiViolations[key],
    // The requirements those violations touch, deduplicated: a consumer showing
    // a compliance summary wants the requirement, not the policy id.
    requirements: std.set([bsiPolicies[name].requirement for name in bsiViolations[key]]),
  } + operatorPods;

// The reasons a workload is not carried. Closed, and published, so a consumer
// switches on the reason rather than reading the sentence beside it — rendering
// all of them as "not offered" says the same thing about a proprietary media
// server and about a project whose authors sell their own hosting.
//
// `upstream-hosts-it-free` is the newest and the least obvious, so it is worth
// stating plainly: it is NOT a judgement about the software or its authors. A
// project that runs a free instance of itself has already answered the question a
// paid hosting offer asks, and answered it at a price nothing can undercut. There
// is no version of this catalogue that competes with free, so carrying such a
// workload would cost the operator work and offer the user nothing they cannot
// already have. It sits beside `upstream-sells-hosting` rather than inside it
// because the two are different facts and a consumer may reasonably treat them
// differently — one is a business conflict, the other simply an absent need.
local excludedReasons = [
  'licence-forbids-saas',
  'no-published-source',
  'undeployable',
  'upstream-archived',
  'upstream-hosts-it-free',
  'upstream-sells-hosting',
];

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
  assert std.all([std.member(stageKeys, key) for key in std.objectFields(bsiOperatorPods)]) :
         'bsi-operator.gen.libsonnet names a stage that does not exist';
  assert std.all([std.member(stageKeys, key) for key in std.objectFields(pssOperatorPods)]) :
         'pss-operator.gen.libsonnet names a stage that does not exist — rerun cr-pss.sh';
  // A measured verdict is only meaningful for a stage whose own manifest could
  // not be judged. If a stage grew a pod template, its derived `pss` is the
  // better evidence and the measured one must not sit beside it pretending to
  // add something.
  assert std.all([
    pssLib.of(main.list(stageImports[key]()).items) == null
    for key in std.objectFields(pssOperatorPods)
  ]) : 'pss-operator.gen.libsonnet measures a stage that now renders its own pod template — its derived pss is the better evidence, so drop the measured one';
  assert std.all([
    std.objectHas(bsiPolicies, name)
    for key in std.objectFields(bsiOperatorPods)
    for name in bsiOperatorPods[key].violates
  ]) : 'bsi-operator.gen.libsonnet names a policy bollwerk no longer ships';
  // Signature entries are checked for staleness but never for completeness: an
  // image bump invalidates the CLAIM (the digest no longer matches) while
  // leaving the key in place, so a full set of keys would prove nothing about
  // freshness. What keeps the claims true is the digest comparison, not a count.
  assert std.all([std.member(stageKeys, key) for key in std.objectFields(signatures)]) :
         'signatures.gen.libsonnet names a stage that does not exist — rerun gen-signatures';
  assert std.all([
    std.objectHas(bsiPolicies, name)
    for key in std.objectFields(bsiViolations)
    for name in bsiViolations[key]
  ]) : 'bsi.gen.libsonnet names a policy bollwerk no longer ships — rerun gen-bsi';
  assert std.all([
    std.isFunction(stageImports[key])
    for key in std.objectFields(stageImports)
  ]) : 'workloads: every stage import must resolve to a function(params) app';
  // `description` is one sentence for somebody deciding whether they WANT the
  // software; `summary` is for somebody deciding how to RUN it. They are kept
  // apart for the reason `consent` and `trademark` were: a field with an
  // audience must not be quietly reused for a different one. Absent is a real
  // answer and the common one — a shop would rather show a technical summary
  // than a sentence somebody generated to fill a field.
  //
  // The three rules the portal asked for are enforced here rather than
  // documented, because a guard that only exists in prose is one nobody runs:
  // one sentence, never opening with the software's own name (the card already
  // carries it as a heading), no deployment mechanics, and no marketing.
  local mechanicsWords = [
    'configmap',
    'persistentvolume',
    'readwriteonce',
    'readwritemany',
    'pvc',
    'replica',
    'statefulset',
    'deployment',
    'sidecar',
    'ingress',
    'kubernetes',
    'container',
    'official image',
    'serves on',
    'stateless',
    'volume',
    'port ',
  ];
  local marketingWords = [
    'powerful',
    'seamless',
    'enterprise-grade',
    'best-in-class',
    'blazing',
    'cutting-edge',
    'world-class',
    'next-generation',
    'revolutionary',
    'robust',
  ];
  // Every catalogued workload carries one today. It stays OPTIONAL rather than
  // required: a workload arriving without a good sentence should be published
  // without one, not with a filler that a shop would then render.
  local descriptionOf(workload) =
    local w = ann.workloads[workload];
    if !std.objectHas(w, 'description') then {}
    else
      local d = w.description;
      local lower = std.asciiLower(d);
      local displayName = std.get(w, 'name', workload);
      assert std.length(d) <= 160 :
             'workloads.%s.description must fit one line (<=160 chars), got %d' % [workload, std.length(d)];
      assert std.endsWith(d, '.') && std.length(std.findSubstr('. ', d)) == 0 :
             'workloads.%s.description must be ONE sentence ending in a full stop' % workload;
      assert !std.startsWith(lower, std.asciiLower(displayName) + ' ') :
             'workloads.%s.description must not open with the software name — the card already shows it' % workload;
      assert std.all([std.length(std.findSubstr(t, lower)) == 0 for t in mechanicsWords]) :
             'workloads.%s.description names deployment mechanics — that belongs in summary' % workload;
      assert std.all([std.length(std.findSubstr(t, lower)) == 0 for t in marketingWords]) :
             'workloads.%s.description reads as marketing — plain is the register' % workload;
      { description: d };

  [
    {
      id: workload,
      summary: ann.workloads[workload].summary,
      maturity: maturity.of(workload),
    }
    + descriptionOf(workload)
    + softwareFacts(workload)
    // What the PROJECT's trademark policy says. ABSENT means nobody looked, and
    // a consumer must not read that as permission — a trademark binds whether or
    // not its holder has heard of the person publishing this. Deliberately never
    // derived from `license`: the code grant and the mark are separate and
    // routinely disagree.
    + (local t = std.get(trademark, workload, null); if t == null then {} else { trademark: t })
    + {
      // The external infrastructure the workload depends on: a LIST of
      // { kind, required, engine?, extensions? }. Which kinds it needs is
      // hand-annotated; which database ENGINE is derived, and absent where
      // nothing establishes it. Empty when the workload depends on nothing.
      requires: requiresV2(workload, [
        stageImports[workload + '/' + stage]
        for stage in std.objectFields(ann.workloads[workload].stages)
      ]),
      stages: [
        { id: stage }
        + ann.workloads[workload].stages[stage]
        // COMPUTED, never annotated. The path a consumer imports a stage by is
        // fully determined by the two ids naming it, so stating it again by hand
        // is a copy that can only ever be right by agreement — and one that
        // disagreed would send a consumer to a different stage's file while every
        // fact published beside it came from this one.
        + { importPath: 'github.com/metio/kurly/workloads/%s/%s.libsonnet' % [workload, stage] }
        + { storage: { pvcs: pvcCount(stageImports[workload + '/' + stage]) } }
        + (
          // One render per stage: `runs` is what everything below is derived
          // from, and rendering it twice to ask two questions about the same
          // image would let the answers disagree.
          local ran = runs(stageImports[workload + '/' + stage]);
          local pinned = std.get(ran, 'digest', null);
          { runs: ran }
          + { signature: signatureOf(workload, stage, pinned) }
          // The linux CPU architectures the stage's pinned image publishes, from
          // architectures.gen.libsonnet (generated by gen-architectures). null
          // when the image has no entry yet (a new workload before a regen) or
          // the stage pins no image of its own (an operator picks it).
          //
          // Anchored to the digest that was measured, like the signature beside
          // it. Which CPUs an image publishes is a fact about specific bits, and
          // Renovate moves the pin between sweeps — an entry carried forward
          // onto an image nobody inspected would place a workload on an arm node
          // on the strength of the version before it. A bump retracts the claim
          // and the next sweep earns it back.
          + (
            local resolved = std.get(architectures, workload + '/' + stage, null);
            local measured = if resolved == null then null else std.get(resolved, 'digest', null);
            {
              architectures:
                if resolved == null || measured == null || measured != pinned
                then null
                else resolved.architectures,
            }
          )
        )
        + { posture: posture(stageImports[workload + '/' + stage]) }
        + { scaling: scaling(stageImports[workload + '/' + stage]) }
        + { pss: pssLib.of(main.list(stageImports[workload + '/' + stage]()).items) }
        // What the pods an OPERATOR ran actually clear, for the stages whose own
        // manifest has no pod template to read. A SEPARATE field, never merged
        // into `pss`: one is derived from what kurly wrote and the other is
        // measured from what ran, and a consumer must be able to tell which it
        // is holding. ABSENT means not measured, never clean.
        + (
          local m = std.get(pssOperatorPods, workload + '/' + stage, null);
          if m == null then {} else { pssOperator: m }
        )
        + { profile: profile(stageImports[workload + '/' + stage]) }
        + { secrets: secretsOf(stageImports[workload + '/' + stage]) }
        + { declaredRequests: declaredRequests(stageImports[workload + '/' + stage]) }
        + clusterScoped(stageImports[workload + '/' + stage])
        // Which bollwerk policies the stage breaks, from bsi.gen.libsonnet.
        + { bsi: bsiOf(workload + '/' + stage, stageImports[workload + '/' + stage]) }
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
  assert reconcile('mesh', std.objectFields(ann.mesh), std.objectFieldsAll(mesh)),
  assert reconcile('backup', std.objectFields(ann.backup), std.objectFieldsAll(backup)),
  // A stage that declares secretKeys but whose default render reads no Secret at
  // all is stating a contract nothing consumes. That is legal — many stages wire
  // the Secret only when a parameter names one — but a stage that reads a Secret
  // BY DEFAULT and declares no keys leaves a consumer no way to know what to put
  // in it, so those are enumerated here rather than left to be rediscovered.
  //
  // The nine below are deliberate: each mounts a CONFIGURATION DOCUMENT that no
  // generator can mint — a Thanos objstore.yml naming a bucket and its
  // credentials, a Dex config with its connectors, an application signing key
  // whose format the application defines. Inventing a `generate: document` for
  // them would hand a portal a job it cannot do while telling it the job was
  // done. The derived `secrets` field is what says a Secret is needed at all.
  //
  // The list is exact rather than a count, so adding a stage that reads a Secret
  // without declaring its keys fails here and has to be justified.
  assert (
    local undeclared = std.set([
      workload + '/' + stage
      for workload in std.objectFields(ann.workloads)
      for stage in std.objectFields(ann.workloads[workload].stages)
      // A custom-resource stage renders no pod template, so secretsOf reports
      // null — not measured rather than none — and cannot be judged here.
      if !std.objectHas(ann.workloads[workload].stages[stage], 'secretKeys')
         && (
           local sec = secretsOf(stageImports[workload + '/' + stage]);
           sec != null && std.length(sec) > 0
         )
    ]);
    undeclared == std.set([
      'dex/server',
      'ente/server',
      'forgejo/server',
      'lemmy/backend',
      'misskey/server',
      'thanos/compact',
      'thanos/receive',
      'thanos/store',
      'tik/backend',
    ])
  ) : 'catalog: the set of stages reading a Secret without declaring its keys has changed — a new one needs secretKeys, or a documented reason why its contents cannot be generated',
  // `scaling` and `profile` are derived independently — one reads the storage
  // topology, the other asks production() what it did — so they can disagree,
  // and a disagreement means one of them is lying. A stage that cannot scale
  // horizontally must come back from production() with a single replica, or
  // with none at all where the controller has no such field.
  assert std.all([
    local p = stage.profile;
    p == null || stage.scaling == null || stage.scaling.horizontal
    || p.got.replicas == null || p.got.replicas == 1
    for w in workloadEntries
    for stage in w.stages
  ]) : 'catalog: a stage that cannot scale horizontally came back from production() with more than one replica — scaling and profile disagree, and one of them is wrong',
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
  // Every image is pinned by DIGEST. renovate.json has said so since the pins were
  // introduced — a tag says which version, only a digest says which bits, so a
  // rebuilt base image carrying a patched library is otherwise indistinguishable
  // from no change at all — and nothing checked it, so three stages were not.
  //
  // It also catches an image that is GONE: Renovate cannot resolve a digest for
  // something the registry does not have, so the pin quietly stays a bare tag.
  // bigcapital's gateway sat that way, naming an image that has never existed.
  assert std.all([
    std.length(std.findSubstr('@sha256:', std.get(std.get(st, 'runs', {}), 'image', '@sha256:'))) > 0
    for w in workloadEntries
    for st in w.stages
  ]) :
         'catalog: a stage image is not pinned by digest — %s. A tag alone cannot say which bits, and an image that cannot be pinned is often one that is gone' % [
    std.join(', ', [
      st.importPath
      for w in workloadEntries
      for st in w.stages
      if std.length(std.findSubstr('@sha256:', std.get(std.get(st, 'runs', {}), 'image', '@sha256:'))) == 0
    ]),
  ],
  // An upstream the forge reports as ARCHIVED is a project that has stopped, and
  // this catalogue does not carry those: every future vulnerability in it stays
  // open, and an operator who deployed it from here has nowhere to take it. The
  // fact was already asked for and published — what was missing is anything acting
  // on it, which is how minio stayed in the catalogue for months after its
  // repository went read-only.
  //
  // It fails the build rather than warning, because the weekly refresh re-asks each
  // forge and opens a pull request when an answer changes: an archival now arrives
  // as a red pull request naming the workload, which is the moment to decide about
  // it. Removing it means an entry in excluded.libsonnet; keeping it deliberately
  // means saying so there too.
  assert std.all([
    !std.get(std.get(w, 'upstream', {}), 'archived', false)
    for w in workloadEntries
  ]) :
         'catalog: a carried workload has an ARCHIVED upstream — %s. Remove it, and record why in catalog/excluded.libsonnet' % [
    std.join(', ', [
      w.id
      for w in workloadEntries
      if std.get(std.get(w, 'upstream', {}), 'archived', false)
    ]),
  ],
  // Software this catalogue has decided not to carry cannot come back by someone
  // adding an annotation for it. The reason is in excluded.libsonnet beside the id;
  // deleting a directory would have left nothing to read and nothing to stop it.
  // A consent record is a claim about somebody else's wishes, published to every
  // consumer of this catalogue. It carries the evidence or it does not exist.
  assert std.all([
    std.objectHas(consent[id], 'verifiedBy') && std.objectHas(consent[id], 'evidence')
    for id in std.objectFields(consent)
  ]) : 'catalog: a consent record without verifiedBy and evidence — a claim about a maintainer needs the thing a reader can check',
  assert std.all([
    std.member(['no-new-orders', 'winding-down'], consent[id].status)
    for id in std.objectFields(consent)
  ]) : 'catalog: a consent record with an unknown status (no-new-orders, winding-down)',
  assert std.all([
    std.member(['repository-commit', 'signed-email', 'dns-txt'], consent[id].verifiedBy)
    for id in std.objectFields(consent)
  ]) : 'catalog: a consent record verified by an unrecognised method',
  // A trademark posture with nothing behind it is an assertion about somebody
  // else's rights that a reader cannot check.
  assert std.all([
    std.objectHas(trademark[id], 'policy') && std.objectHas(trademark[id], 'posture')
    for id in std.objectFields(trademark)
  ]) : 'catalog: a trademark record without a posture and the policy it was read from',
  assert std.all([
    std.member(['restricted', 'permitted-with-attribution', 'unrestricted', 'unaddressed'], trademark[id].posture)
    for id in std.objectFields(trademark)
  ]) : 'catalog: a trademark record with an unknown posture (restricted, permitted-with-attribution, unrestricted, unaddressed)',
  assert std.all([std.objectHas(ann.workloads, id) for id in std.objectFields(trademark)]) :
         'catalog: trademark.libsonnet names a workload that does not exist',
  // Every exclusion states a reason from the closed vocabulary, so a consumer
  // switches on it rather than parsing the sentence beside it.
  assert std.all([
    std.member(excludedReasons, excluded[id].reason)
    for id in std.objectFields(excluded)
  ]) : 'catalog: an exclusion with a reason outside the published vocabulary',
  assert std.all([!std.objectHas(ann.workloads, name) for name in std.objectFields(excluded)]) :
         'catalog: an excluded workload is annotated again — see catalog/excluded.libsonnet for why it was removed',
  assert std.all([std.objectHas(ann.workloads, name) for name in maturity.productionNames]) :
         'maturity: production.libsonnet names a workload that does not exist',
  // Same for the delivery ledger: a walk that recorded a workload since renamed
  // would otherwise publish a claim about nothing.
  assert std.all([std.objectHas(ann.workloads, name) for name in maturity.deliveredNames]) :
         'maturity: delivered-verified.libsonnet names a workload that does not exist',
  // And for the schema readings. These attach to a delivery, so a count for a
  // workload that has none is silently dropped rather than published — catch that
  // here instead, where it reads as the bug it is.
  assert std.all([std.objectHas(ann.workloads, name) for name in maturity.databaseUseNames]) :
         'maturity: database-use.libsonnet names a workload that does not exist',
  assert std.all([std.member(maturity.deliveredNames, name) for name in maturity.databaseUseNames]) :
         'maturity: database-use.libsonnet names a workload with no delivery to attach the reading to',
  assert std.all([std.objectHasAll(main, helper) for helper in std.objectFields(ann.helpers)]) :
         'helpers: main.libsonnet must expose every annotated helper',

  // 2: `requires` became a list of { kind, required, engine?, extensions? }. A
  // workload can need two dependencies of the same kind, which the v1 object keyed
  // by kind could not express — and a consumer priced the difference.
  schemaVersion: 2,
  // The closed set of dependency kinds `requires[].kind` may take. Published so a
  // consumer validates against it and fails loudly on a term it does not know,
  // rather than carrying an unpriced dependency it silently ignored.
  requiresKinds: requiresKinds,
  // Workloads this catalogue does not carry, and WHY — OUR decision, not a
  // maintainer's wish. A consumer switches on `reason` (one of
  // `excludedReasons`) and shows `note`, which carries the specific project and
  // the URL it was read from.
  excluded: excluded,
  excludedReasons: excludedReasons,
  // What MAINTAINERS have asked of anyone hosting their software. Empty: nobody
  // has asked. An absent entry means nobody asked, NEVER that they consent —
  // there is no `offered` status for the same reason. Kept apart from `excluded`
  // because that is our decision and this is theirs, and publishing one as the
  // other misrepresents somebody else's position.
  consent: consent,
  // The policy set every stage's `bsi` field refers to, with the BSI requirement
  // each one implements.
  bsiPolicies: bsiPolicies,
  workloads: workloadEntries,
  kinds: entries(ann.kinds),
  features: entries(ann.features),
  expose: entries(ann.expose),
  network: entries(ann.network),
  mesh: entries(ann.mesh),
  backup: entries(ann.backup),
  security: entries(ann.security),
  helpers: entries(ann.helpers),
  migrations: entries(ann.migrations),
}
