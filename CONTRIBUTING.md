# Contributing to Monorail

Thanks for helping make Monorail better.

## Reporting bugs

Open an [issue](https://github.com/ashfordeOU/macslider/issues) and include:

- your macOS version and Mac model (Apple silicon or Intel),
- the Monorail version (Settings → About),
- the app whose windows misbehaved, and what you expected to happen.

Logs are in Console.app: filter on the subsystem `org.ashforde.macslider`.

## Development

```bash
make test   # unit tests for the layout model
make run    # build dist/Monorail.app and open it
```

- Layout behaviour belongs in `Sources/MonorailCore` and should come with a test in `Tests/`.
- Code that talks to macOS (Accessibility, events, windows, UI) lives in `Sources/Monorail`.
- Match the style of the surrounding code; keep functions small and comments about *why*.
- Keep pull requests focused on one change, and describe how you tested it.

## Releases

1. Update `VERSION` and add a section to `CHANGELOG.md`.
2. Commit, then tag: `git tag v$(cat VERSION) && git push --tags`.
3. The release workflow builds, signs with the repository's signing certificate
   (see `scripts/make-signing-cert.sh`), packages and publishes the GitHub release.

## License

By contributing you agree that your contributions are licensed under the
[GNU Affero General Public License v3.0](LICENSE).
