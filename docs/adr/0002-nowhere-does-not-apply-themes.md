# Nowhere does not apply themes

Nowhere stays out of theming. It sets colors only by the terminal's sixteen names and loads an optional theme file (`~/.config/nowhere/theme.ps1` or `theme.zsh`) last. Bootstrap, `update` and any Ansible role never create, choose, fetch or change that file. They offer no theme flag, prompt or picker. Applying a theme is up to the user or the theme's own repo, which can drop in a theme file or change each tool's settings itself. Nowhere's job ends at providing the file's location and loading it last.

This settles issue #31, which explored a theme picker in bootstrap and the Ansible role, and keeps the rule from issue #29 that Nowhere ships no theme file and never creates one.
