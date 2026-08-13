// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// falco — runtime security: it watches the system calls every container on a node
// makes and raises an alert when one matches a rule (a shell in a container, a
// write to /etc, an unexpected outbound connection). A composable kurly.daemon
// workload, because the thing it watches is the node. Import it and render with
// kurly.list:
//
//   local falco = import 'github.com/metio/kurly/workloads/falco/agent.libsonnet';
//   kurly.list(falco(namespace='falco'))
//
// LEAST PRIVILEGE, NOT PRIVILEGED. Falco is usually deployed with a fully
// privileged container. It does not need one with the modern eBPF driver, which
// this stage uses: four capabilities cover it — BPF to load the programs,
// PERFMON to read the perf buffers, SYS_RESOURCE to raise the locked-memory
// limit, and SYS_PTRACE to read /proc for process lineage — and the rest of the
// hardened posture stands, including the read-only root filesystem. That is the
// set Falco's own chart documents for its least-privileged mode. Compose
// kurly.privileged() if a node's kernel is too old for the modern driver and the
// kernel module is the only option.
//
// WHAT IT SEES. Every syscall from every container on the node, which is the
// whole job and is also why this is not a tenant workload: the alerts it produces
// describe other people's software. `/sys/kernel` covers the tracefs and debugfs
// the driver reads.
//
// RULES ARE THE PRODUCT. The image ships the default ruleset, which is a starting
// point rather than a policy; `rules` adds files to it, and tuning them down is
// how a deployment stops paging on its own normal behaviour.
//
// OUTPUT GOES TO STDOUT by default, where a log pipeline can pick it up. Falco's
// gRPC and HTTP outputs are configured through `config`.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './agent.image', '\n');

function(
  name='falco',
  image=defaultImage,
  // The namespace this is deployed into; the ClusterRoleBinding's subject needs
  // it. Falco reads pod and namespace metadata to name the container an alert
  // came from.
  namespace='falco',
  // Merged over the rendered falco.yaml — outputs, rule files, driver settings.
  config={},
  // Extra rule files, keyed by file name, mounted beside the shipped ruleset.
  rules={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  env={},
  labels={},
  annotations={},
)
  kurly.daemon(name, image)
  + kurly.version(version)
  + kurly.env(env)
  + kurly.command(['/usr/bin/falco'])
  + kurly.args(['-c', '/etc/falco/falco.yaml'])
  // The eBPF driver is loaded by the process itself, so it needs the privileges
  // that go with that and nothing more. See the header.
  + kurly.rootUser()
  + kurly.addCapabilities(['BPF', 'PERFMON', 'SYS_RESOURCE', 'SYS_PTRACE'])
  // tracefs and debugfs, which the driver attaches its programs through.
  + kurly.hostPath('/sys/kernel', type='Directory', readOnly=false)
  + kurly.scratch('/tmp', '128Mi')
  + kurly.config(
    { 'falco.yaml': std.manifestYamlDoc({
      engine: { kind: 'modern_ebpf' },
      // Falco REFUSES TO START unless a container plugin is loaded — its own
      // rules reference container fields, and it checks that requirement before
      // it reads a single event. The plugin ships in the image; naming it here is
      // what loads it.
      load_plugins: ['container'],
      plugins: [{ name: 'container', library_path: 'libcontainer.so' }],
      stdout_output: { enabled: true },
      json_output: true,
      rules_files: ['/etc/falco/falco_rules.yaml', '/etc/falco/rules.d'],
    } + config, quote_keys=false) } + rules,
    mountPath='/etc/falco',
    subPath=true
  )
  // Pod and namespace metadata, so an alert names the container it came from
  // rather than a container id.
  + kurly.clusterApiServerClient(
    [{ apiGroups: [''], resources: ['pods', 'namespaces', 'nodes', 'replicationcontrollers', 'services'], verbs: ['get', 'list', 'watch'] }],
    namespace=namespace
  )
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
