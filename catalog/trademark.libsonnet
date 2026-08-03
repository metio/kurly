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
//     posture: 'restricted' | 'unrestricted' | 'unaddressed',
//     policy: '<url>',                  // required: the page this was read from
//     neutralName: '<name>',            // optional, and only where the project
//                                       // or common practice offers one — not
//                                       // a name invented here
//     note: '<what the policy actually restricts>',   // optional
//   }
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
}
