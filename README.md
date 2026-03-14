# Fastly Agent Toolkit

A collection of skills for AI coding agents to work with the Fastly platform and edge computing tools.

## Available skills

- `fastly`: Working with the Fastly platform: services, caching, VCL, WAF, TLS, DDoS protection, purging, and API usage.
- `fastly-cli`: Using the Fastly CLI for managing services, compute apps, logging, WAF, TLS, key-value stores, and stats.
- `falco`: VCL development with Falco: linting, testing, simulation, formatting, REPL, and Terraform integration.
- `fastlike`: Running Fastly Compute locally with Fastlike (Go-based): backend configuration, builds, and testing.
- `viceroy`: Running Fastly Compute locally with Viceroy (WASM-based): serving, configuration, testing, and SDK adaptation.
- `xvcl`: The XVCL VCL transpiler: syntax extensions, subroutines, header manipulation, and caching logic.

Each skill lives under `skills/` with a `SKILL.md` entrypoint and a `references/` directory containing detailed topic files.

**Important:** SKILL.md files reference companion files in their `references/` directory. Make sure your agent is allowed to read from these directories, otherwise it won't be able to follow the references and will miss important context.

## Usage

Copy the skills you need into your agent's skills directory. You probably don't need all of them. Pick what's relevant to your project.

### Claude Code

#### Plugin Marketplace

```bash
claude plugin marketplace add git@github.com:fastly/fastly-agent-toolkit.git
claude plugin list

# If this fails, add skills manually in the next section.
```

#### Manual

```bash
mkdir -p .claude/skills
cp -R ./skills/{falco,viceroy} .claude/skills/
```

For immediate, reliable setup in local environments, prefer the manual copy above first (it does not depend on the marketplace installation step).

### Codex

```bash
mkdir -p ~/.codex/skills
cp -R ./skills/{falco,viceroy} ~/.codex/skills/
```

### Qwen Code

Qwen Code requires the experimental skills feature. Enable it by adding to `.qwen/settings.json`:

```json
{
  "tools": {
    "experimental": {
      "skills": true
    }
  }
}
```

Then copy skills to the project directory:

```bash
mkdir -p .qwen/skills
cp -R ./skills/{falco,viceroy} .qwen/skills/
```

### Gemini CLI

```bash
gemini extensions link .
```

Swap `{falco,viceroy}` for whatever combination you need. For VCL work, `falco` and `xvcl` are the most useful. For Fastly Compute, grab `fastly-cli` and either `viceroy` or `fastlike`.

## Skill format

Each skill lives in its own directory as a `SKILL.md` file with YAML frontmatter following the [Agent Skills spec](https://agentskills.io/specification).
