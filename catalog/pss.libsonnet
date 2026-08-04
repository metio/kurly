// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Which bar of the Kubernetes Pod Security Standards a stage clears, evaluated
// against what it RENDERS rather than against what its recipes intended.
//
// This is a different claim from `posture` and a much more portable one. `posture`
// reports four knobs kurly happens to set; PSS is a published, versioned
// definition that every Kubernetes operator already knows, enforced by an
// admission controller shipped with the cluster. "Clears restricted" means
// something to somebody who has never heard of this catalogue.
//
// The controls below are the ones the standard names, in its own vocabulary, so
// a failure can be looked up rather than interpreted. Each is checked over every
// pod template the stage renders and over every container in it — regular, init
// and ephemeral alike, because the admission controller checks all three and a
// privileged init container makes the whole pod privileged.
//
// A stage that renders no pod template reports null. Its pods belong to an
// operator, which decides their security context, and reading that silence as
// "privileged" would libel a workload nobody measured.
//
// Kept in its own file so the assertion suite can exercise the controls directly
// against synthetic workloads, rather than only through whatever the catalogue
// happens to contain. A rule this long that is only ever exercised by real data
// is one whose edge cases nobody has tried.
{
  // The pod templates a manifest set renders. Shared with the catalog's other
  // derived facts so there is ONE definition: a second copy would drift the day
  // a new controller kind appeared, and drift silently.
  podTemplates(items):: [
    if m.kind == 'CronJob' then m.spec.jobTemplate.spec.template else m.spec.template
    for m in items
    if std.member(['Deployment', 'StatefulSet', 'DaemonSet', 'Job', 'CronJob'], m.kind)
  ],

  of(items)::
    local tmpls = $.podTemplates(items);
    if tmpls == [] then null
    else
      // Every container the admission controller would look at.
      local allContainers(t) =
        std.get(t.spec, 'containers', [])
        + std.get(t.spec, 'initContainers', [])
        + std.get(t.spec, 'ephemeralContainers', []);
      local podSec(t) = std.get(t.spec, 'securityContext', {});
      local ctrSec(c) = std.get(c, 'securityContext', {});
      // A container's effective value: its own if set, otherwise the pod's.
      local effective(t, c, field) =
        if std.objectHas(ctrSec(c), field) then ctrSec(c)[field]
        else std.get(podSec(t), field, null);

      // ── baseline ──────────────────────────────────────────────────────────────
      local baselineCapabilities = std.set([
        'AUDIT_WRITE',
        'CHOWN',
        'DAC_OVERRIDE',
        'FOWNER',
        'FSETID',
        'KILL',
        'MKNOD',
        'NET_BIND_SERVICE',
        'SETFCAP',
        'SETGID',
        'SETPCAP',
        'SETUID',
        'SYS_CHROOT',
      ]);
      local anyTmpl(pred) = std.any([pred(t) for t in tmpls]);
      local anyCtr(pred) = std.any([pred(t, c) for t in tmpls for c in allContainers(t)]);

      local baselineFailures = std.prune([
        if anyTmpl(function(t) std.any([std.get(t.spec, f, false) == true for f in ['hostNetwork', 'hostPID', 'hostIPC']]))
        then 'hostNamespaces' else null,
        if anyCtr(function(t, c) std.get(ctrSec(c), 'privileged', false) == true)
        then 'privileged' else null,
        if anyCtr(function(t, c) std.length(std.setDiff(
          std.set(std.get(std.get(ctrSec(c), 'capabilities', {}), 'add', [])), baselineCapabilities
        )) > 0) then 'capabilities' else null,
        if anyTmpl(function(t) std.any([std.objectHas(v, 'hostPath') for v in std.get(t.spec, 'volumes', [])]))
        then 'hostPathVolumes' else null,
        if anyCtr(function(t, c) std.any([
          std.get(p, 'hostPort', 0) != 0
          for p in std.get(c, 'ports', [])
        ])) then 'hostPorts' else null,
        if anyCtr(function(t, c) std.get(ctrSec(c), 'procMount', 'Default') != 'Default')
        then 'procMount' else null,
        // Unconfined is the only seccomp value baseline rejects; unset is allowed.
        if anyTmpl(function(t) std.get(std.get(podSec(t), 'seccompProfile', {}), 'type', '') == 'Unconfined')
           || anyCtr(function(t, c) std.get(std.get(ctrSec(c), 'seccompProfile', {}), 'type', '') == 'Unconfined')
        then 'seccompProfile' else null,
        if anyTmpl(function(t) std.length(std.get(podSec(t), 'sysctls', [])) > 0)
        then 'sysctls' else null,
        if anyTmpl(function(t) std.get(std.get(podSec(t), 'seLinuxOptions', {}), 'user', '') != ''
                               || std.get(std.get(podSec(t), 'seLinuxOptions', {}), 'role', '') != '')
        then 'seLinuxOptions' else null,
      ]);

      // ── restricted, which is baseline plus these ──────────────────────────────
      local restrictedVolumeTypes = std.set([
        'configMap',
        'csi',
        'downwardAPI',
        'emptyDir',
        'ephemeral',
        'persistentVolumeClaim',
        'projected',
        'secret',
      ]);
      // A volume's type is whichever key it carries besides its name.
      local volumeTypeOf(v) = std.setDiff(std.set(std.objectFields(v)), std.set(['name']));

      local restrictedFailures = std.prune([
        if anyTmpl(function(t) std.any([
          std.length(std.setDiff(volumeTypeOf(v), restrictedVolumeTypes)) > 0
          for v in std.get(t.spec, 'volumes', [])
        ])) then 'volumeTypes' else null,
        if anyCtr(function(t, c) std.get(ctrSec(c), 'allowPrivilegeEscalation', true) != false)
        then 'allowPrivilegeEscalation' else null,
        if anyCtr(function(t, c) effective(t, c, 'runAsNonRoot') != true)
        then 'runAsNonRoot' else null,
        if anyCtr(function(t, c) effective(t, c, 'runAsUser') == 0)
        then 'runAsUser' else null,
        // Restricted requires seccomp to be SET, not merely not-Unconfined.
        if anyCtr(function(t, c)
          local ctr = std.get(std.get(ctrSec(c), 'seccompProfile', {}), 'type', null);
          local pod = std.get(std.get(podSec(t), 'seccompProfile', {}), 'type', null);
          local eff = if ctr != null then ctr else pod;
          !std.member(['RuntimeDefault', 'Localhost'], std.get({ v: eff }, 'v', '')))
        then 'seccompProfile' else null,
        // Must drop ALL; only NET_BIND_SERVICE may then be added back.
        if anyCtr(function(t, c)
          local caps = std.get(ctrSec(c), 'capabilities', {});
          !std.member(std.get(caps, 'drop', []), 'ALL')
          || std.length(std.setDiff(std.set(std.get(caps, 'add', [])), std.set(['NET_BIND_SERVICE']))) > 0)
        then 'capabilities' else null,
      ]);

      if baselineFailures != [] then { level: 'privileged', violates: baselineFailures }
      else if restrictedFailures != [] then { level: 'baseline', violates: restrictedFailures }
      else { level: 'restricted', violates: [] },
}
