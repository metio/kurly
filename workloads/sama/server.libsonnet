// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// sama — a SAMA server (the backend of an end-to-end encrypted chat: WebSocket
// and HTTP APIs for conversations, messages, devices and attachments, with the
// SAMA client applications talking to it). A composable kurly.http workload backed
// by an EXTERNAL MongoDB — the mongodb-cluster workload provides one — and an
// EXTERNAL Redis, which every node uses to find the others. Import it and render
// with kurly.list:
//
//   local sama = import 'github.com/metio/kurly/workloads/sama/server.libsonnet';
//   kurly.list(sama())
//
// Serves the WebSocket and HTTP API on :9001 — compose an exposure onto it. The
// exposure has to allow WebSocket upgrades, which is what the clients connect on;
// plain HTTP alone gets an application that logs in and then goes silent.
//
// CLUSTERING: every replica opens a second socket (:9002 here) and registers its
// pod address in Redis, and a message for a user connected to another replica is
// forwarded over it. So the replicas talk to each other DIRECTLY, pod to pod, on
// a port no Service carries — a NetworkPolicy that allows only the API port
// delivers messages within a replica and drops them between replicas, which reads
// as messages arriving for some recipients and not others.
//
// SECRETS: kurly authors none. MONGODB_URL, REDIS_URL, the two JWT secrets, the
// cookie secret and the admin API key come from a provided Secret via envFrom.
// Rotating JWT_ACCESS_SECRET or JWT_REFRESH_SECRET signs everyone out.
//
// ATTACHMENTS live in S3-compatible object storage rather than on a volume, and
// are uploaded by the client against a presigned URL the server mints — so the
// bucket endpoint must be reachable from the BROWSER, not only from the cluster.
// Left unset the server starts and everything but file transfer works. The S3
// client addresses buckets virtual-host style and that is not configurable, so a
// self-hosted gateway serving only path-style addresses will not do.
//
// Stateless: conversations and messages are in MongoDB, sessions in Redis, files
// in the bucket. A plain rolling Deployment.
//
// The built-in REPL (APP_REPL_HTTP_ACCESS_KEY, APP_REPL_SOCKET_HANDLER,
// APP_REPL_FILE_IN/OUT) evaluates JavaScript inside the server process and stays
// unset here. Switching it on gives whoever reaches that port the process.
//
// Schema migrations are the image's own `npm run migrate-mongo-up`, run as a job
// against the same database — the server does not run them at startup.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='sama',
  image=defaultImage,
  replicas=2,
  // The API port (WebSocket and HTTP share it) and the port replicas use to reach
  // each other. The cluster port stays off the Service: it is pod-to-pod traffic
  // and nothing outside the workload has any business on it.
  port=9001,
  clusterPort=9002,
  // How long a node's registration in Redis lives, and therefore how often the
  // cluster is re-synced. Milliseconds, and REQUIRED: unset it becomes NaN and the
  // sync interval fires continuously.
  clusterSyncInterval=60000,
  // How often an idle client socket is pinged, in milliseconds. Same NaN trap.
  socketPingInterval=60000,
  // The origin the browser-based client is served from, allowed for cross-origin
  // API calls. Left null the server echoes the request's own origin back, which is
  // no restriction at all.
  corsOrigin=null,
  // The S3-compatible bucket attachments go to. Absolute URL including the scheme,
  // because the AWS client is given it verbatim. Left null there is no attachment
  // storage and the rest of the server runs.
  s3Endpoint=null,
  s3Bucket='sama',
  s3Region='us-east-1',
  // The Secret holding MONGODB_URL, REDIS_URL, JWT_ACCESS_SECRET,
  // JWT_REFRESH_SECRET, COOKIE_SECRET and HTTP_ADMIN_API_KEY — and S3_ACCESS_KEY
  // and S3_SECRET_KEY where attachments are configured. Read via envFrom.
  secretName='sama',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
                    NODE_ENV: 'production',
                    APP_NAME: name,
                    APP_PORT: std.toString(port),
                    APP_CLUSTER_PORT: std.toString(clusterPort),
                    NODE_CLUSTER_DATA_EXPIRES_IN: std.toString(clusterSyncInterval),
                    WATCHDOG_PING_SOCKET_INTERVAL: std.toString(socketPingInterval),
                    STANDALONE_NODE: 'false',
                    LOG_LEVEL: 'info',
                    LOG_SINGLE_LINE: 'true',
                    // npm resolves its cache and its log directory from HOME, which is root's
                    // home in the image and is not writable here.
                    HOME: '/tmp',
                    STORAGE_DRIVER: 's3',
                    S3_BUCKET_NAME: s3Bucket,
                    S3_REGION: s3Region,
                    FILE_UPLOAD_URL_EXPIRES_IN: '3600',
                    FILE_DOWNLOAD_URL_EXPIRES_IN: '604800',
                    JWT_ACCESS_TOKEN_EXPIRES_IN: '10800',
                    JWT_REFRESH_TOKEN_EXPIRES_IN: '1209600',
                    CONVERSATION_NOTIFICATIONS_ENABLED: 'true',
                    // The name of the Bull queue push notifications are handed to. The queue is
                    // constructed at startup and a nameless queue is not a queue.
                    SAMA_NATIVE_PUSH_QUEUE_NAME: 'push_notifications',
                  }
                  + (if corsOrigin == null then {} else { CORS_ORIGIN: corsOrigin })
                  + (if s3Endpoint == null then {} else { S3_ENDPOINT: s3Endpoint });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.extraPort('cluster', clusterPort, expose=false)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // The image selects no account and the application needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // npm's cache and logs, and node's own scratch use. The application writes
  // nothing else outside the database and the bucket.
  + kurly.scratch('/tmp', '128Mi')
  // A Service named sama injects SAMA_PORT=tcp://…, and APP_PORT is read from the
  // environment — the server would take that URL for its listen port.
  + kurly.disableServiceLinks()
  // /health answers 200 once MongoDB and Redis are connected; the process exits
  // rather than serving when either is unreachable.
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
