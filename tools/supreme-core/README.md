# Supreme Trade Core (Rust)

Rust is the data core for the MM2 Supreme Trade Checker. It fetches the official Supreme Values category pages, parses item cards, validates category coverage, normalizes names, and publishes a versioned JSON snapshot. The Roblox executor still runs the display and MM2 database matching layer in Luau; this project does not attempt to load a native DLL into Arceus X.

## Live pipeline

1. GitHub Actions runs `supreme-trade-core refresh`.
2. The Rust scraper fetches all 14 MM2 category pages from `https://supremevalues.com/mm2/{category}`.
3. Tradable categories are parsed into entries using the value shown on each item card. Sets, evos and untradables are checked for page availability but are not mixed into single-item tradable values.
4. Minimum card-count checks reject incomplete/changed pages rather than publishing a partial dataset.
5. Rust writes `data/SupremeTradeChecker.mapping.json` with the raw entries, generated timestamp, category/page counts, and deterministic `by_name` / `by_image_alt` indexes.
6. The Luau client downloads the JSON, validates schema version and age, uses Rust's indexes, then matches values to the live `ReplicatedStorage.Database.Sync` records and renders the badges.
7. If the JSON endpoint is unavailable, Luau falls back to the previous in-game Supreme scraper.

GitHub Actions refreshes the dataset every six hours on the default branch. Pushes to the development branch also attempt an initial refresh and publish the first JSON file.

## Build / test locally

Install Rust using rustup, then run:

```sh
cargo test --manifest-path tools/supreme-core/Cargo.toml
cargo run --manifest-path tools/supreme-core/Cargo.toml --release -- refresh data/SupremeTradeChecker.mapping.json
```

A refresh requires network access to Supreme Values and deliberately fails if critical categories are missing or parsed counts fall below their guardrails.

## Offline JSON build and trade-total CLI

The core also supports fixture-based builds and a small independent total calculator:

```sh
cargo run --manifest-path tools/supreme-core/Cargo.toml --release -- build tools/supreme-core/examples/supreme-export.json /tmp/SupremeTradeChecker.mapping.json
cargo run --manifest-path tools/supreme-core/Cargo.toml --release -- total /tmp/SupremeTradeChecker.mapping.json tools/supreme-core/examples/items.json
```

The total report multiplies each item value by its quantity. Unknown, ambiguous and tier-only entries are reported explicitly; the overall total is omitted rather than silently treating unresolved lines as zero.

## JSON contract (schema version 1)

Top-level fields:

- `schema_version`: currently `1`
- `source`, `generated_at_unix`, `entry_count`
- `category_counts`: parsed tradable value-card counts per category
- `page_card_counts`: total item cards seen on each category page
- `entries`: compact Supreme entries using `c,n,im,y,e,o,cl,v,t,dm`
- `by_name`: normalized name to zero-based entry indexes
- `by_image_alt`: normalized image alt text to zero-based entry indexes

The executor accepts the mapping only when the schema matches, there are at least 300 entries, both Rust indexes exist, and the snapshot is no older than seven days.
