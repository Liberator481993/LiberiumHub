# Supreme Trade Checker

In-game Supreme Values overlay for Murder Mystery 2. This is a Luau script for an executor, not an APK or a standalone application.

## Features

- Shows Supreme numeric Value badges on supported inventory and trade item cards.
- Calculates the total value on both sides of an active trade.
- Counts stack quantities, including duplicate items, using a shared aggregation path for inventory and both trade sides.
- Preserves small fractional Supreme Values, including values displayed in scientific notation.
- Displays a WIN / FAIR / LOSE result and the numeric difference whenever at least one side contains numeric values.
- Keeps unknown and tier-only items visible as separate counts; they are not silently added to numeric totals.
- Shows an inventory value total and item-value coverage diagnostics, including data-only inventory records whose GUI cards are missing or detached when their exact MM2 database key is available.
- Includes a copyable diagnostic report for troubleshooting.
- Can optionally cache parsed Supreme Values locally for up to seven days when the executor supports file access.
- Includes an optional public-server hop button.

## Loadstring

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Liberator481993/LiberiumHub/main/SupremeTradeChecker.lua"))()
```

## Trade result rules

- Numeric Supreme Values are summed, multiplied by stack quantity.
- Unknown items and tier-only entries are excluded from the numeric subtotal.
- If some items are excluded, the checker still displays a result based on known numeric Values and adds a warning.
- If neither side has any numeric Value, the checker displays that there is no numeric comparison to make.
- A partial result is not a guarantee of a fair trade: check excluded items manually.

## Requirements and notes

- Run inside MM2 using a Luau executor that supports the required Roblox UI and HTTP access.
- The checker reads the live MM2 item database and the Supreme Values MM2 pages.
- If live pages cannot be fetched, a valid local cache may be used. Without either complete live data or a valid cache, value loading fails rather than silently using a partial page set.
- Local cache and clipboard support depend on executor capabilities; neither is required for the core in-game overlay.
- The script is informational only. It does not accept, decline, send, or modify trades.

## Diagnostics

Open the compact Supreme panel and use **COPY FULL DIAGNOSTIC**. The report includes:

- Supreme page loading and cache status
- MM2 database and mapping counts
- Inventory and trade totals
- Valued, tier-only, unknown, and unmatched item coverage
- Inventory and trade scanner states and any captured errors
- Frame-less inventory entries are resolved only by exact MM2 database key; otherwise they remain unknown

When reporting an issue, send the complete copied report and describe what screen was open (inventory or active trade).

## Validation status

The repository workflow checks that `SupremeTradeChecker.lua` and `SupremeTradeChecker.txt` are identical and compiles the Lua file with the official Luau compiler. Passing that workflow confirms copy synchronization and syntax compilation; it does not replace an in-game executor test.
