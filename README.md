# Fastly Agent Toolkit

A collection of skills for AI coding agents to work with the Fastly platform and edge computing tools.

- [Fastly Agent Toolkit](#fastly-agent-toolkit)
  - [Agent Plugins](#agent-plugins)
  - [Available skills](#available-skills)
  - [Runtime requirements](#runtime-requirements)
  - [Support and privacy](#support-and-privacy)
  - [Usage](#usage)
    - [Manual copy](#manual-copy)
    - [Claude Code](#claude-code)
    - [Codex](#codex)
    - [Swival](#swival)
    - [Qwen Code](#qwen-code)
    - [Gemini CLI](#gemini-cli)
    - [Using the `skills` CLI](#using-the-skills-cli)
  - [Skill format](#skill-format)
  - [Contributing new skills](#contributing-new-skills)

## Agent Plugins

This repository is a portable [Agent Plugin](https://agent-plugins.org/specification).
Clients load the root [`plugin.json`](plugin.json) manifest and discover the skills in `skills/`.

## Available skills

- `fastly`: Working with the Fastly platform, including services, caching, VCL, WAF, TLS, DDoS protection, purging, and API usage.
- `fastly-cli`: Using the [Fastly CLI](https://www.fastly.com/documentation/reference/cli/) to manage services, compute apps, logging, WAF, TLS, key-value stores, and stats.
- `fastly-fiddle`: Testing VCL against real Fastly edge infrastructure with [Fastly Fiddle](https://fiddle.fastly.dev/), covering assertion-based tests, the Fiddle HTTP API, shareable bug reproductions, and CI integration.
- `fastly-stats`: Fastly traffic numbers via the CLI or raw HTTP, covering the Historical Stats, Real-Time analytics, and Origin/Domain Inspector APIs, and owning the unit, window, and aggregation conventions that decide whether a reported figure is right.
- `fastly-ngwaf`: Auditing Next-Gen WAF workspaces for missing or disabled protection rules and checking whether attack traffic is being blocked.
- `fastly-reference-architectures`: Curated GitHub repositories demonstrating working reference architectures on Fastly, from single Compute applications to systems combining multiple Fastly products.
- `falco`: VCL development with [Falco](https://github.com/ysugimoto/falco), covering linting, testing, simulation, formatting, REPL, and Terraform integration.
- `fastlike`: Running Fastly Compute locally with [Fastlike](https://github.com/avidal/fastlike), covering backend configuration, builds, and testing.
- `viceroy`: Running Fastly Compute locally with [Viceroy](https://github.com/fastly/Viceroy), covering serving, configuration, testing, and SDK adaptation.
- `xvcl`: The [XVCL](https://dip-proto.github.io/xvcl/) VCL transpiler, covering syntax extensions, subroutines, header manipulation, and caching logic.

Each skill lives under `skills/` with a `SKILL.md` entrypoint and a `references/` directory containing detailed topic files.

**Important:** SKILL.md files reference companion files in their `references/` directory. Make sure your agent is allowed to read from these directories, otherwise it won't be able to follow the references and will miss important context.

## Runtime requirements

These skills are intended for coding environments that can read project files and run commands.
Install the tools for the workflows you use; installing the plugin does not install its developer tools or connect a Fastly account.

<details>
<summary>Workflow-specific requirements</summary>

| Workflow                                  | Requirements                                                                               |
| ----------------------------------------- | ------------------------------------------------------------------------------------------ |
| Fastly CLI and traffic statistics         | Fastly CLI and locally configured authentication; `curl` and `jq` for raw API examples     |
| NGWAF assessment script                   | Bash, `curl`, `jq`, and a locally configured `FASTLY_API_KEY` with access to the workspace |
| VCL linting, unit tests, and simulation   | Falco; installation requires Homebrew or Go                                                |
| XVCL compilation                          | uv with `uvx` and access to the XVCL package; Falco for the local checks                   |
| Local Compute development                 | Fastlike or Viceroy, plus the build tools and WASM targets required by the application     |
| Fastly Fiddle tests                       | Bash, `curl` 7.76 or newer, `jq`, and network access to Fastly Fiddle                      |
| Documentation and reference architectures | A browser or HTTP client; Git when cloning examples or tool sources                        |

Each skill describes its prerequisites and installation options.
Package installation and source builds may need network access.
Bundled scripts and examples are resolved from the installed skill directory, while your project files stay relative to your project's working directory.

</details>

Set up Fastly authentication yourself using the CLI's interactive login or local configuration.
Do not paste API keys into a conversation, include them in project files, or share command output that reveals them.
Choose credentials with only the permissions needed for the task.

## Support and privacy

For questions about these skills or to report a bug, open an issue in the [GitHub issue tracker](https://github.com/fastly/fastly-agent-toolkit/issues).
Report security issues privately through the process in [SECURITY.md](SECURITY.md).

Read [Privacy and data handling](PRIVACY.md) for details about local credentials, account data, and public Fiddle uploads.
Fastly's [privacy policy](https://www.fastly.com/privacy) and [terms of service](https://www.fastly.com/terms) describe the applicable Fastly policies and service terms.
The skills are available under the [MIT license](LICENSE).

## Usage

Pick the skills relevant to your project. You probably don't need all of them.

### Manual copy

If your agent supports the `.agents/skills/` convention, this is the most portable option. Agents that use this location include Amp, Cline, Codex, Cursor, Gemini CLI, GitHub Copilot, Kimi Code, OpenCode, Replit Agent, Swival, and Warp.

Install into the current project:

```bash
mkdir -p .agents/skills
cp -R ./skills/{falco,viceroy} .agents/skills/
```

Install globally (for agents that support `~/.agents/skills/`):

```bash
mkdir -p ~/.agents/skills
cp -R ./skills/{falco,viceroy} ~/.agents/skills/
```

If your agent doesn't support `.agents/skills/`, expand the agent-specific instructions below.

Agent-specific installation

### [Claude Code](https://code.claude.com/docs/en/overview)

Install the bundled skills as a plugin:

```bash
claude plugin install fastly-agent-toolkit@claude-plugins-official
claude plugin list
```

### [Codex](https://github.com/openai/codex)

Install the bundled skills as a plugin:

```bash
codex plugin marketplace add https://github.com/fastly/fastly-agent-toolkit.git
codex plugin add fastly-agent-toolkit@fastly-agent-toolkit
```

### [Swival](https://swival.dev/)

Stage the collection in your library first, then add the skills you want:

```bash
swival skills add --global https://github.com/fastly/fastly-agent-toolkit  # stage into ~/.config/swival/library
swival skills add fastly-agent-toolkit                                     # install the collection into this project
swival skills add --global fastly-agent-toolkit                            # or activate it in every project
```

Prefer only a couple of skills? Activate them by name instead of the whole collection: `swival skills add falco`, `swival skills add viceroy`.

### [Qwen Code](https://qwenlm.github.io/qwen-code-docs/en/users/overview/)

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

### [Gemini CLI](https://geminicli.com/)

Gemini CLI supports `.agents/skills/` as shown above. You can also link the whole repository using Gemini's extension workflow:

```bash
gemini extensions link .
```

Swap `{falco,viceroy}` for whatever combination you need. For VCL work, `falco` and `xvcl` are the most useful. For Fastly Compute, grab `fastly-cli` and either `viceroy` or `fastlike`.

### Using the `skills` CLI

The [`skills`](https://github.com/vercel-labs/skills) CLI installs skills into the standard `.agents/skills/` directory and automatically symlinks them into agent-specific directories. It supports most agents out of the box.

Install into the current project:

```bash
bunx skills add github:fastly/fastly-agent-toolkit --skill falco --skill viceroy
# or with node:
npx skills add github:fastly/fastly-agent-toolkit --skill falco --skill viceroy
```

Install globally (available across all projects via `~/.agents/skills/`):

```bash
bunx skills add -g github:fastly/fastly-agent-toolkit --skill falco --skill viceroy
```

## Skill format

Each skill lives in its own directory as a `SKILL.md` file with YAML frontmatter following the [Agent Skills spec](https://agentskills.io/specification).
The skills are validated with [`skillscheck`](https://github.com/Swival/skillscheck).

## Contributing new skills

See [CONTRIBUTING.md](CONTRIBUTING.md).
