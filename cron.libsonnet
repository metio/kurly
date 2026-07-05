// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cron: a scheduled job — a CronJob that refuses overlapping runs
// (concurrencyPolicy Forbid) and restarts failed containers (OnFailure).
// The schedule is a required argument: there is no sensible default cadence.
local base = import './base.libsonnet';
local k = import './k.libsonnet';

{
  new(name, image, schedule)::
    base.core(name, image)
    + {
      config+:: {
        schedule: schedule,
        concurrencyPolicy: 'Forbid',
      },

      cronjob:
        local cfg = self.config;
        local podSecurity = self.podSecurity;
        k.batch.v1.cronJob.new(cfg.name, cfg.schedule, [self.container])
        + k.batch.v1.cronJob.metadata.withLabels(self.labels)
        + k.batch.v1.cronJob.spec.withConcurrencyPolicy(cfg.concurrencyPolicy)
        + k.batch.v1.cronJob.spec.jobTemplate.spec.template.metadata.withLabelsMixin(self.labels)
        + k.batch.v1.cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure')
        + { spec+: { jobTemplate+: { spec+: { template+: { spec+: podSecurity } } } } }
        + (
          if cfg.annotations == {}
          then {}
          else
            k.batch.v1.cronJob.metadata.withAnnotations(cfg.annotations)
            + k.batch.v1.cronJob.spec.jobTemplate.spec.template.metadata.withAnnotations(cfg.annotations)
        )
        + (
          if cfg.serviceAccountName == null
          then {}
          else k.batch.v1.cronJob.spec.jobTemplate.spec.template.spec.withServiceAccountName(cfg.serviceAccountName)
        ),

      withSchedule(schedule):: self + { config+:: { schedule: schedule } },
      withConcurrencyPolicy(concurrencyPolicy):: self + { config+:: { concurrencyPolicy: concurrencyPolicy } },
    },
}
