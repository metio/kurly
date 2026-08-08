// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// harbor/core — the Harbor API server and token service: projects, users, robot
// accounts, replication, retention, and the bearer tokens a Docker client trades
// its credentials for. Harbor is FOUR processes, one stage each — core, portal,
// registry, jobservice — all pointed at the same PostgreSQL, the same Redis, and
// the same Secret. Import them, place them together, and render with kurly.list:
//
//   local core = import 'github.com/metio/kurly/workloads/harbor/core.libsonnet';
//   kurly.list([core(externalUrl='https://harbor.example.com'), …])
//
// Serves on :8080 and is the ONLY stage that faces outside: it answers the API,
// the token service and every registry path a client uses, and forwards the UI
// requests it does not answer itself to the portal Service named by portalName.
// Compose the exposure here.
//
// DATABASE & CACHE: Harbor needs PostgreSQL (a `registry` database) and Redis.
// The defaults point at a CNPG cluster named `harbor-db` (its `-rw` Service) and
// a Valkey named `harbor-cache`, with core on Redis DB 0, jobservice on 1 and the
// registry on 2.
//
// SECRETS: one consumer-provided Secret carries everything the components share —
// CORE_SECRET and JOBSERVICE_SECRET (how they authenticate to each other),
// HARBOR_ADMIN_PASSWORD, POSTGRESQL_PASSWORD, the registry basic-auth credential,
// CSRF_KEY, `secretKey` (EXACTLY 16 characters — it encrypts the registry
// passwords stored in the database, so changing it makes every stored credential
// unreadable), and the token service's `tls.key`/`tls.crt`. That last pair is a
// CA keypair somebody has to mint (`openssl req -x509 -newkey rsa:4096 -nodes`);
// no generator produces it. kurly authors no Secret.
//
// externalUrl is the address clients reach Harbor at. `docker login` follows the
// token realm the registry hands back, which core builds from this value, so a
// wrong one logs in against an unreachable host.
//
// Stateless: everything core knows lives in PostgreSQL and Redis, so this is a
// plain rolling Deployment that scales horizontally.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './core.image', '\n');

function(
  name='harbor-core',
  image=defaultImage,
  replicas=1,
  // The address clients reach Harbor at — the token realm and every generated
  // pull command are built from it.
  externalUrl='https://harbor.example.com',
  // The other three stages, by Service name. Everything core talks to in-cluster.
  portalName='harbor-portal',
  registryName='harbor-registry',
  jobserviceName='harbor-jobservice',
  dbHost='harbor-db-rw',
  dbPort='5432',
  dbName='registry',
  dbUser='harbor',
  dbSslMode='disable',
  redisHost='harbor-cache',
  redisPort='6379',
  // The basic-auth user core presents to the registry; its password is
  // REGISTRY_CREDENTIAL_PASSWORD in the Secret, and the registry's htpasswd file
  // must hold the same pair.
  registryUser='harbor_registry_user',
  // The Secret every Harbor stage reads. The consumer provides it; kurly mints
  // none.
  secretName='harbor',
  logLevel='info',
  // Extra environment, merged over the below. Anything sensitive belongs in the
  // Secret, not a literal here.
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
  podLabels={},
  podAnnotations={},
)
  local coreUrl = 'http://%s:8080' % name;
  // The beego configuration the binary reads from CONFIG_PATH; the port here and
  // the container port are the same number for the same reason.
  local appConf = |||
    appname = Harbor
    runmode = prod
    enablegzip = true

    [prod]
    httpport = 8080
  |||;
  local baseEnv = {
    PORT: '8080',
    CONFIG_PATH: '/etc/core/app.conf',
    LOG_LEVEL: logLevel,
    DATABASE_TYPE: 'postgresql',
    POSTGRESQL_HOST: dbHost,
    POSTGRESQL_PORT: dbPort,
    POSTGRESQL_USERNAME: dbUser,
    POSTGRESQL_DATABASE: dbName,
    POSTGRESQL_SSLMODE: dbSslMode,
    POSTGRESQL_MAX_IDLE_CONNS: '50',
    POSTGRESQL_MAX_OPEN_CONNS: '100',
    EXT_ENDPOINT: externalUrl,
    CORE_URL: coreUrl,
    // The loopback address core uses to reach itself, which must not go back out
    // through the Service.
    CORE_LOCAL_URL: 'http://127.0.0.1:8080',
    PORTAL_URL: 'http://%s:8080' % portalName,
    JOBSERVICE_URL: 'http://%s:8080' % jobserviceName,
    REGISTRY_URL: 'http://%s:5000' % registryName,
    REGISTRY_CONTROLLER_URL: 'http://%s:8080' % registryName,
    TOKEN_SERVICE_URL: coreUrl + '/service/token',
    REGISTRY_CREDENTIAL_USERNAME: registryUser,
    REGISTRY_STORAGE_PROVIDER_NAME: 'filesystem',
    CHART_CACHE_DRIVER: 'redis',
    _REDIS_URL_CORE: 'redis://%s:%s/0' % [redisHost, redisPort],
    _REDIS_URL_REG: 'redis://%s:%s/2' % [redisHost, redisPort],
    // Trivy is a separate deployment Harbor can scan with; this stage set does
    // not carry one, so scanning stays off until one is registered by hand.
    WITH_TRIVY: 'false',
    PERMITTED_REGISTRY_TYPES_FOR_PROXY_CACHE: 'docker-hub,harbor,azure-acr,ali-acr,aws-ecr,google-gcr,docker-registry,github-ghcr,jfrog-artifactory',
    REPLICATION_ADAPTER_WHITELIST: 'ali-acr,aws-ecr,azure-acr,docker-hub,docker-registry,github-ghcr,google-gcr,harbor,huawei-SWR,jfrog-artifactory,tencent-tcr,volcengine-cr',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // The Harbor images run as uid 10000.
  + kurly.runAs(10000, gid=10000, fsGroup=10000)
  + kurly.config({ 'app.conf': appConf }, mountPath='/etc/core', subPath=true)
  // Two single-key mounts rather than the whole Secret as a directory: both
  // files sit inside /etc/core beside the app.conf the ConfigMap already puts
  // there, and mounting the Secret over that directory would shadow it.
  + kurly.secretMount(secretName, '/etc/core/key', subPath='secretKey')
  + kurly.secretMount(secretName, '/etc/core/private_key.pem', subPath='tls.key')
  // Core caches the tokens it issues under /etc/core/token; an emptyDir keeps
  // them out of the container's writable layer and bounded.
  + kurly.scratch('/etc/core/token', '64Mi')
  + kurly.scratch('/tmp', '128Mi')
  // Every Harbor image starts by copying a CA bundle into /home/harbor, beside
  // its own binaries and entrypoint scripts, so the root filesystem has to be
  // writable: an emptyDir over that one path would shadow the install tree and
  // leave the container nothing to run.
  + kurly.writableRootFilesystem()
  // The first start creates the whole Harbor schema before anything answers.
  + kurly.startupProbe({ httpGet: { path: '/api/v2.0/ping', port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/api/v2.0/ping', port: 'http' }, periodSeconds: 10 })
  + kurly.livenessProbe({ httpGet: { path: '/api/v2.0/ping', port: 'http' }, initialDelaySeconds: 30, periodSeconds: 20 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + kurly.podLabels(podLabels)
  + kurly.podAnnotations(podAnnotations)
