#!/bin/sh
input=$(cat)

# Parse everything in one jq pass. Field names follow the Claude Code statusLine schema.
eval "$(echo "$input" | jq -r '
  def pct: if . != null then round | tostring else "" end;
  @sh "model=\(.model.display_name // "Claude")",
  @sh "cwd=\(.workspace.current_dir // .cwd // env.HOME)",
  @sh "five_hr=\(.rate_limits.five_hour.used_percentage | pct)",
  @sh "five_hr_resets=\(.rate_limits.five_hour.resets_at // "" | tostring)",
  @sh "weekly=\(.rate_limits.seven_day.used_percentage | pct)",
  @sh "weekly_resets=\(.rate_limits.seven_day.resets_at // "" | tostring)",
  @sh "ctx=\(.context_window.used_percentage | pct)",
  @sh "cost=\(if (.cost.total_cost_usd // 0) > 0 then (.cost.total_cost_usd * 100 | round / 100 | tostring) else "" end)",
  @sh "effort=\(.effort.level // "")",
  @sh "wt_name=\(.worktree.name // .workspace.git_worktree // "")",
  @sh "wt_branch=\(.worktree.branch // "")",
  @sh "fast=\(.fast_mode // false)",
  @sh "pr_num=\(.pr.number // "" | tostring)",
  @sh "pr_state=\(.pr.review_state // "")",
  @sh "pr_kind=\(.pr.kind // "")",
  @sh "cache_warm=\(if .prompt_cache.warm == null then "" else (.prompt_cache.warm | tostring) end)",
  @sh "cache_hit=\(if .prompt_cache.hit_ratio != null then .prompt_cache.hit_ratio * 100 | round | tostring else "" end)",
  @sh "cache_exp=\(.prompt_cache.expires_at // "" | tostring)",
  @sh "session_name=\(.session_name // "")",
  @sh "agent=\(.agent.name // "")",
  @sh "thinking=\(.thinking.enabled // false)",
  @sh "lines_add=\(.cost.total_lines_added // 0)",
  @sh "lines_del=\(.cost.total_lines_removed // 0)",
  @sh "dur_ms=\(.cost.total_duration_ms // 0 | floor)",
  @sh "wt_orig=\(.worktree.original_branch // "")",
  @sh "repo=\(if .workspace.repo.name then "\(.workspace.repo.owner)/\(.workspace.repo.name)" else "" end)"
')"

# GNU date uses -d @epoch, BSD/macOS uses -r epoch
fmt_epoch() {
  date -d "@$1" "$2" 2>/dev/null || date -r "$1" "$2" 2>/dev/null
}

reset_str=""
if [ -n "$five_hr_resets" ]; then
  now=$(date +%s)
  diff=$((five_hr_resets - now))
  if [ "$diff" -gt 0 ]; then
    hrs=$((diff / 3600))
    mins=$(( (diff % 3600) / 60 ))
    if [ "$hrs" -gt 0 ]; then
      reset_str="🔄 ~${hrs}h ${mins}m"
    else
      reset_str="🔄 ~${mins}m"
    fi
  fi
fi

# Branch: live from git; the harness also reports the Claude worktree's branch,
# shown alongside when it differs. Dirty/ahead/behind/stash only come from git.
branch=""
dirty=""
ahead=0
behind=0
stashes=0
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    dirty=" ●"
  fi
  counts=$(git -C "$cwd" --no-optional-locks rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null)
  if [ -n "$counts" ]; then
    ahead=${counts%%[[:space:]]*}
    behind=${counts##*[[:space:]]}
  fi
  # Uncommitted changes (staged + unstaged) against HEAD
  shortstat=$(git -C "$cwd" --no-optional-locks diff HEAD --shortstat 2>/dev/null)
  git_add=$(echo "$shortstat" | sed -n 's/.* \([0-9]*\) insertion.*/\1/p')
  git_del=$(echo "$shortstat" | sed -n 's/.* \([0-9]*\) deletion.*/\1/p')
  stashes=$(git -C "$cwd" --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')
fi
[ -z "$branch" ] && branch="$wt_branch"

green=$(printf '\033[32m')
yellow=$(printf '\033[33m')
red=$(printf '\033[31m')
cyan=$(printf '\033[36m')
dim=$(printf '\033[2m')
rs=$(printf '\033[0m')

pct_color() {
  p=$1
  if [ "$p" -ge 75 ] 2>/dev/null; then printf "%s" "$red"
  elif [ "$p" -ge 50 ] 2>/dev/null; then printf "%s" "$yellow"
  else printf "%s" "$green"
  fi
}

make_bar() {
  pct=$1; width=${2:-10}
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  filled=$(( pct * width / 100 ))
  [ "$pct" -gt 0 ] 2>/dev/null && [ "$filled" -eq 0 ] && filled=1
  bar=""; i=0
  while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i+1)); done
  while [ $i -lt $width ];  do bar="${bar}░"; i=$((i+1)); done
  printf "%s" "$bar"
}

