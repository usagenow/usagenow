# Command line (1.0.0)

In Settings › General choose **Install CLI**. This creates
`~/.local/bin/usagenow`, a symlink to the command bundled inside UsageNow.
Add `~/.local/bin` to your shell's PATH if needed. The app does not change shell
profiles or replace an unrelated existing command. **Remove CLI** removes only
its own symlink. Leave the app in a stable location before installing the link.

```sh
usagenow status
usagenow status --json
usagenow --help
usagenow --version
```

The command reads only `widget-snapshot.json` from the same build's App Group.
It does not start UsageNow, refresh providers, inspect tool folders or credentials,
or access the network. With the app closed it reports the saved snapshot and its
age. Open UsageNow to get a new reading. Debug builds read only their Debug group.

JSON schema **1** has `schemaVersion`, `generatedAt`, `readAt`, `state`, `stale`
and `providers`. Each provider contains its local selection ID, provider name,
optional user-chosen account label and reported plan, capture time, freshness,
quota availability reason and reported windows. Each window contains its kind,
optional duration and scope, remaining percentage and reset date. Dates use ISO
8601 UTC; data over ten minutes old is stale. Percentages become unknown after
their reported reset. Missing optional fields are omitted, never fabricated as
zero. Future consumers should ignore extra fields and check `schemaVersion`.

Exit **0** means the snapshot was read, including stale or empty results.
Exit **1** means a missing, corrupt or unsupported snapshot. Exit **2** means
invalid arguments. JSON is written only on success, diagnostics go to stderr.

This is current status output, not a historical activity export. Do not publish
the output without reviewing user-chosen account labels and usage information.
