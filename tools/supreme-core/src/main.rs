use regex::Regex;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, env, fs, process, thread, time::Duration};

const BASE: &str = "https://www.supremevalues.com/mm2/";
const CATEGORIES: &[&str] = &[
    "sets", "uniques", "evos", "ancients", "vintages", "chromas", "godlies",
    "legendaries", "rares", "uncommons", "commons", "pets", "misc", "untradables",
];
const MINIMUM: &[(&str, usize)] = &[
    ("godlies", 80), ("chromas", 30), ("commons", 150), ("uncommons", 100),
    ("rares", 80), ("legendaries", 40), ("ancients", 8), ("pets", 40), ("uniques", 1),
];

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SupremeEntry {
    #[serde(default)] c: String,
    #[serde(default)] n: String,
    #[serde(default)] im: String,
    #[serde(default)] y: String,
    #[serde(default)] e: String,
    #[serde(default)] o: String,
    #[serde(default)] cl: String,
    #[serde(default, deserialize_with = "deserialize_optional_value")] v: Option<String>,
    #[serde(default)] t: String,
    #[serde(default)] dm: String,
}
#[derive(Debug, Deserialize)]
struct InputFile {
    #[serde(default)] schema_version: u32,
    #[serde(default)] category_counts: BTreeMap<String, usize>,
    #[serde(default)] page_card_counts: BTreeMap<String, usize>,
    entries: Vec<SupremeEntry>,
}

fn deserialize_optional_value<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum InputValue {
        Text(String),
        Number(f64),
    }

    let value = Option::<InputValue>::deserialize(deserializer)?;
    Ok(value.map(|v| match v {
        InputValue::Text(text) => text,
        InputValue::Number(number) => number.to_string(),
    }))
}
#[derive(Debug, Serialize, Deserialize)]
struct MappingFile {
    schema_version: u32,
    source: String,
    generated_at_unix: i64,
    entry_count: usize,
    category_counts: BTreeMap<String, usize>,
    page_card_counts: BTreeMap<String, usize>,
    entries: Vec<SupremeEntry>,
    by_name: BTreeMap<String, Vec<usize>>,
    by_image_alt: BTreeMap<String, Vec<usize>>,
}
#[derive(Debug, Deserialize)]
struct RequestedItem {
    name: String,
    #[serde(default = "one")] quantity: u64,
    #[serde(default)] chroma: Option<bool>,
}
fn one() -> u64 { 1 }
#[derive(Debug, Serialize)]
struct TotalLine {
    name: String, quantity: u64, value_each: Option<f64>,
    subtotal: Option<f64>, status: &'static str,
}
#[derive(Debug, Serialize)]
struct TotalReport { schema_version: u32, total: Option<f64>, lines: Vec<TotalLine> }

fn normalize(input: &str) -> String {
    input.chars().flat_map(char::to_lowercase).filter(|c| c.is_alphanumeric()).collect()
}
fn is_chroma(e: &SupremeEntry) -> bool {
    e.c.eq_ignore_ascii_case("chromas") || e.cl.to_ascii_lowercase().contains("chroma")
        || e.n.to_ascii_lowercase().starts_with("chroma ")
}
fn add(index: &mut BTreeMap<String, Vec<usize>>, key: String, id: usize) {
    if !key.is_empty() { index.entry(key).or_default().push(id); }
}
fn parse_numeric_value(raw: &str) -> Option<String> {
    let value = raw.trim().replace(',', "").parse::<f64>().ok()?;
    if !value.is_finite() || value <= 0.0 { return None; }
    let mut formatted = format!("{value:.4}");
    while formatted.contains('.') && formatted.ends_with('0') { formatted.pop(); }
    if formatted.ends_with('.') { formatted.pop(); }
    Some(formatted)
}

