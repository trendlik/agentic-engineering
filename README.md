# agentic-engineering

Provider-agnostic, version-controlled agent skills and configuration.

## Skills

Custom skills live under [`skills/`](skills/). They are made available globally
by symlinking each one into the agent's skills directory. For Claude Code:

```bash
ln -s ~/agentic-engineering/skills/<skill-name> ~/.claude/skills/<skill-name>
```

The symlink keeps the skill available across all projects while the real files
stay versioned here.

### Installed skills

- `implement-issue` — structured clarify → plan → implement → test → review → PR → CI loop.

## Setup on a new machine

```bash
git clone <remote-url> ~/agentic-engineering
for s in ~/agentic-engineering/skills/*/; do
  ln -s "$s" ~/.claude/skills/"$(basename "$s")"
done
```
