typeset -U path PATH
path=("$HOME/bin" "$HOME/.local/bin" "$HOME/.grok/bin" "$HOME/.bun/bin"
      "$HOME/.local/share/mise/shims" /opt/homebrew/bin /usr/local/bin $path)

# Load GH_TOKEN from the macOS login Keychain (survives reboots, available to
# non-interactive shells). Store/update the token with:
#   security add-generic-password -U -a "$USER" -s gh-token -w
# Guard against an empty lookup so gh can fall back to its keyring login.
__gh_token="$(security find-generic-password -a "$USER" -s gh-token -w 2>/dev/null)"
# GITHUB_AUTH_TOKEN is what bun reads for the @rogo-technologies npm registry
# (see ask-rogo bunfig.toml). The PAT must include the read:packages scope.
[ -n "$__gh_token" ] && export GH_TOKEN="$__gh_token" && export GITHUB_AUTH_TOKEN="$__gh_token"
unset __gh_token

# Personal GitHub account (kushrp). Its token lives in a SEPARATE Keychain slot so
# it never clobbers the work GH_TOKEN above. Store/update it (paste at the hidden
# prompt) with:
#   security add-generic-password -U -a "$USER" -s gh-token-kushrp -w
# Then use `ghk ...` exactly like `gh ...` for anything under the kushrp account
# (e.g. `ghk repo create kushrp/second-brain --private`). git push needs no token:
# the github-kushrp SSH alias already authenticates as kushrp.
ghk() { GH_TOKEN="$(security find-generic-password -a "$USER" -s gh-token-kushrp -w 2>/dev/null)" gh "$@"; }

# Silence zoxide's doctor "possible configuration issue" warning in ALL shells,
# incl. non-interactive/agent shells that source .zshenv but not the interactive
# .zshrc (where it was previously set). Known false-positive from several tools
# registering precmd/chpwd hooks — see .zshrc §6.
export _ZO_DOCTOR=0
