# claude-statusline

Custom status line for [Claude Code](https://code.claude.com/docs/en/overview).

```
✨ Opus 5.5 🔥 high 💭 🤖 agent 「session」

🔋 █░░░░░░░░░ 13% 🔄 ~1h 23m 🕐 05:31 · 📅 ████░░░░░░ 40% 🔄 ~3d 11h 🕐 Sat 15:27

💰 $1.23 · ⏱ 1h13m · 🧠 ██████░░░░ 62% · 💾 warm ⏳ 4m7s 87% hit

📁 owner/repo · 🌿 feat/x ● Δ +12 −3 ⬆ 1 🌳 wt (feat/y) from main · 📦 2 · 🔀 #42 ✓ · ✏️ claude +120 −34

Follow the white rabbit. ▌
```

## Lines

1. **Model**: model, effort level, fast mode, thinking, agent, session name.
2. **Usage**: 5-hour and weekly rate-limit bars with reset countdowns.
3. **Session**: cost, duration, context window usage, prompt-cache state.
4. **Git**: repo, branch (live from git), dirty marker and uncommitted diff (`Δ`), ahead/behind, Claude worktree name (plus its branch when it differs from git's, and the branch it started from), stashes, PR review state, lines changed by Claude this session (`✏️ claude`).

Empty sections are hidden. Spacer lines use an invisible U+2800 character because Claude Code drops empty lines.

The dirty marker `●` ignores untracked files to keep `git status` fast in large repos.

## Install

Requires `jq` and `git`.

```sh
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then merge `settings.statusline.json` into `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.sh",
  "refreshInterval": 30
}
```
