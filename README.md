# agentic-engineering

Provider-agnostic, version-controlled agent skills and configuration.

## Skills

Custom skills live under [`skills/`](skills/). Each is made available globally by
symlinking it into the agent's skills directory (Claude Code or Gemini). The
symlink keeps the skill available across all projects while the real files stay
versioned here.

### Installed skills

- `implement-issue` — structured clarify → plan → implement → test → review → PR → CI loop.
  Full setup, start to finish (install the skill, then onboard a project), lives in
  [`ONBOARDING.md`](skills/implement-issue/ONBOARDING.md).