fn build(entries: Vec<SupremeEntry>, category_counts: BTreeMap<String, usize>,
         page_card_counts: BTreeMap<String, usize>) -> MappingFile {
    let mut by_name = BTreeMap::new();
    let mut by_image_alt = BTreeMap::new();
    for (id, entry) in entries.iter().enumerate() {
        add(&mut by_name, normalize(&entry.n), id);
        let alt = normalize(&entry.im);
        if !alt.is_empty() && alt != normalize(&entry.n) { add(&mut by_image_alt, alt, id); }
    }
    MappingFile {
        schema_version: 1, source: "Supreme Values MM2".into(),
        generated_at_unix: chrono::Utc::now().timestamp(), entry_count: entries.len(),
        category_counts, page_card_counts, entries, by_name, by_image_alt,
    }
}
fn parse_page(category: &str, html: &str) -> Result<(Vec<SupremeEntry>, usize), String> {
    let document = Html::parse_document(html);
    let card_selector = Selector::parse(".itemcolumn").map_err(|e| e.to_string())?;
    let head_selector = Selector::parse(".itemhead").map_err(|e| e.to_string())?;
    let origin_selector = Selector::parse(".itemorigin").map_err(|e| e.to_string())?;
    let image_selector = Selector::parse("img").map_err(|e| e.to_string())?;
    let value_re = Regex::new(r"(?i)Value\s*[-:–—]\s*([0-9][0-9,.]*)").unwrap();
    let tier_re = Regex::new(r"(?i)Value\s*[-:–—]\s*([x×]\s*\d+\s+T\d+\s+[A-Za-z]+)").unwrap();
    let class_re = Regex::new(r"(?i)Class\s*[-:]\s*([A-Za-z]+)").unwrap();
    let mut entries = Vec::new();
    let mut cards = 0;
    for card in document.select(&card_selector) {
        cards += 1;
        let name = card.select(&head_selector).next()
            .map(|x| x.text().collect::<Vec<_>>().join(" ").trim().to_string()).unwrap_or_default();
        if name.is_empty() { continue; }
        let text = card.text().collect::<Vec<_>>().join(" ");
        let tier = tier_re.captures(&text).and_then(|c| c.get(1)).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
        let value = value_re.captures(&text)
            .and_then(|c| c.get(1))
            .and_then(|m| parse_numeric_value(m.as_str()));
        if value.is_none() && tier.is_empty() { continue; }
        let origin = card.select(&origin_selector).next()
            .map(|x| x.text().collect::<Vec<_>>().join(" ").trim().to_string()).unwrap_or_default();
        if origin.contains("Deletion") { continue; }
        let image_alt = card.select(&image_selector).next()
            .and_then(|x| x.value().attr("alt")).unwrap_or("").trim().to_string();
        let attr = |key: &str| card.value().attr(key).unwrap_or("").to_string();
        entries.push(SupremeEntry {
            c: category.to_string(), n: name, im: image_alt,
            y: attr("data-year"), e: attr("data-event"), o: origin,
            cl: class_re.captures(&text).and_then(|c| c.get(1)).map(|m| m.as_str().to_string()).unwrap_or_default(), v: value, t: tier, dm: attr("data-demand"),
        });
    }
    Ok((entries, cards))
}
fn parse_markdown_page(category: &str, markdown: &str) -> Result<(Vec<SupremeEntry>, usize), String> {
    let item_re = Regex::new(r"(?i)Image:\s*(.*?)\s*\|\s*(.*?)\s+Value\s*[-:–—]\s*([0-9][0-9,.]*)").unwrap();
    let tier_re = Regex::new(r"(?i)Image:\s*(.*?)\s*\|\s*(.*?)\s+Value\s*[-:–—]\s*([x×]\s*\d+\s+T\d+\s+[A-Za-z]+)").unwrap();
    let origin_re = Regex::new(r"(?i)Origin\s*[-:]\s*(.*?)(?:Change in Value|$)").unwrap();
    let demand_re = Regex::new(r"(?i)Demand\s*[-:]\s*(\d+)").unwrap();
    let mut entries = Vec::new();
    let mut cards = 0usize;
    let mut current: Option<SupremeEntry> = None;
    for line in markdown.lines() {
        if let Some(caps) = item_re.captures(line) {
            if let Some(entry) = current.take() { entries.push(entry); }
            cards += 1;
            let image_alt = caps.get(1).map(|m| m.as_str().trim()).unwrap_or("");
            let name = caps.get(2).map(|m| m.as_str().trim()).unwrap_or("");
            let value = caps.get(3).and_then(|m| parse_numeric_value(m.as_str()));
            current = Some(SupremeEntry {
                c: category.to_string(), n: name.to_string(), im: image_alt.to_string(),
                y: String::new(), e: String::new(), o: String::new(), cl: String::new(),
                v: value, t: String::new(), dm: String::new(),
            });
        } else if let Some(caps) = tier_re.captures(line) {
            if let Some(entry) = current.take() { entries.push(entry); }
            cards += 1;
            current = Some(SupremeEntry {
                c: category.to_string(),
                n: caps.get(2).map(|m| m.as_str().trim()).unwrap_or("").to_string(),
                im: caps.get(1).map(|m| m.as_str().trim()).unwrap_or("").to_string(),
                y: String::new(), e: String::new(), o: String::new(), cl: String::new(),
                v: None, t: caps.get(3).map(|m| m.as_str().trim().to_string()).unwrap_or_default(), dm: String::new(),
            });
        } else if let Some(entry) = current.as_mut() {
            if let Some(caps) = origin_re.captures(line) {
                entry.o = caps.get(1).map(|m| m.as_str().trim().to_string()).unwrap_or_default();
                let year_re = Regex::new(r"(20\d{2})").unwrap();
                if let Some(year) = year_re.captures(&entry.o).and_then(|c| c.get(1)) {
                    entry.y = year.as_str().to_string();
                    entry.e = entry.o.split_whitespace().next().unwrap_or("").to_string();
                }
            }
            if let Some(caps) = demand_re.captures(line) {
                entry.dm = caps.get(1).map(|m| m.as_str().to_string()).unwrap_or_default();
            }
        }
    }
    if let Some(entry) = current { entries.push(entry); }
    Ok((entries, cards))
}
fn fetch_category(client: &reqwest::blocking::Client, category: &'static str)
    -> Result<(String, Vec<SupremeEntry>, usize), String> {
    let urls = [format!("{BASE}{category}"), format!("{BASE}{category}.php")];
    let mut last = String::new();
    for url in urls {
        match client.get(&url).send().and_then(|r| r.error_for_status()).and_then(|r| r.text()) {
            Ok(body) if body.len() > 1500 && body.contains("itemcolumn") => {
                let (entries, cards) = parse_page(category, &body)?;
                return Ok((category.to_string(), entries, cards));
            }
            Ok(_) => last = format!("{url}: response did not contain item cards"),
            Err(e) => last = format!("{url}: {e}"),
        }
    }

    // GitHub-hosted runners can be denied by the source site's edge firewall.
    // Try text and CORS relays; the in-game Luau scraper remains a fallback for clients.
    let encoded = format!("https://www.supremevalues.com/mm2/{category}")
        .replace(":", "%3A").replace("/", "%2F");
    let proxies = [
        format!("https://r.jina.ai/https://www.supremevalues.com/mm2/{category}"),
        format!("https://r.jina.ai/https://www.supremevalues.com/mm2/{category}.php"),
        format!("https://api.allorigins.win/raw?url={encoded}"),
        format!("https://corsproxy.io/?url={encoded}"),
    ];
    let mut proxy_errors = Vec::new();
    for proxy_url in proxies {
        match client.get(&proxy_url)
            .timeout(Duration::from_secs(10))
            .header("Accept", "text/plain,text/html,*/*")
            .header("X-Return-Format", "markdown")
            .send().and_then(|r| r.error_for_status()).and_then(|r| r.text()) {
            Ok(body) if body.len() > 1000 => {
                if body.contains("itemcolumn") {
                    let (entries, cards) = parse_page(category, &body)?;
                    if !entries.is_empty() { return Ok((category.to_string(), entries, cards)); }
                }
                let (entries, cards) = parse_markdown_page(category, &body)?;
                if !entries.is_empty() { return Ok((category.to_string(), entries, cards)); }
                proxy_errors.push(format!("{proxy_url}: no cards in response [{}]",
                    body.chars().take(100).collect::<String>().replace('\n', " ")));
            }
            Ok(_) => proxy_errors.push(format!("{proxy_url}: short response")),
            Err(error) => proxy_errors.push(format!("{proxy_url}: {error}")),
        }
    }
    Err(format!("{category}: direct fetch failed ({last}); proxies: {}", proxy_errors.join(" | ")))
}

fn fetch_all() -> Result<MappingFile, String> {
    let client = reqwest::blocking::Client::builder()
        .user_agent("Mozilla/5.0 (compatible; SupremeTradeChecker/0.2)")
        .timeout(Duration::from_secs(35)).build().map_err(|e| e.to_string())?;
    let mut entries = Vec::new();
    let mut category_counts = BTreeMap::new();
    let mut page_card_counts = BTreeMap::new();
    let mut failures = Vec::new();

    // Keep the number of simultaneous source/proxy requests low to avoid rate limits.
    for batch in CATEGORIES.chunks(4) {
        let handles: Vec<_> = batch.iter().map(|&category| {
            let client = client.clone();
            thread::spawn(move || fetch_category(&client, category))
        }).collect();
        for (&category, handle) in batch.iter().zip(handles) {
            match handle.join().map_err(|_| format!("{category}: fetch worker panicked"))? {
                Ok((name, mut parsed, cards)) => {
                    category_counts.insert(name.clone(), parsed.len());
                    page_card_counts.insert(name, cards);
                    if !matches!(category, "sets" | "evos" | "untradables") {
                        entries.append(&mut parsed);
                    }
                }
                Err(error) => {
                    if matches!(category, "sets" | "evos" | "untradables") {
                        category_counts.insert(category.to_string(), 0);
                        page_card_counts.insert(category.to_string(), 0);
                    } else {
                        failures.push(error);
                    }
                }
            }
        }
    }
    let mut missing = Vec::new();
    for (category, minimum) in MINIMUM {
        let count = *category_counts.get(*category).unwrap_or(&0);
        if count < *minimum { missing.push(format!("{category}: {count}/{minimum}")); }
    }
    if !failures.is_empty() || !missing.is_empty() {
        return Err(format!("Refusing to publish incomplete Supreme snapshot. Failed pages: [{}]. Below minimum: [{}].",
            failures.join(" | "), missing.join(", ")));
    }
    if entries.len() < 300 { return Err(format!("Only {} entries parsed; minimum is 300", entries.len())); }
    Ok(build(entries, category_counts, page_card_counts))
}

fn resolve<'a>(map: &'a MappingFile, item: &RequestedItem) -> Result<&'a SupremeEntry, &'static str> {
    let key = normalize(&item.name);
    let ids = map.by_name.get(&key).or_else(|| map.by_image_alt.get(&key)).ok_or("not_found")?;
    let mut candidates: Vec<&SupremeEntry> = ids.iter().filter_map(|id| map.entries.get(*id)).collect();
    if let Some(want_chroma) = item.chroma { candidates.retain(|entry| is_chroma(entry) == want_chroma); }
    if candidates.len() != 1 { return Err(if candidates.is_empty() { "not_found" } else { "ambiguous" }); }
    Ok(candidates[0])
}
fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("fetch") if args.len() == 3 => {
            let map = fetch_all()?;
            let json = serde_json::to_string(&map).map_err(|e| e.to_string())?;
            fs::write(&args[2], json).map_err(|e| e.to_string())?;
            println!("Published snapshot data: {} entries across {} categories", map.entry_count, map.category_counts.len());
        }
        Some("build") if args.len() == 4 => {
            let raw = fs::read_to_string(&args[2]).map_err(|e| e.to_string())?;
            let input: InputFile = serde_json::from_str(&raw).map_err(|e| format!("invalid input JSON: {e}"))?;
            if input.schema_version != 1 {
                return Err(format!("unsupported export schema_version {}; expected 1", input.schema_version));
            }
            if input.entries.is_empty() {
                return Err("export contains no Supreme entries".into());
            }
            let mut derived_counts = BTreeMap::<String, usize>::new();
            for (index, entry) in input.entries.iter().enumerate() {
                let category = entry.c.trim().to_ascii_lowercase();
                if normalize(&entry.n).is_empty() {
                    return Err(format!("entry {} has an empty item name", index + 1));
                }
                if !CATEGORIES.contains(&category.as_str())
                    || matches!(category.as_str(), "sets" | "evos" | "untradables") {
                    return Err(format!("entry {} has unsupported value category '{}'", index + 1, entry.c));
                }
                if entry.v.as_deref().and_then(parse_numeric_value).is_none() && entry.t.trim().is_empty() {
                    return Err(format!("entry {} ('{}') has neither a valid numeric nor tier value", index + 1, entry.n));
                }
                *derived_counts.entry(category).or_insert(0) += 1;
            }
            let category_counts = if input.category_counts.is_empty() {
                derived_counts
            } else {
                input.category_counts
            };
            let mapping = build(input.entries, category_counts, input.page_card_counts);
            let json = serde_json::to_string_pretty(&mapping).map_err(|e| e.to_string())?;
            fs::write(&args[3], json).map_err(|e| e.to_string())?;
            println!("Built {} entries; name keys: {}; image-alt keys: {}", mapping.entry_count, mapping.by_name.len(), mapping.by_image_alt.len());
        }
        Some("total") if args.len() == 4 => {
            let map: MappingFile = serde_json::from_str(&fs::read_to_string(&args[2]).map_err(|e| e.to_string())?).map_err(|e| format!("invalid mapping: {e}"))?;
            let items: Vec<RequestedItem> = serde_json::from_str(&fs::read_to_string(&args[3]).map_err(|e| e.to_string())?).map_err(|e| format!("invalid items: {e}"))?;
            let mut lines = Vec::new(); let mut sum = 0.0; let mut complete = true;
            for item in items {
                match resolve(&map, &item) {
                    Ok(entry) => match entry.v.as_deref().and_then(|v| v.parse::<f64>().ok()) {
                        Some(value) => { let subtotal = value * item.quantity as f64; sum += subtotal;
                            lines.push(TotalLine { name: item.name, quantity: item.quantity, value_each: Some(value), subtotal: Some(subtotal), status: "ok" }); }
                        None => { complete = false; lines.push(TotalLine { name: item.name, quantity: item.quantity, value_each: None, subtotal: None, status: "tier_value" }); }
                    },
                    Err(status) => { complete = false; lines.push(TotalLine { name: item.name, quantity: item.quantity, value_each: None, subtotal: None, status }); }
                }
            }
            println!("{}", serde_json::to_string_pretty(&TotalReport { schema_version: 1, total: if complete { Some(sum) } else { None }, lines }).map_err(|e| e.to_string())?);
        }
        _ => return Err("Usage:\n  supreme-trade-core fetch <mapping.json>\n  supreme-trade-core build <supreme-export.json> <mapping.json>\n  supreme-trade-core total <mapping.json> <items.json>".into()),
    }
    Ok(())
}
fn main() { if let Err(error) = run() { eprintln!("supreme-trade-core: {error}"); process::exit(1); } }

