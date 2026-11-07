# Supreme Trade Core (Rust)

A standalone Rust core for deterministic Supreme Values name normalization, lookup-index generation, ambiguity handling, and duplicate-quantity totals. The in-game interface remains Luau because Arceus X executes Luau; this crate is not a DLL and is not loaded inside Roblox.

## Input contract

The Rust CLI consumes a JSON export of the entries already parsed by the Luau scraper. Each entry uses the compact fields produced by the checker:

- `c`: category (for example `godlies` or `chromas`)
- `n`: Supreme item name
- `im`: image alt text
- `v`: numeric value as a string, or null for tier-only values
- `t`: tier label, if present
- `y`, `e`, `o`, `cl`, `dm`: year, event, origin, class, demand

Example `supreme-export.json`:

```json
{
  "schema_version": 1,
  "entries": [
    {"c":"godlies","n":"Lightbringer","im":"Lightbringer","v":"45","t":"","y":"","e":"","o":"","cl":"","dm":""},
    {"c":"chromas","n":"Seer","im":"Seer","v":"15","t":"","y":"","e":"","o":"","cl":"","dm":""}
  ]
}
```

## Build the indexed mapping

Install Rust via rustup, then run:

```sh
cd tools/supreme-core
cargo test
cargo run --release -- build supreme-export.json SupremeTradeChecker.mapping.json
```

The mapping contains the original entries plus deterministic `by_name` and `by_image_alt` indexes. Duplicate names are retained as candidate lists; the core never silently chooses between ambiguous matches.

## Calculate a trade total

Create `items.json`:

```json
[
  {"name":"Lightbringer","quantity":2,"chroma":false},
  {"name":"Seer","quantity":1,"chroma":true}
]
```

Run:

```sh
cargo run --release -- total SupremeTradeChecker.mapping.json items.json
```

The report includes per-item values, quantity subtotals, and a total only when every line resolves to a numeric value. Unknown, ambiguous, and tier-valued entries are explicitly reported instead of being counted as zero.

## Runtime boundary

This is the first Rust-core milestone: a tested, portable data engine and stable JSON contract. It does **not** yet run in Arceus X. A later integration step must either publish a generated mapping JSON for the Luau client to fetch, or run this core behind a hosted API. Neither a Rust DLL nor native FFI is assumed to work in Arceus X.
