// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// features: the composable capabilities of a workload, each a function
// returning a `{ config+:: … }` mixin you add with `+`. A feature only ever
// contributes to config — never to a manifest directly — so the kind's
// computed manifests late-bind against the merged config regardless of the
// order features are composed:
//
//   kurly.http('tik', image)
//   + kurly.args(['backend', '--config=/etc/tik/pipelines.edn'])
//   + kurly.store('/var/lib/tik', '1Gi')
//   + kurly.config({ 'pipelines.edn': edn })
//   + kurly.runAs(12345)
//   + kurly.recreate()
{
  // Container basics.
  image(image):: { config+:: { image: image } },
  port(port):: { config+:: { port: port } },
  replicas(replicas):: { config+:: { replicas: replicas } },
  // args appends arguments to the image's own entrypoint (a subcommand
  // selecting the workload); command overrides the entrypoint itself.
  args(args):: { config+:: { args: args } },
  command(command):: { config+:: { command: command } },
  env(env):: { config+:: { env+: env } },
  // The workload version, stamped as app.kubernetes.io/version on every object.
  version(version):: { config+:: { version: version } },
  labels(labels):: { config+:: { labels+: labels } },
  annotations(annotations):: { config+:: { annotations+: annotations } },
  resources(requests=null, limits=null):: {
    config+:: {
      resources+:
        (if requests == null then {} else { requests: requests })
        + (if limits == null then {} else { limits: limits }),
    },
  },
  serviceAccount(serviceAccountName):: { config+:: { serviceAccountName: serviceAccountName } },
  // HTTP readiness+liveness probes on the named `http` port.
  probes(path='/healthz'):: { config+:: { probePath: path } },

  // CronJob tuning (only kurly.cron reads these).
  schedule(schedule):: { config+:: { schedule: schedule } },
  concurrencyPolicy(concurrencyPolicy):: { config+:: { concurrencyPolicy: concurrencyPolicy } },

  // Storage and mounts. store adds the workload's own PVC and mounts it; config
  // renders a ConfigMap from a filename->content map and mounts it read-only;
  // secretMount mounts an EXISTING Secret (kurly never mints key material);
  // scratch adds a writable emptyDir — the escape valve a read-only root
  // filesystem needs for /tmp and the like.
  store(mountPath, size, accessModes=['ReadWriteOnce'], storageClass=null, selector={}, annotations={}):: {
    config+:: {
      store: {
        mountPath: mountPath,
        size: size,
        accessModes: accessModes,
        storageClass: storageClass,
        selector: selector,
        annotations: annotations,
      },
    },
  },
  config(files, mountPath='/etc/config'):: {
    config+:: { configFiles: { mountPath: mountPath, files: files } },
  },
  secretMount(secretName, mountPath, readOnly=true, optional=false, defaultMode=null):: {
    config+:: {
      secretMounts+: [{
        secretName: secretName,
        mountPath: mountPath,
        readOnly: readOnly,
        optional: optional,
        defaultMode: defaultMode,
      }],
    },
  },
  scratch(mountPath, sizeLimit=null):: {
    config+:: { scratch+: [{ mountPath: mountPath, sizeLimit: sizeLimit }] },
  },

  // A pinned run-as user/group (and matching fsGroup) for images that do not
  // declare a non-root USER themselves, or that must own a mounted volume's
  // files. gid defaults to uid; fsGroup defaults to gid.
  runAs(uid, gid=null, fsGroup=null):: {
    config+:: {
      runAsUser: uid,
      runAsGroup: if gid == null then uid else gid,
      fsGroup: if fsGroup == null then (if gid == null then uid else gid) else fsGroup,
    },
  },

  // Deployment update strategy. recreate is the single-writer case: a
  // ReadWriteOnce store cannot be mounted by a second pod while the old one
  // holds it, so a rolling update would deadlock.
  strategy(strategy):: { config+:: { strategy: strategy } },
  recreate():: { config+:: { strategy: 'Recreate' } },

  // Security escape hatches — each downgrades one default for a workload that
  // genuinely needs it. The kurly.security.* mixins relax whole PSS profiles.
  rootUser():: { config+:: { runAsNonRoot: false } },
  writableRootFilesystem():: { config+:: { readOnlyRootFilesystem: false } },
  hostUsers():: { config+:: { hostUsers: true } },
}
