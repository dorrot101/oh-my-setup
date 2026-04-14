[user]
    name = {{git_user_name}}
    email = {{git_user_email}}

[init]
    defaultBranch = {{git_default_branch}}

[core]
    editor = vim
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    light = false

[merge]
    conflictstyle = diff3

[diff]
    colorMoved = default

[pull]
    rebase = true

[push]
    autoSetupRemote = true
