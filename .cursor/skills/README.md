# Agent skills

If upstream has no `.claude/skills` directory, that path is a symlink to
`.cursor/skills`. If upstream already ships skills, leave that tree in place.
Edit the fork skill under `.cursor/skills/` only.

Shared skill source: `rafaelgaspar/fork-pack` `dot-cursor/skills/`.

| Skill | When to use |
| --- | --- |
| [rafaelgaspar-fork](rafaelgaspar-fork/SKILL.md) | Fork workflow — feat branches, `rafaelgaspar` pointer, tag-bump |
