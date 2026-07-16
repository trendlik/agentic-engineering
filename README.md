# agentic-engineering

Provider-agnostic, version-controlled agent skills and configuration.

## Skills

Custom skills live under [`skills/`](skills/). Each is made available globally by
symlinking it into the agent's skills directory (Claude Code or Gemini). The
symlink keeps the skill available across all projects while the real files stay
versioned here.

### Installed skills

- `implement-issue` — runs an issue from ticket to merged PR: agents do the work,
  humans approve at the key gates. Phases: clarify → plan → implement → test →
  review → PR → CI-fix loop → retrospective.
  Full setup, start to finish (install the skill, then onboard a project), lives in
  [`ONBOARDING.md`](skills/implement-issue/ONBOARDING.md).

  The flow is driven by **GitHub Issues** (via the `gh` CLI) — the only supported
  tracker today. It can be adapted to other systems (Jira, Linear, GitLab), but
  that means editing the skill's scripts and phases; it won't work with a non-GitHub
  tracker out of the box.

## Requirements

The skills rely on a Unix-style shell and toolchain (`bash`, `git`, `gh`, `jq`), so
they run natively on **macOS and Linux**. The `*.sh` scripts won't execute under
native Windows `cmd`/PowerShell; on **Windows** you'd need **WSL** or **Git Bash**
(and symlinking skills into place also expects a POSIX environment). Note this
hasn't been tested on Windows — WSL/Git Bash is the expected path, not a verified one.
