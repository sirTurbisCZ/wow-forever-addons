# Contributing

## Reporting a bug

Open a [GitHub issue](https://github.com/sirTurbisCZ/wow-forever-addons/issues) with the label `bug` and include:

- the game client build and the version of each addon involved (shown in chat at login, and in the `.toc`)
- the steps to reproduce, and what you expected instead
- for Lua errors: `/felog` opens ForeverErrorLog's window; its **Copy** text starts with a report header, so paste all of it

## Proposing a feature

Open an issue with the label `enhancement`. The addons stay deliberately simple: few options, one minimap button and one settings window each, and nothing heavy at login or per frame. Proposals that fit that are much more likely to be accepted.

## Changes

Every fix and feature goes through an issue first. Pull requests reference it (`Closes #N` in the description) so it closes on merge.

Before opening a pull request, run the syntax check on every Lua file:

```sh
find addons -name '*.lua' -type f -exec luac5.1 -p {} \;
```

## Releases

A release is a tag named `<addon>-v<version>`: `felog`, `plateband`, `betterbackpack`, `wayfarer`, `seekwell` or `seekwell-locations`, for example `plateband-v0.8.1`. The version must equal the `## Version` in the addon's `.toc`. Push tags one at a time. The workflow checks the version, syntax-checks the Lua files, builds the zip and publishes a GitHub Release using the newest section of the addon's `Docs/CHANGELOG.md`.
