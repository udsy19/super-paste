# Super Paste

An open-source clipboard manager for macOS: a searchable history of everything you copy, pinboards for the things
you keep, a Paste Stack for pasting in sequence, end-to-end-encrypted folder sync and a local MCP server.

Work in progress. Requires macOS 14 or later.

## Build

```
scripts/signing-setup.sh   # once: a project-local code-signing identity (.signing/)
scripts/build-app.sh       # build/Super Paste.app
swift run SuperPasteSelfTest
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organised.

## License

MIT — see [LICENSE](LICENSE).
