// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The named resource sizes kurly.resourcePreset picks from: a memory request
// equal to its limit (a Guaranteed memory footprint) and a CPU request with no
// limit (CPU throttling is usually worse than letting a pod burst).
//
// They live in their own file because two things read them: the feature that
// applies one, and the catalog that publishes their values. A consumer sizing a
// deployment — or pricing one — reads the numbers rather than transcribing them,
// so a change here reaches it instead of silently disagreeing with it.
{
  nano: { requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '64Mi' } },
  micro: { requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '128Mi' } },
  small: { requests: { cpu: '250m', memory: '256Mi' }, limits: { memory: '256Mi' } },
  medium: { requests: { cpu: '500m', memory: '512Mi' }, limits: { memory: '512Mi' } },
  large: { requests: { cpu: '1', memory: '1Gi' }, limits: { memory: '1Gi' } },
}
