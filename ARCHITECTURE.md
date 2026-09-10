# How Bookflow is built

`README.md` covers using the plugin. This file covers its insides: why it is
split the way it is, and where to look when something needs changing.

## The shape

Two layers, with a hard line between them:

```
bin/bookflow      Python, 1100 lines. Owns the database and every calculation.
                  Speaks JSON. Runnable on its own.
    ▲
    │  Process + JSON.parse
    │
Service.qml       Runs the CLI, holds the parsed payload, owns the poll timer.
BarWidget.qml     The bar entry point. Icon + percentage. Hosts the Service.
Panel.qml         The popup. Reads Service properties, calls Service functions.
Strings.js        en/es tables.
Format.js         Percentages, short dates, collection labels.
```

**The QML calculates nothing.** No pace, no estimate, no page arithmetic — it
renders fields that arrive in the JSON. That line is worth defending: it is what
lets you check any number the panel shows by running one command in a terminal,
and it keeps the reading logic in a language with a test story.

The reverse also holds: the CLI knows nothing about the bar. It is a normal
command with a normal exit status, and the panel is one of its callers.

### Why the CLI lives inside the plugin repo

`omarchy plugin add` clones files and nothing else — it runs no install hooks,
by design. So there is no step that could copy a binary onto `PATH`. The plugin
resolves its own CLI instead:

```qml
readonly property string cli: Qt.resolvedUrl("bin/bookflow").toString().replace(/^file:\/\//, "")
```

Cloning the repo is the whole installation. The cost is that `bookflow` is not
on your `PATH` — run it as `bin/bookflow` from the plugin directory.

Every invocation is wrapped in `timeout -k 2 20` so a wedged `gio` or `pdfinfo`
cannot hang the shell process, which hosts the entire desktop.

## The idea the design rests on

Evince saves the last page of every file it opens as a gvfs metadata attribute:

```console
$ gio info -a metadata::evince::page book.pdf
  metadata::evince::page: 11
```

It is **0-based** — that is page 12. Papers, Xreader and Atril do the same under
their own attribute names; Zathura and Okular keep equivalent state in files.

This is why there is no "log your reading" button anywhere in the plugin. The
reader already recorded it.

### Reader adapters

Each adapter answers one question — *what page is this file open at, 1-based, or
`None`* — and they are registered in a single table in `bin/bookflow`:

```python
READERS = {
    "evince": {"label": "Document Viewer",
               "position": gvfs_position("metadata::evince::page"),
               "formats": ["pdf"]},
    ...
}
```

`position: None` means the reader cannot report a page; the panel then shows the
manual-entry hint and the **Current page** field carries the book instead. That
is the EPUB story today: Calibre stores its position as an EPUB CFI with no
usable page index, and the hash it names its state files by is not reliably
derivable, so guessing was worse than asking.

Adding a reader is one entry in that table plus a `*_position(path)` function.
Nothing else in the codebase knows which readers exist.

## Session detection without watching a process

The obvious design is to find the reader's PID and time how long it lives. This
does not do that. **A page that moved is the signal that you are reading** —
that is the only evidence needed, and it costs one attribute read.

`bookflow sync` takes one sample and is idempotent:

1. No active book, or no saved position → no-op.
2. Clamp the page to the book's length; `furthest_page = max(furthest_page, page)`.
3. Find the book's open session (`ended_at IS NULL`):
   - last sample within `session_gap_minutes` (default 15) → extend it: move
     `end_page`, recompute `pages`, add the elapsed minutes capped at the gap.
   - otherwise → close it and open a new one starting at the previous page.
4. Page unchanged and sampled less than a minute ago → return without writing.

Consequences worth knowing:

- Opening a book from Nautilus is tracked exactly like opening it from the panel.
- Two shells sampling at once cannot double-count; step 4 makes the sample idempotent.
- `furthest_page` is what drives progress, so paging back to re-read does not
  undo it. `current_page` still follows the cursor, and `set-page` overrides both.

The QML side of this is a single adaptive timer in `Service.qml`: 60s at rest,
tightening to 15s for five minutes after a sample reports `changed`, plus an
immediate sync when the panel opens.

## The estimate, and its honesty

Constants live at the top of `bin/bookflow`: `PACE_WINDOW_SESSIONS = 10`,
`RATE_WINDOW_DAYS = 28`.

