<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/brand/rankraft-mark-dark-bg.svg">
    <img src=".github/brand/rankraft-mark-light-bg.svg" alt="RankRaft AI" width="72" height="72">
  </picture>
</p>

<h1 align="center">RankRaft AI skill</h1>

<p align="center">An Agent Skill for coding agents working against the <a href="https://rankraft.ai">RankRaft AI</a> API and SDKs.</p>

<p align="center">
  <a href="https://rankraft.ai"><b>rankraft.ai</b></a> &nbsp;·&nbsp;
  <a href="https://docs.rankraft.ai">Docs</a> &nbsp;·&nbsp;
  <a href="https://app.rankraft.ai">Dashboard</a> &nbsp;·&nbsp;
  <a href="https://docs.rankraft.ai/api-reference/introduction">API reference</a>
</p>

It teaches the agent the parts a developer otherwise learns from a 422: that the
report endpoints are POSTs that read, that cursors are bound to the query, that
filter values are strings, which fields each report accepts, what every error
code means, and when to point someone at the MCP server instead of writing code.

**This repo is the skill itself** - `SKILL.md` at the root, plus `references/`
and `scripts/`. It is plain Markdown and one shell script, so any agent that
reads the Agent Skills format can use it. Nothing here is specific to one tool.

## Install

Copy the directory wherever your agent looks for skills:

```bash
git clone https://github.com/RankRaft/rankraft-skill
```

| Agent | Where it goes |
|---|---|
| Claude Code (per project) | `.claude/skills/rankraft/` |
| Claude Code (every project) | `~/.claude/skills/rankraft/` |
| Codex | `.codex/skills/rankraft/` |
| Cursor, Windsurf, others | the directory they read `SKILL.md` from; or paste `SKILL.md` into project rules |

```bash
cp -r rankraft-skill .claude/skills/rankraft     # for example
```

Claude Code users who prefer a managed install can use the plugin instead:
[RankRaft/rankraft-claude-plugin](https://github.com/RankRaft/rankraft-claude-plugin).
It vendors this exact directory and updates when this repo does.

## What is in it

| File | Read it when |
|---|---|
| `SKILL.md` | starting any RankRaft AI task: REST vs MCP, SDK quick starts, the ten rules that bite |
| `references/api-reference.md` | you need exact request/response shapes, filter fields per endpoint, limits |
| `references/errors.md` | handling or explaining an error code |
| `references/recipes.md` | visibility over time, leaderboards, citation share, CSV prompt loads, warehouse exports, 92-day backfills |
| `references/why-the-sdks.md` | deciding whether to call the API by hand |
| `scripts/smoke.sh` | checking a key, its permission and the site ids in one command |

## Keeping it true

The source of truth is `https://api.rankraft.ai/v1/openapi.json`. When the API
changes, the two SDK repos get a pull request from their daily spec-sync
workflow; this repo should follow. Anything here that disagrees with the spec
is a bug - open an issue.

## Licence

MIT

---

RankRaft AI - [rankraft.ai](https://rankraft.ai) · [docs.rankraft.ai](https://docs.rankraft.ai) · hello@rankraft.ai
