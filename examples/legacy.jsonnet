// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A legacy image that runs as root and expects its stock capabilities:
// compose the baseline security profile instead of chaining single-knob
// hatches. kurly's extra hardening beyond PSS (read-only root filesystem,
// user namespaces) stays on — this image also writes to /var/cache, so the
// writable-rootfs hatch fine-tunes AFTER the profile (a profile sets every
// security knob, so it would override an earlier hatch).
local kurly = import '../main.libsonnet';

kurly.list(
  (
    kurly.http.new('erp', 'ghcr.io/example/erp:5.4.1')
    .withHttpProbes('/status')
    + kurly.security.baseline
  )
  .withWritableRootFilesystem()
  + kurly.expose.ingress('erp.internal.example.com', ingressClass='nginx')
)
