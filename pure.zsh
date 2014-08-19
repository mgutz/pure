# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# vcs_info:
# %a => current action (rebase/merge)
# %b => current branch
# %s => current source cli (git, hg...)
# prompt:
# %F => color dict
# $fg[color] => foreground color
# $fg_bold[color] => bold color
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)

prompt_pure_ok_color="$fg_bold[green]"
prompt_pure_error_color="$fg_bold[red]"
prompt_pure_dir_color="$fg_bold[cyan]"
#prompt_pure_prompt_char="❯"
prompt_pure_prompt_char="›"
prompt_pure_current_dir=""

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
prompt_pure_human_time() {
	local tmp=$1
	local days=$(( tmp / 60 / 60 / 24 ))
	local hours=$(( tmp / 60 / 60 % 24 ))
	local minutes=$(( tmp / 60 % 60 ))
	local seconds=$(( tmp % 60 ))
	(( $days > 0 )) && echo -n "${days}d "
	(( $hours > 0 )) && echo -n "${hours}h "
	(( $minutes > 0 )) && echo -n "${minutes}m "
	echo "${seconds}s"
}

# fastest possible way to check if repo is dirty
prompt_pure_git_dirty() {
	# check if it's dirty
	[[ "$PURE_GIT_UNTRACKED_DIRTY" == 0 ]] && local umode="-uno" || local umode="-unormal"
	command test -n "$(git status --porcelain --ignore-submodules ${umode})"
	return $?
}

prompt_pure_git_async_info() {
	local prompt_pure_preprompt="$1"
	local orig_pwd="$2"

	# save working directory for async check
	local pid=$$
	echo $PWD > /tmp/$pid.pwd

	# check async if there is anything to pull
	(( ${PURE_GIT_PULL:-1} )) && {
		# check check if there is anything to pull
		command git fetch &>/dev/null &&
		# check if there is an upstream configured for this branch
		command git rev-parse --abbrev-ref @'{u}' &>/dev/null && {
			local arrows=''
			(( $(command git rev-list --right-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows='⇣'
			(( $(command git rev-list --left-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows+='⇡'

			# return if working directory changed before this finished
			local current_pwd=$(</tmp/$pid.pwd)
			[[ "$current_pwd" = "$orig_pwd" ]] || return 1

			# rewrites previous line
			# \e7 - store cursor position
			# \e2A - go up two lines (prompt starts with \n which adds extra line)
			# %f - reset colors
			# \e8 - restore cursor position
			print -Pn "\e7\e[2A${prompt_pure_preprompt}${prompt_pure_error_color}${arrows}%f\e8"
		}
	} &!
}


# string length ignoring ansi escapes
prompt_pure_string_length() {
	echo ${#${(S%%)1//(\%([KF1]|)\{*\}|\%[Bbkf])}}
}


prompt_pure_hg_dirty() {
	# Grep exits with 0 when "One or more lines were selected", return "dirty".
	hg status 2> /dev/null | grep -Eq '^\s*[ACDIM!?L]'
	return $pipestatus[-1]
}

# displays the exec time of the last command if set threshold was exceeded
prompt_pure_cmd_exec_time() {
	local stop=$EPOCHSECONDS
	local start=${cmd_timestamp:-$stop}
	integer elapsed=$stop-$start
	(($elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5})) && prompt_pure_human_time $elapsed
}

prompt_pure_preexec() {
	cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title when a process is active
	print -Pn "\e]0;"
	echo -nE "$PWD:t: $2"
	print -Pn "\a"
}

prompt_pure_precmd() {
	# shows the full path in the title
	print -Pn '\e]0;%~\a'

	# git info
	vcs_info

	# shows expanded environment variables
	local short_dir=${${PWD/#%$HOME/\~}/#$HOME\//\~/}
	local vcs_prompt=""
	local prompt_pure_preprompt=""

	if [[ -d .git ]] || command git rev-parse --is-inside-work-tree &>/dev/null; then
		prompt_pure_git_dirty && vcs_prompt="${prompt_pure_error_color}${vcs_info_msg_0_}*" || vcs_prompt="${prompt_pure_ok_color}${vcs_info_msg_0_}"
		prompt_pure_preprompt="\n${prompt_pure_dir_color}${short_dir}${vcs_prompt} $prompt_pure_username%f ${prompt_pure_error_color}`prompt_pure_cmd_exec_time`%f"
		prompt_pure_git_async_info $prompt_pure_preprompt $PWD
	elif [[ -d .hg ]] || command hg summary > /dev/null 2>&1; then
		prompt_pure_hg_dirty && vcs_prompt="${prompt_pure_error_color}${vcs_info_msg_0_}*" || vcs_prompt="${prompt_pure_ok_color}${vcs_info_msg_0_}"
	fi

	[[ -z "$prompt_pure_preprompt" ]] && prompt_pure_preprompt="\n${prompt_pure_dir_color}${short_dir}${vcs_prompt} $prompt_pure_username%f ${prompt_pure_error_color}`prompt_pure_cmd_exec_time`%f"
	print -P $prompt_pure_preprompt

	# reset value since `preexec` isn't always triggered
	unset cmd_timestamp
}


prompt_pure_setup() {
	# prevent percentage showing up
	# if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	prompt_opts=(cr subst percent)

	zmodload zsh/datetime
	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	zstyle ':vcs_info:*' enable git hg
	zstyle ':vcs_info:git*' formats ' %b'
	zstyle ':vcs_info:git*' actionformats ' %b|%a'
	zstyle ':vcs_info:hg*' use-simple true
	zstyle ':vcs_info:hg*' formats ' %s:%b'
	zstyle ':vcs_info:hg*' actionformats ' %s:%b|%a'


	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username='%n@%m '

	# prompt turns red if the previous command didn't exit with 0
	PROMPT='%(?.$prompt_pure_ok_color.$prompt_pure_error_color)${prompt_pure_prompt_char}%f '
}

prompt_pure_setup "$@"
