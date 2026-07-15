// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Order-independence: kurly's central claim is that features write only config
// and every manifest recomputes from the merged whole, so composing the same
// features in ANY order yields identical manifests. This renders every
// permutation of a feature set and asserts they are byte-identical. Every field
// is a std.assertEqual, checked the same way as the main suite.
local kurly = import '../main.libsonnet';

// All permutations of an array (n! — keep the input small).
local permutations(arr) =
  if std.length(arr) <= 1 then [arr]
  else std.flattenArrays([
    [[arr[i]] + rest for rest in permutations(arr[0:i] + arr[i + 1:])]
    for i in std.range(0, std.length(arr) - 1)
  ]);

// Features touching DISJOINT config keys — genuinely commutative. Features that
// set the same scalar (two strategy() calls, a security profile then a hatch)
// are last-wins by design and deliberately excluded.
local features = [
  kurly.replicas(3),
  kurly.env({ LEVEL: 'info' }),
  kurly.store('/data', '1Gi'),
  kurly.runAs(1000),
  kurly.probes('/health'),
];

local base = kurly.http('web', 'ghcr.io/example/web:1.0.0');
local renderOf(perm) = std.manifestJson(kurly.list(std.foldl(function(app, f) app + f, perm, base)));
local distinct = std.set([renderOf(perm) for perm in permutations(features)]);

{
  // 5 features → 120 orderings, all rendering the same manifests.
  permutation_count: std.assertEqual(std.length(permutations(features)), 120),
  order_independent: std.assertEqual(std.length(distinct), 1),
}
