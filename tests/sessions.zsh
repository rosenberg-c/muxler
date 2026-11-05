#!/usr/bin/env zsh
set -eu

source "${0:A:h:h}/.zsh_session"
source "${0:A:h:h}/.zsh_tmux"
source "${0:A:h}/config.zsh"
fixture_dir=$(mktemp -d)
host_config=$fixture_dir/ssh_config
trap 'rm -f -- "$host_config"; rmdir -- "$fixture_dir"' EXIT
print 'Host debian-dev debian-new' > "$host_config"
WORKSPACE_REMOTE_HOSTS_CONFIG=$host_config

fail() { print -u2 -- "$1"; exit 1; }
[[ $WORKSPACE_ROOT == "${0:A:h:h}" ]] || fail 'workspace root follows sourced files'

# User aliases are optional and take precedence over built-in aliases.
(
  fixture=$(mktemp -d)
  trap 'rm -f -- "$fixture/user.sessions.local.sh" "$fixture/user.sessions.remote.sh"; rmdir -- "$fixture"' EXIT
  WORKSPACE_ROOT=$fixture
  source "${0:A:h:h}/sessions.local.sh"
  source "${0:A:h:h}/sessions.remote.sh"
  (( $+functions[local-red] && $+functions[remote-cyan] )) || fail 'missing optional user aliases broke built-ins'
  print 'local-red() { user_local_loaded=yes; }' > "$fixture/user.sessions.local.sh"
  print 'remote-cyan() { user_remote_loaded=yes; }' > "$fixture/user.sessions.remote.sh"
  source "${0:A:h:h}/sessions.local.sh"
  source "${0:A:h:h}/sessions.remote.sh"
  local-red
  remote-cyan
  [[ $user_local_loaded == yes && $user_remote_loaded == yes ]] || fail 'user aliases did not override built-ins'
)

# Test built-in shortcuts without loading the user's optional aliases.
real_root=$WORKSPACE_ROOT
WORKSPACE_ROOT=$fixture_dir
source "$real_root/sessions.local.sh"
source "$real_root/sessions.remote.sh"
WORKSPACE_ROOT=$real_root

# Capture the commands destined for iTerm without opening tabs or starting tmux.
tmux_iterm_new_tabs() { tab_color=$1; shift; tab_commands=("$@"); }
tmux_local() { local_args=("$@"); }

