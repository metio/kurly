// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Generates one renderable composition for every catalog entry × the kinds it
// declares legal, using each parameter's example (or default) value — so every
// feature, exposure recipe, security profile, and kind is proven to render and
// schema-validate on every kind it claims to support. Emits [{ name, snippet }];
// check-coverage renders each snippet and runs it through kubeconform. Because
// the set is generated straight from catalog.json, a newly annotated feature is
// covered automatically and a generation gap is caught by the count assertion in
// the gate.
local catalog = import '../catalog/catalog.json';

// Compact Jsonnet literal for a JSON value (JSON is valid Jsonnet).
local lit(v) = std.manifestJsonEx(v, '', '', ': ');

// An argument's value is its example, else its default; it is "provided" when it
// has either. EVERY provided argument renders named, never positional — the same
// rule the assembler uses.
//
// Named is not a style preference here. A positional call binds by ORDER, so the
// catalog's arg order silently becomes part of the contract: list two arguments
// in an order the function does not declare and every value lands in the wrong
// parameter, rendering a manifest that is valid and means something else.
// Jsonnet has no types to catch it — d.T.string is documentation, not a check —
// so it surfaces only where a schema happens to disagree, and not at all where
// two neighbouring arguments are both strings. Named calls make the order
// irrelevant and delete the whole class.
local argValue(a) = if std.objectHas(a, 'example') then a.example else a.default;
local provided(a) = std.objectHas(a, 'example') || std.objectHas(a, 'default');
local argExprs(args) = [
  a.name + '=' + lit(argValue(a))
  for a in args
  if provided(a)
];
local call(prefix, entry) = prefix + '(' + std.join(', ', argExprs(entry.args)) + ')';

local kindById = { [k.id]: k for k in catalog.kinds };
local baseFor(kindId) = call('kurly.' + kindId, kindById[kindId]);
local snippetFor(kindId, term) =
  "local kurly = import 'github.com/metio/kurly/main.libsonnet'; kurly.list(" + baseFor(kindId) + term + ')';

// A bare kind, each feature on each legal kind, each exposure recipe and security
// profile on http (the kind that carries a Service and the representative pod).
local kindCases = [
  { name: 'kind-' + k.id, snippet: snippetFor(k.id, '') }
  for k in catalog.kinds
];
local featureCases = [
  { name: 'feature-' + f.id + '-' + kindId, snippet: snippetFor(kindId, ' + ' + call('kurly.' + f.id, f)) }
  for f in catalog.features
  for kindId in f.kinds
];
// A modifier that adds rules to an HTTPRoute (guard) needs an exposure present to
// attach to, so prepend a representative one; the true exposures and the
// Service-only modifiers (referenceGrant) render on a bare http.
local exposeCases = [
  {
    name: 'expose-' + e.id,
    snippet: snippetFor(
      'http',
      (if std.objectHas(e, 'requiresExposure') && e.requiresExposure
       then " + kurly.expose.gateway('coverage.example.com', 'shared')"
       else '')
      + ' + ' + call('kurly.expose.' + e.id, e)
    ),
  }
  for e in catalog.expose
];
local securityCases = [
  { name: 'security-' + s.id, snippet: snippetFor('http', ' + kurly.security.' + s.id) }
  for s in catalog.security
];
// Each composable network variant on http. denyAll is a standalone generator
// (not a mixin), so it is skipped here and documented rather than composed.
local networkCases = [
  { name: 'network-' + n.id, snippet: snippetFor('http', ' + ' + call('kurly.network.' + n.id, n)) }
  for n in catalog.network
  if !(std.objectHas(n, 'standalone') && n.standalone)
];

kindCases + featureCases + exposeCases + securityCases + networkCases
