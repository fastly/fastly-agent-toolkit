# Observability and ops reference architectures

## fastly-log-analytics — log streaming + Object Storage dashboard
- **Repo:** github.com/fastly/fastly-log-analytics
- **Source:** official (fastly org)
- **Demonstrates:** a self-hosted request-level log analytics dashboard, explicitly positioned as the complement to Fastly's aggregate stats APIs (the `fastly-stats` skill covers those APIs; this is a system built on top of the logs they stream).
- **Watch out for:** none known as of last verification.
- **Last verified:** 2026-08-19

## fos-migrator — bulk content migration into Object Storage
- **Repo:** github.com/benjaminshaver/fos-migrator
- **Source:** community (benjaminshaver)
- **Demonstrates:** an operational tool/pattern for bulk-loading existing content into Object Storage — an ops task rather than a request-serving pattern, which is why it belongs in this file rather than compute-application-patterns.
- **Watch out for:** none known as of last verification.
- **Last verified:** 2026-08-19
