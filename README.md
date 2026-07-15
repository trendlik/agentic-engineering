# agentic-engineering

Provider-agnostic, version-controlled agent skills and configuration.

## Skills

Custom skills live under [`skills/`](skills/). They are made available globally
by symlinking each one into the agent's skills directory. Run these from the repo
root — `$PWD` resolves the absolute path the symlink needs, wherever you cloned it.

### For Claude Code:

```bash
ln -s "$PWD/skills/<skill-name>" ~/.claude/skills/<skill-name>
```

### For Google Antigravity (Gemini):

```bash
mkdir -p ~/.gemini/config/skills
ln -s "$PWD/skills/<skill-name>" ~/.gemini/config/skills/<skill-name>
```

The symlink keeps the skill available across all projects while the real files
stay versioned here.

### Installed skills

- `implement-issue` — structured clarify → plan → implement → test → review → PR → CI loop.
  See [`ONBOARDING.md`](skills/implement-issue/ONBOARDING.md) for making a target
  repository compatible with the skill (hard requirements plus optional layers).

## Setup on a new machine

Clone anywhere, then `cd` into the repo so `$PWD` points at it. Choose your
platform or configure both:

**For Claude Code:**
```bash
git clone <remote-url> agentic-engineering
cd agentic-engineering
for s in skills/*/; do
  ln -s "$PWD/$s" ~/.claude/skills/"$(basename "$s")"
done
```

**For Google Antigravity (Gemini):**
```bash
git clone <remote-url> agentic-engineering
cd agentic-engineering
mkdir -p ~/.gemini/config/skills
for s in skills/*/; do
  ln -s "$PWD/$s" ~/.gemini/config/skills/"$(basename "$s")"
done
```

Skills that ship a `scripts/doctor.sh` (e.g. `implement-issue`) let you verify the new
machine is ready in one command, e.g.:
```bash
~/.claude/skills/implement-issue/scripts/doctor.sh
```
It checks for git/gh/jq, gh authentication, and a GitHub-backed origin remote, and prints
exactly what's missing.
