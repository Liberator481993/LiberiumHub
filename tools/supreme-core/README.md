# Supreme Trade Core (Rust)

Rust is the data/indexing core for the MM2 Supreme Trade Checker. The in-game client stays Luau because Arceus X executes Luau, not native Rust DLLs.

## Data flow

1. The Luau checker in Arceus X fetches Supreme Values pages using the executor's HTTP capability (the same path that has already been used by the in-game checker).
2. Once the full dataset is parsed and page checks pass, open the checker panel and press **EXPORT JSON**. The script saves `SupremeTradeChecker_export.json` with `writefile` when the executor supports it and also copies the same JSON to the clipboard as a fallback.
3. Upload the exported file to the repository as `data/supreme-export.json` on branch `supreme-trade-checker-rust-core`.
   - If `writefile` is unavailable, create `data/supreme-export.json` from the copied clipboard contents instead.
   - The export includes parsed category/card counts and uses schema version `1`; the Rust importer accepts numeric or string `v` fields.
4. GitHub Actions validates that the reported category counts exactly match the exported entries and that all 14 category pages have non-zero card counts. It then runs the Rust core's `build` command, validates the output schema, generates normalized `by_name` and `by_image_alt` indexes, and publishes `data/SupremeTradeChecker.mapping.json` to the stable `supreme-values-data` branch.
5. Luau downloads that stable JSON snapshot, validates schema version and age, then matches its item entries against the live `ReplicatedStorage.Database.Sync` database and displays item values and trade/inventory totals.
6. If the Rust snapshot is unavailable, Luau retains its existing Supreme page scraper as a fallback.

6. If the Rust snapshot is unavailable, Luau retains its existing Supreme page scraper as a fallback.

## MM2 item resolution
- Inventory totals use exact, namespaced database keys (`i:` for weapons and `p:` for pets) from `InventoryModule.Data`. GUI Frames are used for labels only and are not required for totals.
- Starter placeholders `DefaultGun` and `DefaultKnife` are omitted from tradeable totals.
- Leaderboard trophies are identified per database record: the item must be `Unique` and have an exact color word at the beginning of its name (for example, `Gold Icepiercer`), or an exact recognized color suffix in its database key. Arbitrary substring matches are not used. These trophies are shown as `UNTRADABLE` and omitted from tradeable inventory totals.
- Chroma detection is consistent across names, item flags, icon indexes, name indexes, and Chroma-to-base relationships. Both prefixed and base names are indexed.
- Trade cards support normal containers, image-only cards, and direct `NewItem` slots. Duplicate card instances are counted independently; stack quantities are read from `Amount`.
- Item states are kept separate: `LOADING`, `UNKNOWN`, `NO VALUE`, and `UNTRADABLE`. Unknown items are not silently converted to zero.

GitHub Actions publishes only when `data/supreme-export.json` exists. A code-only push runs the Rust tests but skips snapshot publication; a push that includes the export builds and validates the mapping before replacing the `supreme-values-data` snapshot. The workflow does not fetch Supreme Values from GitHub-hosted runners.

**Why the export step exists:** GitHub-hosted runners received HTTP 403 from Supreme Values on all 14 category pages during the live scrape check. The user-side Arceus X scraper is the supported data-ingress point; the workflow no longer pretends that GitHub can scrape those pages. It only publishes a map after a complete export has been supplied.

## Rust CLI

Install Rust via rustup:

```sh
cargo test --manifest-path tools/supreme-core/Cargo.toml
cargo run --manifest-path tools/supreme-core/Cargo.toml --release -- build data/supreme-export.json data/SupremeTradeChecker.mapping.json
cargo run --manifest-path tools/supreme-core/Cargo.toml --release -- total data/SupremeTradeChecker.mapping.json tools/supreme-core/examples/items.json
```

The standalone `refresh` command is also available for environments where the Supreme Values host permits direct HTTP access:

```sh
cargo run --manifest-path tools/supreme-core/Cargo.toml --release -- refresh data/SupremeTradeChecker.mapping.json
```

## Mapping format

Top-level fields:

- `schema_version`: currently `1`
- `source`, `generated_at_unix`, `entry_count`
- `category_counts` and `page_card_counts`
- `entries`: compact Supreme item records using `c,n,im,y,e,o,cl,v,t,dm`
- `by_name`: normalized item name to zero-based entry indexes
- `by_image_alt`: normalized image alt text to zero-based entry indexes

The Rust total calculator multiplies each item value by its quantity. Unknown, ambiguous, and tier-only entries are reported explicitly; unresolved values are never silently treated as zero.