- **Pace** — mean pages per session over the last 10 sessions with `pages > 0`,
  across all books. Global rather than per-book so a freshly started book
  inherits a real number instead of a guess.
- **Rhythm** — distinct days with reading in the last 28, normalised to a week.
- Under 3 recorded sessions both fall back to the configured values, and the
  payload says which was used via `pace_source` / `sessions_per_week_source`.
  The panel prints that under each figure, so a number sourced from a setting
  never masquerades as a measurement.
- **Confidence** is `none` under 3 sessions, `low` under 10, then `high` when the
  coefficient of variation is under 0.5 and `medium` otherwise.

## Data

One SQLite file, `~/.local/share/bookflow/library.sqlite3`, schema version 2.

| Table | Holds |
|---|---|
| `books` | one row per file found in the catalog, plus `status`, `current_page`, `furthest_page` |
| `sessions` | one row per reading session; `ended_at IS NULL` marks the open one |
| `settings` | preferences, all stored as TEXT and coerced on read |
| `meta` | `schema_version` |

`books.path` is relative to `catalog_root`, so moving the whole library is a
`catalog_path` change and a rescan rather than a migration.

Scanning derives the collection from the first directory level and reading
priority from its `NN_` prefix; a book whose file disappears is deleted when it
had no progress and marked `missing` when it did.

## Shortcuts that show themselves

A panel full of icon buttons is a panel whose keyboard shortcuts nobody finds.
The `ActionKey` component in `Panel.qml` pairs every action icon with the key
that fires it, rendered as a lowercase letter at caption size and 0.3 opacity:

```qml
ActionKey { glyph: bookOpenIcon; hint: "o"; tooltip: root.t("openBook"); ... }
```

Three decisions make it discoverable without becoming clutter:

- **It costs no layout.** The letters sit in the horizontal gap the icon row
  already had, so nothing moved and no row was added to carry them.
- **Lowercase, not uppercase.** In the bar's monospace font an uppercase `O` is
  hard to tell from a zero, and lowercase is what you actually press.
- **Settings answers to `c`, not `,`.** A comma is the conventional preferences
  key, but as a hint badge it reads as punctuation rather than a key and has
  none of the visual weight of the other four. `c` covers *config* and
  *configuración* both; `,` still works for anyone with the habit.

The tooltip carries the same key after the action name, so hovering and reading
agree.

## Where the two languages meet

`Strings.js` (QML) and `STRINGS` in `bin/bookflow` are parallel tables — the CLI
translates only its own terminal output, the panel translates the UI. The CLI
emits *keys*, never prose, for anything the panel displays: `confidence` comes
back as `"low"`, and `Strings.js` turns it into "low" or "baja".

Plurals go through `Strings.tn(language, count, key, fields)`, which picks
`keyOne` or `keyOther` — Spanish needs "falta 1" against "faltan 365", which a
single template cannot express.

The language itself is stored in the database, not in `shell.json`, so the CLI
and the panel cannot disagree about it. Every settings control writes through
`bookflow prefs --set`, making the database the single source of truth.

## Developing on it

**After editing anything but `BarWidget.qml`, restart the shell.** Omarchy's
hot reload and `omarchy-shell shell rescanPlugins` reliably reload only the
top-level entry point; imported `.js` and components loaded through
`Loader { source: Qt.resolvedUrl(...) }` keep serving cached versions, with no
error logged to suggest it.

```bash
omarchy-restart-shell && sleep 8
```

Plugin `console.log` output lands in the user journal as `DEBUG qml:`:

```bash
journalctl --user --since "15 seconds ago" -o cat | grep -i qml
```

Validate the manifest the way the shell will:

```bash
omarchy plugin validate .
```

### Testing capture without a reader

Set the attribute by hand and sync:

```bash
gio set book.pdf -t string metadata::evince::page 11
bin/bookflow sync
```

To do that against a throwaway library instead of your real one, override both
locations — `XDG_DATA_HOME` moves the database, `BOOKFLOW_CATALOG` the catalog:

```bash
XDG_DATA_HOME=/tmp/bf BOOKFLOW_CATALOG=/tmp/books bin/bookflow scan
```

This is how session grouping, the gap boundary, and the monotonic
`furthest_page` were verified; all three are cheap to re-check the same way.
