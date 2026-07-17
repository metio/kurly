// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cron: a scheduled job — a CronJob that refuses overlapping runs
// (concurrencyPolicy Forbid) and restarts failed containers (OnFailure).
// The schedule is a required argument: there is no sensible default cadence.
// Tune it with kurly.schedule / kurly.concurrencyPolicy.
local base = import './base.libsonnet';
local k = import './k.libsonnet';

function(name, image, schedule)
  base.core(name, image)
  + {
    config+:: {
      schedule: schedule,
      concurrencyPolicy: 'Forbid',
    },

    cronjob:
      local cfg = self.config;
      local podSpec = self.podSecurity + self.podVolumes + self.podScheduling + self.podExtras;
      k.batch.v1.cronJob.new(cfg.name, cfg.schedule, self.podContainers)
      + k.batch.v1.cronJob.metadata.withLabels(self.labels)
      + k.batch.v1.cronJob.spec.withConcurrencyPolicy(cfg.concurrencyPolicy)
      + k.batch.v1.cronJob.spec.jobTemplate.spec.template.metadata.withLabelsMixin(self.podTemplateLabels)
      + k.batch.v1.cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure')
      + { spec+: { jobTemplate+: { spec+: { template+: { spec+: podSpec } } } } }
      + (if cfg.annotations == {} then {} else k.batch.v1.cronJob.metadata.withAnnotations(cfg.annotations))
      + (
        if self.podTemplateAnnotations == {}
        then {}
        else k.batch.v1.cronJob.spec.jobTemplate.spec.template.metadata.withAnnotations(self.podTemplateAnnotations)
      ),
  }
