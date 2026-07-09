# agentic-engineering

Provider-agnostic, version-controlled agent skills and configuration.

## Skills

Custom skills live under [`skills/`](skills/). They are made available globally
by symlinking each one into the agent's skills directory.

### For Claude Code:

```bash
ln -s ~/Documents/GitHub/agentic-engineering/skills/<skill-name> ~/.claude/skills/<skill-name>
```

### For Google Antigravity (Gemini):

```bash
mkdir -p ~/.gemini/config/skills
ln -s ~/Documents/GitHub/agentic-engineering/skills/<skill-name> ~/.gemini/config/skills/<skill-name>
```

The symlink keeps the skill available across all projects while the real files
stay versioned here.

### Installed skills

- `implement-issue` — structured clarify → plan → implement → test → review → PR → CI loop.

## Setup on a new machine

Choose your platform or configure both:

**For Claude Code:**
```bash
git clone <remote-url> ~/Documents/GitHub/agentic-engineering
for s in ~/Documents/GitHub/agentic-engineering/skills/*/; do
  ln -s "$s" ~/.claude/skills/"$(basename "$s")"
done
```

**For Google Antigravity (Gemini):**
```bash
git clone <remote-url> ~/Documents/GitHub/agentic-engineering
mkdir -p ~/.gemini/config/skills
for s in ~/Documents/GitHub/agentic-engineering/skills/*/; do
  ln -s "$s" ~/.gemini/config/skills/"$(basename "$s")"
done
```

Skills that ship a `scripts/doctor.sh` (e.g. `implement-issue`) let you verify the new
machine is ready in one command, e.g.:
```bash
~/.claude/skills/implement-issue/scripts/doctor.sh
```
It checks for git/gh/jq, gh authentication, and a GitHub-backed origin remote, and prints
exactly what's missing.