sep="${dim} · ${rs}"

case "$effort" in
  max)    effort_badge="🔥🔥 max" ;;
  xhigh)  effort_badge="🔥 xhigh" ;;
  high)   effort_badge="🔥 high" ;;
  medium) effort_badge="◐ medium" ;;
  low)    effort_badge="🐢 low" ;;
  *)      effort_badge="" ;;
esac

g1="${cyan}✨ ${model}${rs}"
[ -n "$effort_badge" ] && g1="${g1} ${dim}${effort_badge}${rs}"
[ "$fast" = "true" ] && g1="${g1} ${yellow}⚡ fast${rs}"
[ "$thinking" = "true" ] && g1="${g1} 💭"
[ -n "$agent" ] && g1="${g1} ${cyan}🤖 ${agent}${rs}"
[ -n "$session_name" ] && g1="${g1} ${dim}「${session_name}」${rs}"

gu=""
if [ -n "$five_hr" ]; then
  c=$(pct_color "$five_hr"); bar=$(make_bar "$five_hr")
  fp="🔋 ${c}${bar}${rs} ${five_hr}%"
  [ -n "$reset_str" ] && fp="${fp} ${dim}${reset_str}${rs}"
  if [ -n "$five_hr_resets" ]; then
    reset_at=$(fmt_epoch "$five_hr_resets" +%H:%M)
    [ -n "$reset_at" ] && fp="${fp} ${dim}🕐 ${reset_at}${rs}"
  fi
  gu="$fp"
fi

if [ -n "$weekly" ]; then
  c=$(pct_color "$weekly"); bar=$(make_bar "$weekly")
  wp="📅 ${c}${bar}${rs} ${weekly}%"
  if [ -n "$weekly_resets" ]; then
    now=$(date +%s)
    diff=$((weekly_resets - now))
    if [ "$diff" -gt 0 ]; then
      days=$((diff / 86400))
      hrs=$(( (diff % 86400) / 3600 ))
      if [ "$days" -gt 0 ]; then
        wp="${wp} ${dim}🔄 ~${days}d ${hrs}h${rs}"
      else
        mins=$(( (diff % 3600) / 60 ))
        if [ "$hrs" -gt 0 ]; then
          wp="${wp} ${dim}🔄 ~${hrs}h ${mins}m${rs}"
        else
          wp="${wp} ${dim}🔄 ~${mins}m${rs}"
        fi
      fi
    fi
    reset_at_w=$(fmt_epoch "$weekly_resets" "+%a %H:%M")
    [ -n "$reset_at_w" ] && wp="${wp} ${dim}🕐 ${reset_at_w}${rs}"
  fi
  if [ -n "$gu" ]; then gu="${gu}${sep}${wp}"; else gu="$wp"; fi
fi

# Second line: session stats
g3=""
add3() { if [ -n "$g3" ]; then g3="${g3}${sep}$1"; else g3="$1"; fi; }

[ -n "$cost" ] && add3 "${dim}💰 \$$(printf "%.2f" "$cost")${rs}"

