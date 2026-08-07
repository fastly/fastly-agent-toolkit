# Verifying a Change With Stats

How to use stats to answer "did my change do what I intended?" — as opposed to looking up a number.
These techniques are not obvious from endpoint documentation, and each one has settled a question
that reading config could not.

For endpoint shapes see [historical-stats-api.md](historical-stats-api.md) and
[realtime-api.md](realtime-api.md); for field semantics and aggregation shape see
[fields.md](fields.md). This file is only about method.

## Contents

- [Step 1: baseline before you touch anything](#step-1-baseline-before-you-touch-anything)
- [Pick the metric that will give the cleanest answer](#pick-the-metric-that-will-give-the-cleanest-answer)
- [Quantify in σ, not percent](#quantify-in-σ-not-percent)
- [Competing-hypothesis arithmetic](#competing-hypothesis-arithmetic)
- [Cross-check across sources](#cross-check-across-sources)
- [Confounds to name explicitly](#confounds-to-name-explicitly)
- [Checklist](#checklist)

## Step 1: baseline before you touch anything

Per-POP history exists (`datacenter=` is a real filter) but `by=minute` is retained only ~1 day and
real-time only 120 seconds. **The fine-grained pre-change state is unrecoverable after that window
passes.** Snapshot first; it is the cheapest step and the only irreversible one.

Capture *several* baseline samples, not one — you need a spread to compute σ later, and one sample
cannot distinguish your change from normal variance.

```bash
KEY="Fastly-Key: $(fastly auth token --quiet)"
CODES=$(curl -sS -H "$KEY" https://api.fastly.com/datacenters | jq -r '.[].code' | paste -sd, -)
NOW=$(date -u +%s)
curl -sS -H "$KEY" \
  "https://api.fastly.com/stats/service/$SID?from=$((NOW-3600))&to=$NOW&by=minute&datacenter=$CODES" \
  > "baseline-$NOW.json"     # timestamp the file: the window is not recoverable from content alone
```

## Pick the metric that will give the cleanest answer

Decide **in advance** which metric will show the change most unambiguously. Ranked by how little
argument they invite:

1. **A zero-to-nonzero transition.** If your change makes a POP start doing something it did not do
   before, that metric going `0 → nonzero` needs no baseline model and has no confound. When a new
   shield tier came online, its `shield` field went `0 → 209,432` per 120 s — nothing to dispute.
2. **A ratio within one window.** Hit ratio, offload, share-of-service. Immune to window
   misjudgement because numerator and denominator come from the same samples.
3. **An absolute rate.** Weakest: needs a correct window *and* a baseline, and is the only form that
   broke when a window was misread. If you must report one, print the derived window beside it.

Design the change so a category-1 metric exists if you can.

## Quantify in σ, not percent

A percentage change is unpersuasive when you cannot say what normal drift looks like. Take several
baseline samples, compute the standard deviation, and state the step in multiples of it.

```text
step:      +118,593 req/min
baseline:  σ = 9,835 req/min
           -> 12σ                      <- not arguable
same step as a percentage: +21.8%      <- weak: an unrelated POP drifted +9.0% in the same window
```

The percent figure over-attributes, because it silently treats ambient drift as zero. **σ against a
measured baseline is the defensible form.**

**Always include untouched control POPs in the same window.** POPs you did not change should hold
flat; if they moved as much as the treatment POPs, you measured something ambient. In one
verification the treatment POPs moved −32 to −52 ms while three control POPs moved ±6 ms — the
controls are the entire reason the latency claim held up.

## Competing-hypothesis arithmetic

When two readings of a topology are both plausible, do not argue from config. **Predict a third
POP's volume under each hypothesis and compare against what was observed.** The wrong hypothesis
usually misses by an order of magnitude:

```text
observed at the third POP:        3,251,651
hypothesis A (chained tiers):     3,077,854   (−5.6%)   <- consistent
hypothesis B (either/or routing): 1,415,803   (+130%)   <- excluded
```

This settled a disagreement with a domain expert that reading VCL could not. It works because the
tier fields are adjacency-linked: **a POP's outbound count is the next tier's inbound count**
(`shield_fetches` upstream = `shield` downstream; see
[fields.md](fields.md#is-this-pop-a-tier-or-the-last-hop)), so any topology hypothesis makes a hard
numeric prediction you can falsify.

## Cross-check across sources

Before trusting a series, reconcile it against an independent one and **state the agreement you
got** rather than assuming it:

- **Region-level vs per-POP sum.** A region series read 618,377 req/min while summing real-time
  `shield` across that region's POPs gave 626,944/min — 1.4% agreement, good enough to license using
  the cheaper region-level series for the rest of the analysis.
- **Per-POP sum vs unfiltered total.** Sweeping every POP code reconciled exactly (392 = 392) on a
  live service. Exact agreement is achievable on classic historical stats.
- **Replicate every headline number.** Two samples a few minutes apart agreed to within 0.3 pp on hit
  ratio and 0.5 pp on byte offload. A single real-time sample can catch a transient.

A reconciliation that *fails* is the most valuable outcome here — it usually means a filter was
silently dropped (see
[debugging.md](debugging.md#numbers-look-plausible-but-the-scope-is-wrong-http-200-right-shape-wrong-data)).

## Confounds to name explicitly

- **Cache warm-up.** A newly-added tier's hit ratio shortly after deployment is a **floor, not a
  steady state**. At T+72 min it is still filling. Re-read at T+24 h before treating it as the new
  normal, and say which you are reporting.
- **Ambient drift.** Quantified by your control POPs. Without controls you cannot separate it from
  your change.
- **Aggregation lag.** The most recent historical bucket keeps growing for minutes after it closes —
  do not read the final in-progress bucket.
- **Impossible derived values are your smoke alarm.** A negative byte offload, or an `origin_offload`
  of 119.99, means the arithmetic is wrong, not that the service is unusual. Sanity-check every
  derived figure against its valid range before reporting it — a *plausible* wrong number is the one
  that gets published.

## Checklist

Before publishing a verification:

- [ ] Per-POP baseline captured **before** the change, with its window recorded.
- [ ] Window derived from payload `recorded` timestamps, printed beside every absolute figure.
- [ ] Every ratio recomputed from counters, not summed or averaged across samples.
- [ ] Untouched control POPs reported alongside treatment POPs, same window.
- [ ] Step quantified in σ against measured baseline variance.
- [ ] `meta` asserted to echo every filter sent (no silently dropped `datacenter`).
- [ ] Headline numbers replicated in a second sample.
- [ ] Derived values checked against their valid ranges (ratios in `[0,1]`, offloads non-negative).
- [ ] Cache warm-up noted if a new tier or cache is involved, with a re-read scheduled.
