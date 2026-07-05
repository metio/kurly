// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// security: Pod Security Standards profiles as composable mixins, added onto
// any workload kind with `+` — the same axis pattern as expose. Every kind
// already ships `restricted`, so composing a profile only ever *relaxes* the
// posture:
//
//   restricted — the default, written out (compose it after another profile
//                to re-tighten)
//   baseline   — drops what only `restricted` requires: root is allowed, the
//                image's default capabilities stay, privilege escalation and
//                an unpinned seccomp profile are permitted. The extra
//                hardening kurly adds beyond PSS — read-only root filesystem,
//                user namespaces — is legal at every level and stays on.
//   privileged — no security fields at all; the manifest constrains nothing.
//
// Each profile sets every knob, so when several compose the last one wins,
// and the single-knob with* hatches still fine-tune afterwards. The
// ServiceAccount-token automount rule is not part of any profile — a workload
// without a ServiceAccount never needs apiserver credentials, whatever its
// PSS level.

local restricted = {
  runAsNonRoot: true,
  seccompProfile: 'RuntimeDefault',
  allowPrivilegeEscalation: false,
  dropAllCapabilities: true,
  readOnlyRootFilesystem: true,
  hostUsers: false,
};

{
  restricted:: { config+:: restricted },

  baseline:: {
    config+:: restricted {
      runAsNonRoot: false,
      seccompProfile: null,
      allowPrivilegeEscalation: true,
      dropAllCapabilities: false,
    },
  },

  privileged:: {
    config+:: restricted {
      runAsNonRoot: false,
      seccompProfile: null,
      allowPrivilegeEscalation: true,
      dropAllCapabilities: false,
      readOnlyRootFilesystem: false,
      hostUsers: true,
    },
  },
}