#[cfg(test)]
mod tests {
    use super::*;
    fn entry(name: &str, category: &str, value: &str) -> SupremeEntry {
        SupremeEntry { c: category.into(), n: name.into(), im: String::new(), y: String::new(), e: String::new(), o: String::new(), cl: String::new(), v: Some(value.into()), t: String::new(), dm: String::new() }
    }
    #[test] fn markdown_proxy_parser_extracts_name_value_and_origin() {
        let markdown = "Image: Travelers Gun  | Traveler's Gun Value - 5,100\nOrigin - Halloween 2023 (Unboxed) Change in Value - (-100)\nDemand - 5 Rarity - 5";
        let (entries, cards) = parse_markdown_page("godlies", markdown).unwrap();
        assert_eq!(cards, 1);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].n, "Traveler's Gun");
        assert_eq!(entries[0].v.as_deref(), Some("5100"));
        assert_eq!(entries[0].y, "2023");
        assert_eq!(entries[0].dm, "5");
    }
    #[test] fn numeric_parser_handles_thousands_and_millions() {
        assert_eq!(parse_numeric_value("5,000").as_deref(), Some("5000"));
        assert_eq!(parse_numeric_value("1,000,000").as_deref(), Some("1000000"));
        assert_eq!(parse_numeric_value("0.25").as_deref(), Some("0.25"));
        assert_eq!(parse_numeric_value("35").as_deref(), Some("35"));
    }
    #[test] fn input_accepts_numeric_or_string_values() {
        let raw = r#"{"schema_version":1,"entries":[
            {"c":"godlies","n":"Traveler's Gun","v":1000000},
            {"c":"godlies","n":"Lightbringer","v":"5000"}
        ]}"#;
        let input: InputFile = serde_json::from_str(raw).unwrap();
        assert_eq!(input.entries[0].v.as_deref(), Some("1000000"));
        assert_eq!(input.entries[1].v.as_deref(), Some("5000"));
    }
    #[test] fn normalization_ignores_spaces_punctuation_and_case() { assert_eq!(normalize("  Lightbringer! "), "lightbringer"); }
    #[test] fn index_resolves_names() {
        let map = build(vec![entry("Lightbringer", "godlies", "45")], BTreeMap::new(), BTreeMap::new());
        let item = RequestedItem { name: "LIGHT BRINGER".into(), quantity: 2, chroma: Some(false) };
        assert_eq!(resolve(&map, &item).unwrap().v.as_deref(), Some("45"));
    }
    #[test] fn chroma_filter_disambiguates_same_name() {
        let map = build(vec![entry("Seer", "godlies", "1"), entry("Seer", "chromas", "15")], BTreeMap::new(), BTreeMap::new());
        let item = RequestedItem { name: "Seer".into(), quantity: 1, chroma: Some(true) };
        assert_eq!(resolve(&map, &item).unwrap().c, "chromas");
    }
    #[test] fn ambiguous_matches_are_not_guessed() {
        let map = build(vec![entry("Seer", "godlies", "1"), entry("Seer", "rares", "2")], BTreeMap::new(), BTreeMap::new());
        let item = RequestedItem { name: "Seer".into(), quantity: 1, chroma: None };
        assert_eq!(resolve(&map, &item).unwrap_err(), "ambiguous");
    }
}
