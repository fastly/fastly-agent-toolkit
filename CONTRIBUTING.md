# Contributing a new skill

Thanks for wanting to add a skill to the Fastly Agent Toolkit.

Because this is an open source project rather than an internal collection, every skill should be useful, accurate, and portable across different agents, models, and tools.

## Start with a real problem

Good skills begin with real work and address problems that agents cannot solve reliably or efficiently without extra guidance.

If an agent already handles the task well, we probably do not need a skill for it, since unnecessary instructions only add noise and take up context.

Skills can also spare agents from repeating the same online research, especially when the information is stable or the workflow is not obvious.

For subjects that change often, however, teach the agent how to find the current source instead of copying details that will quickly become outdated.

With that in mind, read the existing skills before starting a new one, and extend an existing skill when its scope already covers the problem.

## Learn from a real session

The best process we have found is to complete the real task with an agent while bringing your own expertise and watching where it hesitates, searches in the wrong place, uses a tool incorrectly, or needs hard-to-find knowledge.

Once the task is finished, ask the agent what it learned and what would save time next time; if you use Swival, its `/learn` command can help with this step.

Treat that output as notes rather than as a finished skill: remove anything obvious or unhelpful, verify every technical claim, and rewrite the useful parts using your own domain knowledge.

Because this hands-on process is very different from asking a tool to invent a skill in the abstract, please do not use automated skill generators, including the Claude skill generator, to create your contribution.

In our experience, they tend to produce buggy, verbose skills that waste context and tokens, receive too little real-world testing, and are often tuned around one vendor's model.

You can still use AI tools for research and editing, but you remain responsible for understanding and checking everything you submit.

## Write a lean, portable skill

Although this guide is written for people, the skill itself will be read mainly by agents, so keep it direct and leave out prose or decorative formatting that spends context without helping with the task.

Keep it portable as well: do not rely on agent-specific metaskills, private conventions, or undocumented behavior from one client.

In practice, every skill lives in its own directory:

```text
skills/example-skill/
|-- SKILL.md
|-- references/       Optional detailed material
|-- scripts/          Optional reusable helpers
+-- examples/         Optional working examples
```

`SKILL.md` starts with YAML frontmatter:

```yaml
---
name: example-skill
description: Use when an agent needs to ...
---
```

Both fields are required, and the name must match the directory name.

Because agents use the description to decide whether to load the skill, name the tasks and terms that genuinely belong in scope and clarify the boundary with related skills.

Keep the essential workflow in `SKILL.md`, put detailed material in `references/`, and link each reference with a note explaining when to read it.

Add scripts or examples only when they make the workflow more reliable or reproducible, not simply to make the bundle look complete.

Since the bundle is public, do not include credentials, private data, or internal-only information.

When guidance depends on a particular tool or API version, say which version you checked and make sure the instructions still match current behavior.

Finally, add the skill to the "Available skills" section of `README.md`; there is no need to edit the plugin manifests because clients discover skills from the `skills/` directory.

## Use the skill yourself

Once you have a draft, use it for the real workflow it is meant to support, since reading it in isolation will not show whether it actually helps.

Run representative tasks from beginning to end, check every command, example, link, and expected result against current tools and authoritative sources, and test the exact version whenever the advice is version-specific.

Afterward, judge the quality of the final result rather than only whether the agent followed the instructions, because a skill that leads to a worse answer is not ready to merge.

## Evaluate it before opening a pull request

Hands-on testing is a good start, but every new skill should also be evaluated with a tool such as [Calibra](https://calibra.swival.dev) before it can be merged, as the existing skills have been. Internally, evaluations are maintained in the [fastly-agent-toolkit-evals](https://fastly/fastly-agent-toolkit-evals) repository

Compare representative tasks with and without the skill to confirm that its description selects it when useful, improves the result, and does not create regressions or confusion elsewhere.

Alongside obvious matches, test near misses and unrelated requests, especially when another skill covers a related area and could trigger unnecessarily or give conflicting advice.

Be sure to include small models because users should not have to pay for a large frontier model to get reliable help with a simple task.

Small models also keep evaluations affordable when they run for hours or days, while exposing vague instructions and hidden assumptions.

Although success with a small model does not guarantee identical behavior across all larger models, it is still a strong sign that the skill is clear, self-contained, and likely to behave consistently with frontier models.

Keep a short record of the tasks, models, and results so reviewers can understand the evidence.

## Run the repository checks

On macOS, install the local validation dependencies with:

```bash
brew install uv shellcheck jq
node --version >/dev/null 2>&1 || brew install node
```

Then run the complete checks after every edit:

```bash
make ci
```

This command checks the skill metadata, Markdown, JSON, YAML, shell scripts, plugin packaging, and every skill with `skillscheck` in strict mode.

## Open the pull request

Once the skill and its evaluation are ready, open a focused pull request explaining the problem, why a skill is needed, which skill and reference files were added, and what you tested.

Include the evaluation summary and mention that `make ci` passes locally.

A human reviewer will examine the skill and its description before merging it, so treat automated feedback as helpful input rather than as a replacement for human review.

## Stay involved

Finally, contributing a skill means taking responsibility for it after the pull request is merged, including understanding the subject well enough to fix problems and update the guidance when tools, APIs, or recommended workflows change.

Because outdated guidance can confidently send agents in the wrong direction, a skill is not a one-time contribution that can be forgotten after it is merged.
