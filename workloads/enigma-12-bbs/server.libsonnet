// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// enigma-12-bbs — an ENiGMA½ bulletin board system (a modern BBS engine speaking
// telnet, with message bases, file areas and legacy door games). A composable
// kurly.worker-shaped service on the official image, exposed as a plain TCP
// Service. Import it and render with kurly.list:
//
//   local enigma = import 'github.com/metio/kurly/workloads/enigma-12-bbs/server.libsonnet';
//   kurly.list(enigma())
//
// Listens for telnet callers on :8888. That is a raw TCP protocol, so an HTTP
// exposure recipe does nothing for it — reach it with a Service of type
// LoadBalancer/NodePort, or a Gateway TCPRoute.
//
// FIRST RUN: the image's own entrypoint creates its configuration by asking
// questions on a terminal, which no cluster provides — with nothing to answer
// them it exits and the pod never serves. The init container writes the same
// artefacts non-interactively instead: the menu set copied from the image's own
// templates, and a minimal config.hjson naming the board and its first message
// area. It only ever writes what is missing, so an operator's later edits on the
// volume survive every restart, and the container then runs main.js directly
// rather than the entrypoint whose only other job was that setup.
//
// Single writer: the configuration, the SQLite databases and the file base sit on
// ReadWriteOnce volumes, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// Seeds /enigma-bbs/config on an empty volume: the menu files the engine reads
// (copied from the image's templates, with the include list spliced in the way
// the project's own generator does it) and a config.hjson holding the board name
// and one message conference. Everything else stays at the engine's defaults.
local setupScript = |||
  set -eu
  cd /enigma-bbs
  if [ -z "$(ls -A /enigma-bbs/config 2>/dev/null || true)" ]; then
    cp -rp /enigma-bbs-pre/config/. /enigma-bbs/config/
  fi
  if [ ! -f /enigma-bbs/config/config.hjson ]; then
    mkdir -p /enigma-bbs/config/menus
    includes=""
    for f in message_base private_mail login new_user doors file_base activitypub; do
      cp "misc/menu_templates/$f.in.hjson" "/enigma-bbs/config/menus/enigma-$f.hjson"
      includes="$includes\n\t\tenigma-$f.hjson"
    done
    sed "s|%INCLUDE_FILES%|${includes#\\n\\t\\t}|" misc/menu_templates/main.in.hjson \
      > /enigma-bbs/config/menus/enigma-main.hjson
    cat > /enigma-bbs/config/config.hjson <<EOF
  {
    general: {
      boardName: "$BOARD_NAME"
      menuFile: /enigma-bbs/config/menus/enigma-main.hjson
    }
    messageConferences: {
      local: {
        name: Local
        desc: Local Areas
        sort: 1
        default: true
        areas: {
          general: {
            name: General
            desc: General chit-chat
            sort: 1
            default: true
          }
        }
      }
    }
  }
  EOF
  fi
|||;

function(
  name='enigma-12-bbs',
  image=defaultImage,
  // Shown to callers, and the name the generated configuration carries. Change it
  // on the volume afterwards; this only decides what the first boot writes.
  boardName='ENiGMA BBS',
  // Configuration and generated menus.
  configSize='1Gi',
  // The SQLite databases: users, message bases, statistics.
  databaseSize='5Gi',
  // The file base — what callers upload and download.
  fileBaseSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // The telnet login server, the one listener enabled by default.
  + kurly.port(8888)
  + kurly.servicePort(8888)
  + kurly.env(env)
  // The image declares no user and the engine writes inside its own install tree
  // (it creates core/mailers/ before it listens), so it runs as root on a writable
  // root filesystem. No capability beyond the dropped-ALL default is needed: 8888
  // is unprivileged and nothing drops privileges.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // Skips the image entrypoint, whose only job besides this setup is an
  // interactive configuration wizard.
  + kurly.command(['node', 'main.js'])
  + kurly.store('/enigma-bbs/config', configSize, storageClass=storageClass)
  + kurly.store('/enigma-bbs/db', databaseSize, storageClass=storageClass)
  + kurly.store('/enigma-bbs/filebase', fileBaseSize, storageClass=storageClass)
  + kurly.initContainer({
    name: 'setup',
    image: image,
    command: ['bash', '-c', setupScript],
    env: [{ name: 'BOARD_NAME', value: boardName }],
    volumeMounts: [{ name: 'store', mountPath: '/enigma-bbs/config' }],
  })
  // Telnet is not HTTP: probe the listener by connection.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