dur_s=$((dur_ms / 1000))
if [ "$dur_s" -ge 60 ]; then
  if [ "$dur_s" -ge 3600 ]; then
    add3 "${dim}⏱ $((dur_s / 3600))h$(( (dur_s % 3600) / 60 ))m${rs}"
  else
    add3 "${dim}⏱ $((dur_s / 60))m${rs}"
  fi
fi

if [ -n "$ctx" ]; then
  c=$(pct_color "$ctx"); bar=$(make_bar "$ctx")
  add3 "🧠 ${c}${bar}${rs} ${ctx}%"
fi

g2=""
if [ -n "$branch" ]; then
  bp="${red}${dirty}${rs}"
  [ "$ahead" -gt 0 ] 2>/dev/null  && bp="${bp} ${green}⬆ ${ahead}${rs}"
  [ "$behind" -gt 0 ] 2>/dev/null && bp="${bp} ${yellow}⬇ ${behind}${rs}"
  if [ -n "$git_add" ] || [ -n "$git_del" ]; then
    bp="${bp} ${dim}Δ${rs} ${green}+${git_add:-0}${rs} ${red}−${git_del:-0}${rs}"
  fi
  g2="🌿 ${branch}${bp}"
  [ -n "$repo" ] && g2="${dim}📁 ${repo}${rs}${sep}${g2}"
  if [ -n "$wt_name" ]; then
    wt="🌳 ${wt_name}"
    [ -n "$wt_branch" ] && [ "$wt_branch" != "$branch" ] && wt="${wt} (${wt_branch})"
    [ -n "$wt_orig" ] && wt="${wt} from ${wt_orig}"
    g2="${g2} ${dim}${wt}${rs}"
  fi
  [ "$stashes" -gt 0 ] 2>/dev/null && g2="${g2}${sep}📦 ${stashes}"
fi

if [ -n "$pr_num" ]; then
  [ "$pr_kind" = "mr" ] && pr_ref="!${pr_num}" || pr_ref="#${pr_num}"
  case "$pr_state" in
    approved)          pr_part="${green}🔀 ${pr_ref} ✓${rs}" ;;
    changes_requested) pr_part="${red}🔀 ${pr_ref} ✗${rs}" ;;
    pending)           pr_part="${yellow}🔀 ${pr_ref} …${rs}" ;;
    draft)             pr_part="${dim}🔀 ${pr_ref} draft${rs}" ;;
    *)                 pr_part="🔀 ${pr_ref}" ;;
  esac
  if [ -n "$g2" ]; then g2="${g2}${sep}${pr_part}"; else g2="$pr_part"; fi
fi

# Lines changed by Claude this session (git's uncommitted diff is shown by the branch)
if [ "$lines_add" -gt 0 ] || [ "$lines_del" -gt 0 ]; then
  diff_part="✏️ ${dim}claude${rs} ${green}+${lines_add}${rs} ${red}−${lines_del}${rs}"
  if [ -n "$g2" ]; then g2="${g2}${sep}${diff_part}"; else g2="$diff_part"; fi
fi

if [ -n "$cache_warm" ]; then
  if [ "$cache_warm" = "true" ]; then
    cp="${green}💾 warm${rs}"
    if [ -n "$cache_exp" ]; then
      left=$((cache_exp - $(date +%s)))
      [ "$left" -gt 0 ] && cp="${cp} ${dim}⏳ $((left / 60))m$((left % 60))s${rs}"
    fi
  else
    cp="${dim}💾 cold${rs}"
  fi
  [ -n "$cache_hit" ] && cp="${cp} ${dim}${cache_hit}% hit${rs}"
  add3 "$cp"
fi

# Model, usage, session stats and git each get their own line, with a blank line between.
# Claude Code drops truly empty lines, so the spacer holds an invisible U+2800 (braille blank).
spacer="⠀"
for l in "$g1" "$gu" "$g3" "$g2"; do
  [ -n "$l" ] && printf "%s\n%s\n" "$l" "$spacer"
done
printf '\033[1;32mFollow the white rabbit. ▌\033[0m\n'
printf "%s\n" "$spacer"
