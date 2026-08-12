// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// vector — a pipeline for logs, metrics and traces: it collects them, reshapes
// them with a transform language, and sends them wherever they are meant to go. A
// composable kurly.daemon workload, because collecting a node's container logs
// means reading them off that node. Import it and render with kurly.list:
//
//   local vector = import 'github.com/metio/kurly/workloads/vector/agent.libsonnet';
//   kurly.list(vector(namespace='vector', sinks={
//     loki: { type: 'loki', inputs: ['kubernetes_logs'], endpoint: 'http://loki:3100', encoding: { codec: 'json' } },
//   }))
//
// THE DEFAULT SINK PRINTS TO STDOUT, WHICH IS NOT A PIPELINE. The kubernetes_logs
// source is configured for you; where the data goes is the decision only the
// deployment can make, and there is no honest default for it. So the default sink
// is a console one — the agent starts, and what it collects is visibly going
// nowhere useful, which is a better failure than buffering into a void. Passing an
// empty `sinks` is refused outright, because that one is not a mistake anybody
// makes on purpose.
//
// IT READS EVERY CONTAINER'S LOGS ON THE NODE, and asks the apiserver for the pod
// metadata to label them with — that is the cluster-wide grant, and it is
// read-only on pods and namespaces. The logs themselves come from the node's log
// directory, which is why /var/log is mounted.
//
// STATE IS THE CHECKPOINT FILE. Vector remembers how far it read in each log file
// under its data directory; on an emptyDir that survives a container restart but
// not a pod one, so a rescheduled agent re-reads what the node still has. A
// hostPath data directory is what makes the checkpoint survive the pod, at the
// cost of writing to the node — `dataDir` chooses.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './agent.image', '\n');

function(
  name='vector',
  image=defaultImage,
  // The namespace this is deployed into; the ClusterRoleBinding's subject needs
  // it, and one without a namespace grants nothing.
  namespace='vector',
  // Where the collected data goes. The default prints to stdout — replace it.
  sinks={ console: { type: 'console', inputs: ['kubernetes_logs'], encoding: { codec: 'json' } } },
  // Extra sources beside the kubernetes_logs one this configures.
  sources={},
  // Vector Remap Language transforms, between the sources and the sinks.
  transforms={},
  // A node path for the read checkpoints. Null keeps them in the pod, where a
  // reschedule loses them and the agent re-reads what is still on disk.
  dataDir=null,
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  env={},
  labels={},
  annotations={},
)
  assert std.length(std.objectFields(sinks)) > 0 :
         'vector: at least one sink is needed — an agent with nowhere to send what it collects reads every log on the node and drops it';

  kurly.daemon(name, image)
  + kurly.version(version)
  + kurly.env({ VECTOR_SELF_NODE_NAME: '', VECTOR_LOG: 'info' } + env)
  + kurly.args(['--config=/etc/vector/vector.yaml'])
  + kurly.config({
    'vector.yaml': std.manifestYamlDoc({
      data_dir: if dataDir != null then '/vector-data' else '/tmp/vector',
      sources: { kubernetes_logs: { type: 'kubernetes_logs' } } + sources,
      [if std.length(std.objectFields(transforms)) > 0 then 'transforms']: transforms,
      sinks: sinks,
    }, quote_keys=false),
  }, mountPath='/etc/vector')
  // Pod and namespace metadata, to label the lines it reads. Read-only, and
  // cluster-wide because the pods it reads logs for are in every namespace.
  + kurly.clusterRbac(
    [{ apiGroups: [''], resources: ['pods', 'namespaces', 'nodes'], verbs: ['get', 'list', 'watch'] }],
    namespace=namespace
  )
  // The node's container logs. Read-only: an agent that could write them could
  // rewrite the record it exists to ship.
  + kurly.hostPath('/var/log', type='Directory')
  + kurly.scratch('/tmp', '1Gi')
  + (if dataDir != null then kurly.hostPath('/vector-data', path=dataDir, type='DirectoryOrCreate', readOnly=false) else {})
  // The image runs as root; reading /var/log needs a uid that may, so this is one
  // of the few agents where root is the working answer rather than a shortcut.
  + kurly.rootUser()
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
