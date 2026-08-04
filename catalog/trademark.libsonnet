// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// What a project's own TRADEMARK POLICY says about using its name and logo.
//
// A trademark policy is in force whether or not the people holding it have ever
// heard of anybody running this catalogue. That makes it a different kind of
// fact from consent.libsonnet, which records something a maintainer SENT us:
//
//   consent    absent means NOBODY ASKED, so nobody objected.
//   trademark  absent means WE DO NOT KNOW, and unknown is NOT permission.
//
// Most of the catalogue sits at unknown, and that is the honest state rather
// than a gap to be filled with a guess. A consumer that reads an absent entry as
// "go ahead" is asserting a licence nobody granted; what it does with unknown is
// its own decision, but it must be able to tell unknown from permitted.
//
// NEVER DERIVED FROM THE LICENCE. The code licence and the trademark are
// separate grants and they routinely disagree — a permissively licensed project
// with a strict mark is the ordinary case, not the exception. A posture inferred
// from `license` would be a guess wearing the clothes of a fact, which is the one
// thing this catalogue does not publish.
//
// NOT WHETHER WE HOLD PERMISSION. Partner programmes exist, and being a partner
// is a fact about one deployment rather than about the software. That belongs in
// an operator's own configuration, so that a fork holding different permissions
// says so without editing this file. A record here describes what the PROJECT
// published, full stop.
//
// NOT A LEGAL DETERMINATION either. Whether a particular listing is nominative
// use is a question for a lawyer and for the operator asking it. This file
// records what the policy says and links it, so the answer to "why is it listed
// under that name" points at the project's own page instead of at somebody's
// reading of it.
//
// ── the shape ───────────────────────────────────────────────────────────────
//
//   '<workload-id>': {
//     posture: 'restricted' | 'permitted-with-attribution' | 'unrestricted'
//              | 'unaddressed',
//     policy: '<url>',                  // required: the page this was read from
//     neutralName: '<name>',            // optional, and only where the project
//                                       // or common practice offers one — not
//                                       // a name invented here
//     note: '<what the policy actually restricts>',   // optional
//   }
//
// `permitted-with-attribution` means the policy GRANTS the use a catalogue entry
// makes — naming a service after the software — on a condition about how it is
// presented: that the page says who runs the service, and does not let the mark
// outrank that. Named for the CONDITION rather than for the permission, because
// the condition is the part that has to survive a redesign.
//
// It exists because `restricted` was not merely mislabelling these; it was
// withholding the name. A consumer falling back to a neutral name published
// OpenSearch as `opensearch` — doing the one thing its holders went out of their
// way to say was unnecessary, on the strength of a value that meant "we could
// not tell". A posture that cannot express "yes, if you attribute" turns a
// permission into a prohibition.
//
// The condition is not optional. Taking a permission and quietly not honouring
// what it was granted for is worse than never having read the policy, because it
// looks like diligence. A consumer that cannot render the attribution should
// treat this exactly as `restricted`.
//
// `unaddressed` means SOMEBODY READ IT AND IT DOES NOT SAY. A project can have a
// long trademark policy that never addresses using its name to offer the software
// as a service — and a reader cannot tell that from a workload nobody has looked
// at yet, because both are silence. This makes the two distinguishable: absent
// means nobody looked, `unaddressed` means somebody did and came back
// empty-handed. It is not permission, and a consumer must treat it exactly as it
// treats absent.
//
// `policy` is required because a posture with nothing behind it is an assertion
// about somebody else's rights with no way to check it. Absent from this file
// entirely is the right way to say "we have not looked".
//
// ── what has been looked at ─────────────────────────────────────────────────
//
// 2026-08-04: every workload in the catalogue was swept, by fetching each
// project's homepage and FOLLOWING the links it already carries whose href
// mentions trademark/brand/legal, and by asking GitHub for each repository's
// real file list rather than guessing filenames. That is what the first pass
// could not do — it guessed paths and filenames, and a policy nobody guesses the
// path of is invisible to it.
//
// Sixteen workloads had a discoverable policy page that way. The rest were then
// found by looking for them BY NAME, which is how the foundation-held marks
// arrived: the mark is not the project's to publish a policy about, so its site
// links a foundation's one policy instead of restating it, and a
// JavaScript-rendered footer is invisible to a probe reading raw HTML.
//
// The workloads not in this file were therefore looked FOR and not found, which
// is still `absent` — the file has no way to say "searched, nothing published",
// and adding one would change a value a consumer switches on. Treat absent
// exactly as before: unknown, and never permission.
{
  // Read from the policy itself rather than from reputation. It permits using
  // the name to promote a project built on WordPress, and then restricts the two
  // places a hosting listing would most naturally put it:
  //
  //   "Under no circumstances is it permitted to use WordPress or WordCamp as
  //    part of a domain name or top-level domain name."
  //   "Please do not use 'WP' in any way that confuses people."
  //
  // The domain-name line is the one worth noticing early: a URL is the hardest
  // thing to change later, because every link anybody saved breaks with it.
  // Read from the policy. Drupal's rule is combination: the mark may appear in a
  // product or service name only alongside your own, and never as the whole of a
  // domain or company name.
  //
  //   "The name of your company or organization should be used in combination
  //    with the Drupal trademark so that there can be no confusion about the
  //    true source … of your product or service."
  //
  // Its own examples of what is NOT allowed are close to a hosting listing:
  // "Drupal Hosting LLC", "Drupal Services Inc.", a "drupal.tld" domain.
  drupal: {
    posture: 'restricted',
    policy: 'https://www.drupal.org/trademark',
    note: 'The mark may be used only in combination with your own name, so the source is unambiguous; never as a whole company name or domain ("Drupal Hosting LLC", "drupal.tld" are the policy\'s own counter-examples).',
  },
  // The Linux Foundation's usage policy, which Jenkins points at. It binds
  // exactly the case a hosting listing is:
  //
  //   "You need to comply with the Trademark Usage Policy if you are using the
  //    term 'Jenkins' as part of your own trademark or brand identifier for
  //    Jenkins-based software goods or services."
  // A registered EUIPO word mark, with a policy that separates the code grant
  // from the brand in as many words: "The AGPLv3 covers the code; this policy
  // covers the branding." Self-hosting for yourself, a club or a class is
  // explicitly free. What needs written permission is exactly this catalogue's
  // consumer:
  //
  //   "Offering paid hosting, SaaS, or commercial cloud services under the
  //    Endurain name."
  //
  // And for anyone tempted to fork around it: "If your fork is commercial
  // (offering paid hosting, subscriptions, or products), you must rename it and
  // remove the Logos unless you have written permission."
  endurain: {
    posture: 'restricted',
    policy: 'https://github.com/endurain-project/endurain/blob/master/TRADEMARK.md',
    note: 'Non-commercial self-hosting may use the name freely; offering paid hosting or SaaS under it needs prior written permission, and a commercial fork must be renamed.',
  },
  // MIT code, and the policy says in as many words that the brand is not part of
  // that grant: "The Code is free to use, modify, and distribute under the MIT
  // terms. The Brand (Trademarks) is NOT licensed under MIT." What it then
  // forbids is the listing itself:
  //
  //   "You may not use 'Frigate' in the name of a commercial product, service,
  //    or app."
  //
  // Plus confusing domain names, and a fork must be renamed and the logo
  // removed. A good example of why a posture is never derived from a licence.
  frigate: {
    posture: 'restricted',
    policy: 'https://github.com/blakeblackshear/frigate/blob/master/TRADEMARK.md',
    note: 'MIT covers the code and explicitly not the brand: the name may not be used in a commercial product or service name, nor in a confusing domain; a fork must be renamed.',
  },
  jenkins: {
    posture: 'restricted',
    policy: 'https://www.jenkins.io/project/trademark/',
    note: 'Using "Jenkins" as part of a brand identifier for Jenkins-based goods or services is governed by the Linux Foundation Trademark Usage Policy.',
  },
  // The sharpest of the four: it names hosting, and it names it as the thing
  // that needs permission.
  //
  //   "You are not allowed to use the Nextcloud marks for advertisement,
  //    promotion, marketing or sales purposes for commercial Nextcloud services
  //    like support or hosting or development around Nextcloud without
  //    permission from Nextcloud GmbH."
  //
  // And, so there is no reading of it as covering only the wordmark:
  //
  //   "you can not use the Nextcloud marks to advertise hosting of a Nextcloud
  //    VM or Docker image on your hosting service without permission."
  // Open Source Matters holds the mark, and permission is the default position:
  // "Although those rights are exclusively ours, we are happy to give people
  // permission to use the term under certain circumstances." Unpermitted use is
  // narrow and comes with conditions — make clear you are not OSM, imply no
  // endorsement — and the project keeps a separate domain-name policy and a list
  // of approved domains, which is the part a hosting URL runs into.
  joomla: {
    posture: 'restricted',
    policy: 'https://tm.joomla.org/trademark-policy.html',
    note: 'Open Source Matters grants permission case by case; unpermitted use requires disclaiming affiliation, and domain names are governed separately with an approved-domains list.',
  },
  // A Model Trademark Guidelines policy. Its operative sentence puts the burden
  // squarely on the user of the mark: "Any use that does not comply with this
  // Policy or for which we have not separately provided written permission is
  // not a use that we have approved, so you must decide for yourself whether the
  // use is nevertheless lawful."
  leantime: {
    posture: 'restricted',
    policy: 'https://leantime.io/trademark',
    note: 'Model Trademark Guidelines: uses outside the policy need separate written permission, and the policy declines to say whether anything else is lawful.',
  },
  // The mark is held by Open Source Collective on the project's behalf, and a
  // licence is the entry condition rather than the exception: "You may use the
  // Mautic trademarks (including accompanying official logos) for your own
  // purposes, but you must first obtain a license."
  mautic: {
    posture: 'restricted',
    policy: 'https://www.mautic.org/trademark',
    note: 'Any use of the marks requires a licence first, granted automatically or on application; the mark is held by Open Source Collective for the project.',
  },
  // MySQL is Oracle's mark, governed by Oracle's Third Party Usage Guidelines.
  // A narrow family of "Conditional Use Logos" may be shown without written
  // permission, on conditions Oracle judges "in its sole discretion"; anything
  // else is a request. Note the workload is the operator's InnoDBCluster, but
  // the mark on the listing would be MySQL either way.
  'mysql-cluster': {
    posture: 'restricted',
    policy: 'https://www.mysql.com/about/legal/trademark.html',
    note: "Oracle's Third Party Usage Guidelines govern; only a narrow set of Conditional Use Logos may be shown without written permission, and Oracle judges the conditions at its own discretion.",
  },
  // Checked, and it does not answer. mediawiki.org publishes no trademark page;
  // the Wikimedia policy is the only one there is, and its MediaWiki passages are
  // about not mimicking the look of Wikimedia's own sites. What it does say
  // points the other way — "You do not need to contact us if you just want to use
  // the MediaWiki software to create a wiki" — and it addresses using the NAME to
  // offer hosting nowhere at all.
  //
  // Recorded rather than left absent so a reader can tell this from a workload
  // nobody has looked at. It is not permission.
  mediawiki: {
    posture: 'unaddressed',
    policy: 'https://foundation.wikimedia.org/wiki/Policy:Trademark_policy',
    note: 'The Wikimedia policy governs the Wikimedia marks and the look of its sites; it says using the MediaWiki software needs no contact, and does not address the name in a commercial listing either way.',
  },
  nextcloud: {
    posture: 'restricted',
    policy: 'https://nextcloud.com/trademarks/',
    note: 'Advertising commercial Nextcloud hosting under the marks requires permission from Nextcloud GmbH; the policy names hosting a Nextcloud image explicitly.',
  },
  // NOT RECORDED: mediawiki. The Wikimedia trademark policy is the only page
  // there is — mediawiki.org has none — and what it says about MediaWiki points
  // the other way: "You do not need to contact us if you just want to use the
  // MediaWiki software to create a wiki." Its MediaWiki passages are about not
  // mimicking the look of Wikimedia's own sites, and it does not address using
  // the name in a commercial listing either way. A page existing is not an
  // answer to the question, so this stays unknown rather than being classified
  // from the fact that a policy exists somewhere.
  // Fair use is granted for showing support, and withdrawn precisely where a
  // hosting listing sits: the word mark may be used "provided that: There is no
  // commercial purpose behind the use and you are not offering Pi-hole
  // commercially under the same domain name". The logo is not granted at all.
  pihole: {
    posture: 'restricted',
    policy: 'https://pi-hole.net/trademark',
    note: 'Fair use of the word mark is conditioned on there being no commercial purpose and on not offering Pi-hole commercially under the same domain; the logo is excluded.',
  },
  // The strictest of the set, and it does not turn on commerciality: "You may not
  // include the PhotoPrism trademark in the name of your app, product, or
  // service, whether commercial or non-commercial in nature", which it spells out
  // as covering online services. The logo is never permitted for a product.
  // The Foundation's grant is nominative and no wider: permission "for the
  // purpose of referring to the openHAB software and project", with the marks
  // barred from any use suggesting endorsement, sponsorship or affiliation
  // unless expressly authorised. Naming a hosted service after it is the use the
  // grant does not reach.
  openhab: {
    posture: 'restricted',
    policy: 'https://www.openhab.org/about/trademark',
    note: 'Permission is granted to refer to the software, not to trade under the marks; any use implying endorsement or affiliation needs express authorisation.',
  },
  photoprism: {
    posture: 'restricted',
    policy: 'https://www.photoprism.app/trademark',
    note: 'The name may not appear in the name of any app, product or service, commercial or not; the logo may never be used for one.',
  },
  // Explicit on both halves of the question. Use of the word mark is granted only
  // where "There is no commercial purpose behind the use", and separately:
  //
  //   "You may not form a company, use a company name, or create a software
  //    product name that includes the 'RabbitMQ' trademark."
  rabbitmq: {
    posture: 'restricted',
    policy: 'https://www.rabbitmq.com/trademark-guidelines',
    note: 'The word mark is granted only for non-commercial use, and may not appear in a company name or a software product name.',
  },
  wordpress: {
    posture: 'restricted',
    policy: 'https://wordpressfoundation.org/trademark-policy/',
    note: 'The name may be used to describe a project built on WordPress, but never as part of a domain name; "WP" must not be used confusingly.',
  },

  // ── marks held by a foundation ──────────────────────────────────────────────
  //
  // The first pass looked for a policy on each PROJECT's own site and in its own
  // repository, and found four. It could not have found these: the mark is not
  // the project's to publish a policy about. It belongs to a foundation, which
  // publishes ONE policy covering everything it holds, and the project site
  // links it from the footer rather than restating it.
  //
  // Each was read at its source, and the workloads below are the ones whose own
  // NAME is the mark in question — not every project a foundation touches.

  // Apache Software Foundation. Naming a service after the mark is not a grey
  // area here; the policy lists it among uses that are "probably infringing":
  //
  //   "Software service offerings that are for anything other than official
  //    ASF-distributed software."
  //   "You may not use ASF trademarks such as 'Apache' or 'ApacheFoo' or 'Foo'
  //    in your own domain names if that use would be likely to confuse a
  //    relevant consumer" — without the written approval of the VP, Brand
  //    Management.
  //
  // Factual reference to the software stays nominative fair use; branding a
  // service does not.
  local asf = {
    posture: 'restricted',
    policy: 'https://www.apache.org/foundation/marks/',
    note: 'Naming a service after the mark is listed among uses that are probably infringing, and a confusing domain name needs written approval from the ASF VP, Brand Management; factual reference to the software remains nominative fair use.',
  },
  'cassandra-cluster': asf,
  couchdb: asf,
  guacamole: asf,
  answer: asf,
  tika: asf,

  // The Linux Foundation, which holds these as marks in its own name — the
  // published list carries Prometheus®, NATS™, OpenTelemetry™, Thanos™,
  // OpenCost™, Kubernetes® and Keycloak™. Its usage policy allows the reference
  // a catalogue entry makes and refuses the two placements a hosting product
  // would want:
  //
  //   "You may make fair use of word marks to make true factual statements."
  //   "A trademark should not be used as your domain name or as part of your
  //    domain name."
  //   "A trademark should not be used as part of your product name."
  //
  // Deliberately NOT applied to every project that links this policy. The same
  // page says projects "operating as separately incorporated entities" keep
  // their own marks and guidelines, and the LF list does not name Valkey or
  // Distribution — so those stay absent rather than borrowing a posture from a
  // policy their names do not appear in.
  local lf = {
    posture: 'restricted',
    policy: 'https://www.linuxfoundation.org/trademark-usage/',
    note: 'Fair use of the word mark for true factual statements is permitted; the mark may not be used as, or as part of, a product name or a domain name.',
  },
  prometheus: lf,
  nats: lf,
  'otel-collector': lf,
  thanos: lf,
  opencost: lf,
  keycloak: lf,
  'metrics-server': lf,

  // Eclipse Foundation, which states the naming rule and then supplies the two
  // forms it will accept, which is more than most policies do:
  //
  //   "You may not incorporate the name of an Eclipse Project Trademark into
  //    the name of your company or software product name."
  //   "<product name> for <Eclipse project name>" or
  //   "<product name>, <Eclipse project name> Edition"
  mosquitto: {
    posture: 'restricted',
    policy: 'https://www.eclipse.org/legal/logo-guidelines/',
    note: 'The project name may not be incorporated into a company or product name; the accepted forms are "<product> for Eclipse Mosquitto" or "<product>, Eclipse Mosquitto Edition".',
  },

  // The PostgreSQL Community Association of Canada. Both workloads are listed
  // under the PostgreSQL name, so both carry its mark whatever provisions them.
  //
  //   "Do not use the marks in a business name or trade name."
  //   "if you want to use our marks (or some variant of them) in your company
  //    name, product name or domain name, you must obtain prior approval."
  local pgca = {
    posture: 'restricted',
    policy: 'https://www.postgresql.org/about/policies/trademarks/',
    note: 'The marks may not be used in a business, trade, product or domain name without prior approval; commercial uses are asked to carry the registered symbol.',
  },
  postgres: pgca,
  'cnpg-cluster': pgca,

  // LF Projects, LLC — the entity the Linux Foundation page means when it says
  // projects "operating as separately incorporated entities" hold their own
  // marks. Its policy repeats the same two refusals for every Series it covers:
  //
  //   "You may make fair use of word marks to make true factual statements",
  //   but "fair use does not permit you to state or imply that the owner of a
  //   mark produces, endorses, or supports your company, products, or services."
  //   "A trademark should not be used as part of your product name."
  //   "A trademark should not be used as your domain name or as part of your
  //    domain name."
  valkey: {
    posture: 'restricted',
    policy: 'https://lfprojects.org/policies/trademark-policy/',
    note: 'Factual reference is fair use, but the mark may not be part of a product name or a domain name, and nothing may imply the project endorses the service.',
  },

  // PrestaShop SA. The page is a general legal notice rather than a trademark
  // policy, and it addresses exactly one placement — but it addresses it
  // absolutely: "Using the PrestaShop SA trademark in a domain name is strictly
  // prohibited", with the warning that it "may result in legal proceedings".
  // What it does not say is anything about a product or service name.
  prestashop: {
    posture: 'restricted',
    policy: 'https://www.prestashop-project.org/legal/',
    note: 'Use of the mark in a domain name is strictly prohibited; the notice says nothing either way about a product or service name.',
  },

  // ── read, and still not established ─────────────────────────────────────────
  //
  // These projects link the Linux Foundation usage policy from their own sites,
  // and that policy does forbid putting a mark in a product or domain name — but
  // it governs the marks the Foundation holds, and its published list does not
  // name any of these. So the policy is real, it was read, and it does not settle
  // whether THIS name is one of the marks it binds.
  //
  // That is what `unaddressed` is for. It is not permission, and it is not the
  // same as absent: absent means nobody looked, and somebody has now looked at
  // every workload in this catalogue.
  local lfUnlisted = {
    posture: 'unaddressed',
    policy: 'https://www.linuxfoundation.org/trademark-usage/',
    note: "The project links the Linux Foundation usage policy, which forbids a mark in a product or domain name — but the Foundation's published trademark list does not name this one, so whether the policy binds it is unestablished.",
  },
  alertmanager: lfUnlisted,
  'blackbox-exporter': lfUnlisted,
  registry: lfUnlisted,
  'oauth2-proxy': lfUnlisted,

  // ── found by name, not by link ──────────────────────────────────────────────
  //
  // The link-following probe cannot see a footer that only exists after the
  // page runs its JavaScript, which is most modern project sites. These were
  // found by looking for the policy directly and then reading it.

  // Grafana Labs holds Loki® and Tempo® as registered marks — its published
  // trademark list names both — and the policy refuses both placements a hosting
  // product wants:
  //
  //   "Do not use the Grafana Labs Marks as part of your product or service
  //    name, or incorporate them into your company's logos or designs."
  //   "Do not incorporate the Grafana Labs Marks into the name or logo of your
  //    website, domain name, Internet keywords, social media accounts."
  local grafana = {
    posture: 'restricted',
    policy: 'https://grafana.com/trademark-policy/',
    note: 'A registered Grafana Labs mark: it may not be part of a product or service name, nor of a website or domain name; other commercial use needs written permission.',
  },
  loki: grafana,
  tempo: grafana,

  // OpenSearch is the one policy in this file that AFFIRMATIVELY PERMITS the
  // case a hosting catalogue is, and the three-value posture flattens that: it
  // reads `restricted` beside Apache, whose answer is nearly the opposite.
  //
  //   "use the 'OpenSearch' word mark to refer to services for, or software that
  //    works with, OpenSearch" — provided an identifier shows you as the source
  //    ("Foocorp's OpenSearch Tool") and your branding is the more prominent.
  //
  // The restrictions that remain are placement rather than permission: a primary
  // domain needs consent, a subdomain does not, and nothing may imply the
  // project endorses the service.
  'opensearch-cluster': {
    posture: 'permitted-with-attribution',
    policy: 'https://opensearch.org/trademark-brand-policy/',
    note: 'Explicitly permits using the name to refer to a service for OpenSearch, provided your own branding is more prominent and identifies you as the source; a primary domain still needs permission, a subdomain does not.',
  },

  // Mastodon gGmbH permits running a server under the marks and refuses exactly
  // one placement, which happens to be the durable one:
  //
  //   "You may not use the Mastodon word mark, or any similar mark, in your
  //    domain name, unless you have written permission from Mastodon gGmbH."
  //   "you may use the Mastodon marks included in the Mastodon server software
  //    for the purposes of running the server."
  mastodon: {
    posture: 'restricted',
    policy: 'https://joinmastodon.org/trademark',
    note: 'Running a server under the marks is permitted for unmodified or lightly modified software; the word mark may not appear in a domain name without written permission.',
  },

  // Jellyfin, Inc. answers this catalogue's question more squarely than anything
  // else in this file, and answers it CONDITIONALLY — the condition being
  // whether money changes hands:
  //
  //   "Any instance of the Jellyfin software running for any purpose accessible
  //    for no fee to its users is granted an implicit license to use the name
  //    and logo for that purpose."
  //   "If you charge for access to your server in any form, you are required to
  //    change the branding of the server in some way to clearly identify that
  //    the server owner is not 'Jellyfin' as a project, and provide at least one
  //    method of contact for the server."
  //
  // So a free instance may carry the name and a paid one may not, unchanged.
  // Deliberately NOT `permitted-with-attribution`, and this is the reasoning
  // rather than an oversight. Jellyfin's condition is not about presentation, it
  // is whether the instance is free to its users — and evaluating that requires
  // knowing whether the OPERATOR charges. A catalogue that knew that would stop
  // describing the world and start describing one deployment, and the next
  // person running kurly for a free community instance would inherit an answer
  // computed for somebody else's business.
  //
  // So it fails closed. That costs a free operator a name they were entitled to
  // use, which is the cheap direction to be wrong in.
  jellyfin: {
    posture: 'restricted',
    policy: 'https://jellyfin.org/docs/project/branding/',
    note: 'A free instance has an implicit licence to use the name and logo; charging for access in any form requires rebranding the server so it is clear the operator is not the project, plus a contact method.',
  },
}
