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
    #[serde(default)] v: Option<String>,
    #[serde(default)] t: String,
    #[serde(default)] dm: String,
}
#[derive(Debug, Deserialize)]
struct InputFile {
    #[serde(default)] schema_version: u32,
    entries: Vec<SupremeEntry>,
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
    let value_re = Regex::new(r"(?i)Value\s*[-:]\s*([0-9][0-9,.]*)").unwrap();
    let tier_re = Regex::new(r"(?i)Value\s*[-:]\s*([x×]\s*\d+\s+T\d+\s+[A-Za-z]+)").unwrap();
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
        let value = value_re.captures(&text).and_then(|c| c.get(1))
            .and_then(|m| m.as_str().replace(',', "").parse::<f64>().ok())
            .filter(|v| *v > 0.0 && *v < 500000.0)
            .map(|v| {
                let mut s = format!("{v:.4}");
                while s.contains('.') && s.ends_with('0') { s.pop(); }
                if s.ends_with('.') { s.pop(); }
                s
            });
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
        thread::sleep(Duration::from_millis(200));
    }
    Err(last)
}
fn fetch_all() -> Result<MappingFile, String> {
    let client = reqwest::blocking::Client::builder()
        .user_agent("Mozilla/5.0 (compatible; SupremeTradeChecker/0.2)")
        .timeout(Duration::from_secs(25)).build().map_err(|e| e.to_string())?;
    let mut handles = Vec::new();
    for &category in CATEGORIES {
        let client = client.clone();
        handles.push(thread::spawn(move || fetch_category(&client, category)));
    }
    let mut entries = Vec::new();
    let mut category_counts = BTreeMap::new();
    let mut page_card_counts = BTreeMap::new();
    let mut failures = Vec::new();
    for handle in handles {
        match handle.join().map_err(|_| "fetch worker panicked".to_string())? {
            Ok((category, mut parsed, cards)) => {
                category_counts.insert(category.to_string(), parsed.len());
                page_card_counts.insert(category, cards);
                entries.append(&mut parsed);
            }
            Err(error) => failures.push(error),
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
            let mapping = build(input.entries, BTreeMap::new(), BTreeMap::new());
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
