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
// has either. Provided args render positionally while every earlier arg is also
// provided, then switch to named once an optional one is skipped — the same rule
// the assembler uses, always valid Jsonnet.
local argValue(a) = if std.objectHas(a, 'example') then a.example else a.default;
local provided(a) = std.objectHas(a, 'example') || std.objectHas(a, 'default');
local argExprs(args) =
  std.foldl(
    function(acc, a)
      if !provided(a) then acc { gap: true }
      else acc { exprs+: [(if acc.gap then a.name + '=' else '') + lit(argValue(a))] },
    args,
    { exprs: [], gap: false }
  ).exprs;
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
local exposeCases = [
  { name: 'expose-' + e.id, snippet: snippetFor('http', ' + ' + call('kurly.expose.' + e.id, e)) }
  for e in catalog.expose
];
local securityCases = [
  { name: 'security-' + s.id, snippet: snippetFor('http', ' + kurly.security.' + s.id) }
  for s in catalog.security
];

kindCases + featureCases + exposeCases + securityCases
