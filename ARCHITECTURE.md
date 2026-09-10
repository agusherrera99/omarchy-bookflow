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
   - last sample within `session_gap_minutes` (default 15), and the page moved
     forward at a speed a person could read at → extend it: move `end_page`,
     recompute `pages`, add the elapsed minutes capped at the gap.
   - moved backwards, or forwards faster than `MAX_PAGES_PER_MINUTE` (20) allows
     for the elapsed time → navigation. Close the session where it was and
     anchor a new one at the new page with zero pages.
   - no open session → open one at `page - 1`.
4. Page unchanged and sampled less than a minute ago → return without writing.

### Reading is not the same as navigating

A page moving is the evidence that you are reading — but only if it moved at a
speed a person could read at. Jumping to the index, a bookmark, or the end moves
the page too, and crediting that as reading lets one flick through a book
outweigh weeks of real sessions in an average built from ten of them. A single
14 → 367 jump measured at 5,295 pages per minute once put the pace at 52.7
pages per session against a true figure of 2.7.

The allowance is `elapsed × 20` pages, floored at 5 so a fast sample is not
punished for its own promptness. It cannot be gamed by a long absence either:
`close_stale_sessions` runs first, so an open session's elapsed time is always
under the gap, capping the allowance at around 300 pages.

A jump still moves `current_page` and `furthest_page` — you did go there, and
reaching the last page still finishes the book. What it does not do is claim you
read your way there.

Consequences worth knowing:

- Opening a book from Nautilus is tracked exactly like opening it from the panel.
- Two shells sampling at once cannot double-count; step 4 makes the sample idempotent.
- `furthest_page` is what drives progress, so paging back to re-read does not
  undo it. `current_page` still follows the cursor, and `set-page` overrides both.
- Completion keys off the page just reached, not `furthest_page`. The two differ
  the moment a finished book is picked up again, and using the high-water mark
  there would re-finish the book on its first sample.
- A finished book stays finished when you choose it. Reopening a book you have
  read is usually to look something up, not to read it again, so `select` makes
  it the current book without touching its progress, and `sync` records nothing
  for a book whose status is not `active`. Reading it again is a separate,
  deliberate act: `restart` clears the progress and `completed_at`. The first
  sample after a restart opens its session at `page - 1`, so re-opening a
  finished book at page 200 posts a session of one page, not two hundred.
- Which book is current is therefore its own fact, stored as the
  `current_book_id` setting rather than inferred from `status = 'active'` —
  those two stopped meaning the same thing the moment a finished book could be
  the one on screen. `active_book()` falls back to the old status lookup, so
  databases written before the split keep working.

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

### Who owns the keyboard

`PanelKeyCatcher` sits above the content with `Keys.priority: Keys.BeforeItem`,
so it sees keys before the focused control does. That is what lets a bare letter
be a shortcut — and it is why a panel with text inputs has to say when to stand
down. `blocked` is bound to exactly that: any dropdown popup open, or any editor
holding focus. Without it, typing a library path fired one action per letter,
since `o`, `s` and `c` are all shortcuts and all appear in `Documents`.

Tab is the shell's gesture for moving between bar panels, which leaves a panel
containing a form with no way in. Here it goes to the nearer place first: with
the settings form open, Tab hands focus to the next control in the chain, and
only switches panels when there is no form to enter. Buttons opt into being tab
stops with `focusable`, which they do not do by default.

Escape backs out one layer — the settings section if it is open, otherwise the
panel. While an editor holds the keys the catcher is blocked, so the Flickable
carries its own Escape handler to catch what the catcher no longer sees.

## Noticing that a book was finished

A book ends two ways: its last page is reached, or the panel's finish button is
pressed. Rather than have each path raise its own flag, `Service.qml` watches
`library.done` — already in every status payload — and emits `bookFinished` when
it goes up. One trigger covers both, and it stays correct if a third way is ever
added.

The order matters: the signal fires *after* the new payload is assigned, so
anything reacting to it reads the state the finish produced rather than the one
before it. The count starts at `-1` so the first payload of a session cannot be
mistaken for a book having just been finished.

The bar widget answers it by holding a finished state for 2.6s — check glyph,
`100%`, accent colour — over a two-beat scale bounce. Two beats rather than one:
the lift reads as the moment it lands, and the settle keeps it from looking like
the bar hiccuped. `scale` is a visual transform, so neighbouring widgets never
move.

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