local-red >/dev/null
[[ $tab_color == muted_red && ${#tab_commands} == 8 ]] || fail 'local-red tab setup'
[[ $tab_commands[1] == *'lazygit'* && $tab_commands[2] == *'opencode'* ]] || fail 'local-red tab names'
[[ $tab_commands[8] == *'tab9'* && $local_args[3] == nvim ]] || fail 'local-red main session'
[[ $local_args[1] == "$PWD" && $local_args[2] == "$(tmux_local_project_name local-red "$PWD")" && $local_args[5] == local-red ]] || fail 'local-red directory'
[[ $local_args[2] == workspace_local-red_* ]] || fail 'local session namespace'

tmux_local_directory local-blue muted_blue . 3 >/dev/null
[[ ${#tab_commands} == 2 && $tab_commands[2] == *'opencode'* && $local_args[3] == nvim ]] || fail 'local alias three-tab limit'
tmux_local_directory local-blue muted_blue . 4 >/dev/null
[[ ${#tab_commands} == 3 && $tab_commands[3] == *'tab4'* && $local_args[3] == nvim ]] || fail 'local alias first four tabs'
tmux_local_directory local-blue muted_blue . 1 >/dev/null
[[ ${#tab_commands} == 0 && $local_args[3] == nvim ]] || fail 'local alias one-tab limit'
for invalid in 0 10 abc; do
  if tmux_local_directory local-blue muted_blue . "$invalid" >/dev/null 2>&1; then fail "invalid local tab limit accepted: $invalid"; fi
done

for shortcut in local-blue local-yellow local-purple; do
  local_color=${shortcut#local-}
  "${shortcut}" >/dev/null
  [[ $tab_color == "muted_${local_color}" && $local_args[1] == "$PWD" && $local_args[3] == nvim ]] || fail "$shortcut tabs"
  [[ $local_args[4] == "bg=$(tmux_status_bg_color "muted_${local_color}"),fg=white" ]] || fail "$shortcut status color"
  [[ $local_args[2] == "$(tmux_local_project_name "$shortcut" "$PWD")" && $local_args[5] == "$shortcut" ]] || fail "$shortcut namespace"
  [[ $local_args[2] != "$(tmux_local_project_name local-red "$PWD")" ]] || fail 'local shortcut collision'
done

for shortcut in local-red local-blue local-yellow local-purple; do
  "$shortcut" tests >/dev/null
  [[ $local_args[1] == "${0:A:h}" && $local_args[2] == "$(tmux_local_project_name "$shortcut" "${0:A:h}")" && $local_args[5] == "$shortcut" ]] || fail "$shortcut relative directory"
done
local-blue ./tests/../tests >/dev/null
[[ $local_args[1] == "${0:A:h}" ]] || fail 'local directory normalization'
if local-blue missing-workspace-directory >/dev/null 2>&1; then fail 'missing local directory accepted'; fi

for color in red green blue yellow orange purple pink cyan magenta gray \
  muted_red muted_purple muted_blue muted_green muted_yellow muted_orange \
  muted_pink muted_cyan muted_magenta muted_gray; do
  (( $+functions[iterm_$color] )) || fail "missing iTerm color: $color"
done
[[ $(tmux_status_bg_color muted_blue) == '#354f75' ]] || fail 'alternate tmux color mapping'
tmux_local_tabs "$PWD" alternate muted_blue '#354f75' white >/dev/null
[[ $tab_color == muted_blue && $local_args[2] == alternate ]] || fail 'alternate local session color'

tmux_prepare_remote() { remote_args=("$@"); }
tmux_connect() { connect_args=("$@"); }

[[ $(tmux_remote_hosts) == *debian-dev* ]] || fail 'default remote host discovery'

remote-magenta . >/dev/null
[[ $remote_args[1] == debian-dev && $remote_args[2] == '$HOME' ]] || fail 'remote-magenta root path'
[[ $remote_args[3] == "bg=$(tmux_status_bg_color muted_magenta),fg=white" && $tab_color == muted_magenta ]] || fail 'remote-magenta colors'
[[ $remote_args[4] == remote-magenta && $remote_args[5] == 'magenta_%2E_nvim' && $connect_args[2] == 'magenta_%2E_nvim' ]] || fail 'remote-magenta root connection'

tmux_remote_directory . debian-dev '$HOME' muted_magenta remote-magenta magenta_ 3 >/dev/null
[[ ${#remote_args} == 7 && $remote_args[7] == 'magenta_%2E_opencode' && ${#tab_commands} == 2 ]] || fail 'remote alias three-tab limit'
tmux_remote_directory . debian-dev '$HOME' muted_magenta remote-magenta magenta_ 4 >/dev/null
[[ ${#remote_args} == 8 && $remote_args[8] == 'magenta_%2E_tab4' && ${#tab_commands} == 3 ]] || fail 'remote alias first four tabs'
tab_commands=(sentinel)
tmux_remote_directory sample debian-dev '$HOME' muted_magenta remote-magenta magenta_ 1 >/dev/null
[[ ${#remote_args} == 5 && $tab_commands[1] == sentinel && $connect_args[2] == magenta_sample_nvim ]] || fail 'remote alias one-tab limit'
for invalid in 0 10 abc; do
  if tmux_remote_directory sample debian-dev '$HOME' muted_magenta remote-magenta magenta_ "$invalid" >/dev/null 2>&1; then fail "invalid remote tab limit accepted: $invalid"; fi
done

remote-magenta sample >/dev/null
[[ $remote_args[2] == '$HOME/sample' && $remote_args[5] == magenta_sample_nvim ]] || fail 'remote-magenta project path'

remote-green sample >/dev/null
[[ $remote_args[1] == debian-dev && $remote_args[2] == '$HOME/sample' ]] || fail 'remote-green project path'
[[ $remote_args[3] == "bg=$(tmux_status_bg_color muted_green),fg=white" && $tab_color == muted_green ]] || fail 'remote-green colors'
[[ $remote_args[4] == remote-green && $remote_args[5] == green_sample_nvim && $connect_args[2] == green_sample_nvim ]] || fail 'remote-green shared magenta session'

remote-green . >/dev/null
[[ $remote_args[5] == 'green_%2E_nvim' ]] || fail 'remote-green root session'
remote-magenta main >/dev/null
[[ $remote_args[5] == magenta_main_nvim ]] || fail 'remote-magenta root collides with main directory'

remote-magenta path/to/other >/dev/null
[[ $remote_args[2] == '$HOME/path/to/other' && $remote_args[5] == 'magenta_path%2Fto%2Fother_nvim' ]] || fail 'remote-magenta nested path'
[[ $connect_args[2] == 'magenta_path%2Fto%2Fother_nvim' ]] || fail 'remote-magenta nested connection'

remote-magenta another/other >/dev/null
[[ $remote_args[5] == 'magenta_another%2Fother_nvim' ]] || fail 'nested paths with matching leaf names collide'
remote-magenta 'path%2Fto%2Fother' >/dev/null
[[ $remote_args[5] == 'magenta_path%252Fto%252Fother_nvim' ]] || fail 'escaped nested name collides with literal name'

for shortcut in remote-orange remote-cyan; do
  "$shortcut" sample >/dev/null
  [[ $remote_args[5] == "${shortcut#remote-}_sample_nvim" ]] || fail "$shortcut session name"
done

cat > "$host_config" <<EOF
Host $WORKSPACE_TEST_OTHER_HOST $WORKSPACE_TEST_HOST
Host $WORKSPACE_TEST_HOST *.example !excluded
HostName ignored.example
EOF
expected_hosts=("$WORKSPACE_TEST_HOST" "$WORKSPACE_TEST_OTHER_HOST")
[[ $(tmux_remote_hosts) == ${(F)${(o)expected_hosts}} ]] || fail 'remote host discovery and deduplication'

tmux_remote_directory sample "$WORKSPACE_TEST_OTHER_HOST" '$HOME/work' muted_blue example_remote >/dev/null
[[ $remote_args[1] == $WORKSPACE_TEST_OTHER_HOST && $remote_args[2] == '$HOME/work/sample' ]] || fail 'custom remote target'

tmux_remote_project "$WORKSPACE_TEST_HOST" '$HOME/work/sample' sample muted_blue >/dev/null
[[ $remote_args[3] == 'bg=#354f75,fg=white' && $connect_args[2] == sample_nvim ]] || fail 'alternate remote session color'

if remote-magenta ../bad >/dev/null 2>&1; then fail 'remote-magenta accepted an invalid path'; fi
for invalid in /absolute parent/../other parent/./other ./child parent//other parent/; do
  if remote-magenta "$invalid" >/dev/null 2>&1; then fail "remote-magenta accepted: $invalid"; fi
done

# The tab list controls names; helpers can select its first N entries.
original_tabs=("${WORKSPACE_TABS[@]}")
WORKSPACE_TABS=(nvim notes)
tmux_local_directory local-blue muted_blue . 2 >/dev/null
[[ ${#tab_commands} == 1 && $tab_commands[1] == *'notes'* && $local_args[3] == nvim ]] || fail 'custom local windows'
tmux_remote_directory sample debian-dev '$HOME' muted_cyan remote-cyan cyan_ 2 >/dev/null
[[ ${#tab_commands} == 1 && ${#remote_args} == 6 && $remote_args[5] == cyan_sample_nvim && $remote_args[6] == cyan_sample_notes ]] || fail 'custom remote windows'
[[ $connect_args[2] == cyan_sample_nvim ]] || fail 'custom remote main window'
if local-blue >/dev/null 2>&1; then fail 'local alias tabcount exceeds shortened tab list'; fi
if remote-cyan sample >/dev/null 2>&1; then fail 'remote alias tabcount exceeds shortened tab list'; fi
WORKSPACE_TABS=("${original_tabs[@]}")

# Verify the remote hook is streamed to SSH, without contacting a host.
source "${0:A:h:h}/.zsh_tmux"
ssh() { ssh_args=("$@"); ssh_script=$(cat); }
tmux_prepare_remote "$WORKSPACE_TEST_HOST" '$HOME/work/sample' 'bg=#5f3030,fg=white' remote-magenta sample_nvim
[[ $ssh_args[1] == $WORKSPACE_TEST_HOST && $ssh_script == *'tmux_session_install'* ]] || fail 'remote hook transfer'
[[ $ssh_script == *'tmux_session_prepare "$target_dir" "$session_name"'* && $ssh_script == *'@workspace_remote_group'* ]] || fail 'remote session preparation'
[[ $ssh_args[2] == *'remote-magenta'* && $ssh_args[2] == *'sample_nvim'* ]] || fail 'remote group transfer'

print 'session command tests passed'
