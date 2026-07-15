// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A tiny docsonnet-shaped helper for describing kurly's public API. The shape
// mirrors grafonnet's doc-util (d.fn / d.arg / d.T.*) so the annotations read
// the same, but it carries no dependency: doc-util is not vendored, and pulling
// it in would add to the render-time closure kurly deliberately keeps at
// k8s-libsonnet alone. `fn` describes a callable, `arg` one of its parameters;
// kurly-specific facets a docs tool doesn't model (a feature's legal kinds, its
// exclusion group, whether it needs a Service) are merged onto an `fn` result
// with `+` at the annotation site.
{
  // Parameter type tags — a closed vocabulary the assembler UI renders inputs
  // from. `quantity`/`path`/`hostname` refine `string` for a nicer control.
  T:: {
    string: 'string',
    quantity: 'quantity',
    path: 'path',
    hostname: 'hostname',
    int: 'int',
    bool: 'bool',
    array: 'array',
    object: 'object',
    any: 'any',
  },

  // One parameter of a callable. A required parameter has no default; an
  // optional one carries its default (which may legitimately be null, e.g. an
  // unset storageClass — then the key is simply absent and the UI treats it as
  // optional-unset). `example` seeds the input control's placeholder.
  arg(name, type, required=false, default=null, example=null):: std.prune({
    name: name,
    type: type,
    required: required,
    default: if required then null else default,
    example: example,
  }),

  // A callable's documentation: prose help and its ordered parameter list.
  // Kurly facets (kinds/exclusiveGroup/requiresService/hasService) are added by
  // the annotation with `+ { … }`, keeping this helper purely descriptive.
  fn(help, args=[]):: {
    help: help,
    args: args,
  },
}
