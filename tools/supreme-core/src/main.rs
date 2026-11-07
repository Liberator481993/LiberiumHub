use regex::Regex;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    env, fs,
    process,
    time::{SystemTime, UNIX_EPOCH},
};

const CATEGORIES: &[&str] = &[
    "sets", "uniques", "evos", "ancients", "vintages", "chromas", "godlies",
    "legendaries", "rares", "uncommons", "commons", "pets", "misc", "untradables",
];
const VALUE_CATEGORIES: &[&str] = &[
    "uniques", "ancients", "vintages", "chromas", "godlies", "legendaries",
    "rares", "uncommons", "commons", "pets", "misc",
];
const MINIMUM: &[(&str, usize)] = &[
    ("godlies", 80), ("chromas", 30), ("commons", 150), ("uncommons", 100),
    ("rares", 80), ("legendaries", 40), ("ancients", 8), ("pets", 40),
    ("uniques", 1),
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
    #[serde(default)] entries: Vec<SupremeEntry>,
}

#[derive(Debug, Serialize, Deserialize)]
struct MappingFile {
    schema_version: u32,
    source: String,
    generated_at_unix: u64,
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
    name: String,
    quantity: u64,
    value_each: Option<f64>,
    subtotal: Option<f64>,
    status: &'static str,
}
#[derive(Debug, Serialize)]
struct TotalReport {
    schema_version: u32,
    total: Option<f64>,
    lines: Vec<TotalLine>,
}

fn normalize(input: &str) -> String {
    input.chars().flat_map(char::to_lowercase).filter(|c| c.is_alphanumeric()).collect()
}
fn is_chroma(entry: &SupremeEntry) -> bool {
    entry.c.eq_ignore_ascii_case("chromas")
        || entry.cl.to_ascii_lowercase().contains("chroma")
        || entry.n.to_ascii_lowercase().starts_with("chroma ")
}
fn add(index: &mut BTreeMap<String, Vec<usize>>, key: String, id: usize) {
    if !key.is_empty() {
        let ids = index.entry(key).or_default();
        if ids.last().copied() != Some(id) { ids.push(id); }
    }
}
fn now_unix() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs()
}
fn build(entries: Vec<SupremeEntry>, category_counts: BTreeMap<String, usize>, page_card_counts: BTreeMap<String, usize>) -> MappingFile {
    let mut by_name = BTreeMap::new();
    let mut by_image_alt = BTreeMap::new();
    for (id, entry) in entries.iter().enumerate() {
        add(&mut by_name, normalize(&entry.n), id);
        let alt = normalize(&entry.im);
        if !alt.is_empty() && alt != normalize(&entry.n) {
            add(&mut by_image_alt, alt, id);
        }
    }
    MappingFile {
        schema_version: 1,
        source: "Supreme Values MM2".into(),
        generated_at_unix: now_unix(),
        entry_count: entries.len(),
        category_counts,
        page_card_counts,
        entries,
        by_name,
        by_image_alt,
    }
}
fn text_of(element: scraper::ElementRef<'_>) -> String {
    element.text().collect::<Vec<_>>().join(" ").split_whitespace().collect::<Vec<_>>().join(" ")
}
fn selector(value: &str) -> Selector {
    Selector::parse(value).unwrap_or_else(|_| panic!("invalid CSS selector: {value}"))
}
fn parse_category(category: &str, html: &str) -> (usize, Vec<SupremeEntry>) {
    let document = Html::parse_document(html);
    let item_selector = selector("div.itemcolumn");
    let name_selector = selector(".itemhead");
    let origin_selector = selector(".itemorigin");
    let image_selector = selector("img[alt]");
    let value_re = Regex::new(r"(?i)\bValue\s*[-–:]\s*([0-9][0-9,]*(?:\.[0-9]+)?)").unwrap();
    let tier_re = Regex::new(r"(?i)\bValue\s*[-–:]\s*([x×]\s*[0-9]+\s+T[0-9]+\s+[A-Za-z]+)").unwrap();
    let class_re = Regex::new(r"(?i)\bClass\s*[-–:]\s*([A-Za-z]+)").unwrap();
    let demand_re = Regex::new(r"(?i)\bDemand\s*[-–:]\s*([0-9]+)").unwrap();

    let mut entries = Vec::new();
    let mut cards = 0;
    for card in document.select(&item_selector) {
        cards += 1;
        let card_text = text_of(card);
        let name = card.select(&name_selector).next().map(text_of).unwrap_or_default();
        if name.is_empty() { continue; }

        let tier = tier_re.captures(&card_text).and_then(|c| c.get(1))
            .map(|m| m.as_str().trim().to_string()).unwrap_or_default();
        let mut amount = value_re.captures(&card_text).and_then(|c| c.get(1))
            .and_then(|m| m.as_str().replace(',', "").parse::<f64>().ok());
        if amount.is_none() {
            amount = card.value().attr("data-value").and_then(|v| v.parse::<f64>().ok())
                .filter(|v| *v > 0.0);
        }
        if amount.is_none() && tier.is_empty() { continue; }
        if amount.map(|v| v >= 500_000.0).unwrap_or(false) { continue; }

        let origin = card.select(&origin_selector).next().map(text_of).unwrap_or_default();
        if origin.to_ascii_lowercase().contains("deletion") { continue; }
        let image_alt = card.select(&image_selector).next()
            .and_then(|img| img.value().attr("alt")).unwrap_or("").trim().to_string();
        let year = card.value().attr("data-year").unwrap_or("").to_string();
        let event = card.value().attr("data-event").unwrap_or("").to_string();
        let class = class_re.captures(&card_text).and_then(|c| c.get(1))
            .map(|m| m.as_str().to_string()).unwrap_or_default();
        let demand = demand_re.captures(&card_text).and_then(|c| c.get(1))
            .map(|m| m.as_str().to_string()).unwrap_or_default();

        entries.push(SupremeEntry {
            c: category.to_string(),
            n: name,
            im: image_alt,
            y: year,
            e: event,
            o: origin,
            cl: class,
            v: amount.map(|v| {
                let mut value = format!("{v:.4}");
                while value.contains('.') && value.ends_with('0') { value.pop(); }
                if value.ends_with('.') { value.pop(); }
                value
            }),
            t: tier,
            dm: demand,
        });
    }
    (cards, entries)
}
fn fetch_html(client: &reqwest::blocking::Client, category: &str) -> Result<String, String> {
    let urls = [
        format!("https://supremevalues.com/mm2/{category}"),
        format!("https://www.supremevalues.com/mm2/{category}"),
    ];
    let mut errors = Vec::new();
    for url in urls {
        match client.get(&url).send() {
            Ok(response) => {
                if !response.status().is_success() {
                    errors.push(format!("{url}: HTTP {}", response.status()));
                    continue;
                }
                match response.text() {
                    Ok(body) if body.len() > 1500 && body.contains("Supreme") => return Ok(body),
                    Ok(_) => errors.push(format!("{url}: empty or unexpected HTML")),
                    Err(error) => errors.push(format!("{url}: {error}")),
                }
            }
            Err(error) => errors.push(format!("{url}: {error}")),
        }
    }
    Err(errors.join("; "))
}
fn refresh() -> Result<MappingFile, String> {
    let client = reqwest::blocking::Client::builder()
        .user_agent("Mozilla/5.0 (compatible; SupremeTradeChecker/1.0)")
        .timeout(std::time::Duration::from_secs(30))
        .build().map_err(|e| e.to_string())?;
    let mut all_entries = Vec::new();
    let mut category_counts = BTreeMap::new();
    let mut page_card_counts = BTreeMap::new();
    let mut failures = Vec::new();
    for category in CATEGORIES {
        let html = match fetch_html(&client, category) {
            Ok(value) => value,
            Err(error) => { failures.push(format!("{category}: {error}")); continue; }
        };
        let (cards, mut entries) = parse_category(category, &html);
        page_card_counts.insert((*category).to_string(), cards);
        if VALUE_CATEGORIES.contains(category) {
            let count = entries.len();
            category_counts.insert((*category).to_string(), count);
            if let Some((_, minimum)) = MINIMUM.iter().find(|(name, _)| name == category) {
                if count < *minimum {
                    failures.push(format!("{category}: parsed {count} valued cards, expected at least {minimum} (page cards: {cards})"));
                }
            }
            all_entries.append(&mut entries);
        } else if cards == 0 {
            failures.push(format!("{category}: page loaded but no item cards were found"));
        }
    }
    if !failures.is_empty() {
        return Err(format!("Supreme refresh rejected; no partial mapping was written:\n{}", failures.join("\n")));
    }
    if all_entries.len() < 300 {
        return Err(format!("Supreme refresh rejected: only {} entries parsed (minimum 300)", all_entries.len()));
    }
    Ok(build(all_entries, category_counts, page_card_counts))
}
fn resolve<'a>(map: &'a MappingFile, item: &RequestedItem) -> Result<&'a SupremeEntry, &'static str> {
    let key = normalize(&item.name);
    let ids = map.by_name.get(&key).or_else(|| map.by_image_alt.get(&key)).ok_or("not_found")?;
    let mut candidates: Vec<&SupremeEntry> = ids.iter().filter_map(|id| map.entries.get(*id)).collect();
    if let Some(want_chroma) = item.chroma {
        candidates.retain(|entry| is_chroma(entry) == want_chroma);
    }
    if candidates.len() != 1 {
        return Err(if candidates.is_empty() { "not_found" } else { "ambiguous" });
    }
    Ok(candidates[0])
}
fn read_mapping(path: &str) -> Result<MappingFile, String> {
    let raw = fs::read_to_string(path).map_err(|e| e.to_string())?;
    serde_json::from_str(&raw).map_err(|e| format!("invalid mapping JSON: {e}"))
}
fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("refresh") if args.len() == 3 => {
            let mapping = refresh()?;
            let json = serde_json::to_string_pretty(&mapping).map_err(|e| e.to_string())?;
            fs::write(&args[2], json).map_err(|e| e.to_string())?;
            println!("Published dataset prepared: {} entries across {} categories (schema v{}).",
                mapping.entry_count, mapping.category_counts.len(), mapping.schema_version);
        }
        Some("build") if args.len() == 4 => {
            let raw = fs::read_to_string(&args[2]).map_err(|e| e.to_string())?;
            let input: InputFile = serde_json::from_str(&raw).map_err(|e| format!("invalid input JSON: {e}"))?;
            let mapping = build(input.entries, BTreeMap::new(), BTreeMap::new());
            let json = serde_json::to_string_pretty(&mapping).map_err(|e| e.to_string())?;
            fs::write(&args[3], json).map_err(|e| e.to_string())?;
            println!("Built {} entries; name keys: {}; image-alt keys: {}",
                mapping.entry_count, mapping.by_name.len(), mapping.by_image_alt.len());
        }
        Some("total") if args.len() == 4 => {
            let map = read_mapping(&args[2])?;
            let items_raw = fs::read_to_string(&args[3]).map_err(|e| e.to_string())?;
            let items: Vec<RequestedItem> = serde_json::from_str(&items_raw).map_err(|e| format!("invalid items: {e}"))?;
            let mut lines = Vec::new();
            let mut sum = 0.0;
            let mut complete = true;
            for item in items {
                match resolve(&map, &item) {
                    Ok(entry) => match entry.v.as_deref().and_then(|v| v.parse::<f64>().ok()) {
                        Some(value) => {
                            let subtotal = value * item.quantity as f64;
                            sum += subtotal;
                            lines.push(TotalLine { name: item.name, quantity: item.quantity, value_each: Some(value), subtotal: Some(subtotal), status: "ok" });
                        }
                        None => { complete = false; lines.push(TotalLine { name: item.name, quantity: item.quantity, value_each: None, subtotal: None, status: "tier_value" }); }
                    },
                    Err(status) => { complete = false; lines.push(TotalLine { name: item.name, quantity: item.quantity, value_each: None, subtotal: None, status }); }
                }
            }
            let report = TotalReport { schema_version: 1, total: if complete { Some(sum) } else { None }, lines };
            println!("{}", serde_json::to_string_pretty(&report).map_err(|e| e.to_string())?);
        }
        _ => return Err("Usage:\n  supreme-trade-core refresh <mapping.json>\n  supreme-trade-core build <supreme-export.json> <mapping.json>\n  supreme-trade-core total <mapping.json> <items.json>".into()),
    }
    Ok(())
}
fn main() {
    if let Err(error) = run() { eprintln!("supreme-trade-core: {error}"); process::exit(1); }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn entry(name: &str, category: &str, value: &str) -> SupremeEntry {
        SupremeEntry { c: category.into(), n: name.into(), im: String::new(), y: String::new(), e: String::new(), o: String::new(), cl: String::new(), v: Some(value.into()), t: String::new(), dm: String::new() }
    }
    #[test]
    fn normalization_ignores_spaces_punctuation_and_case() {
        assert_eq!(normalize("  Lightbringer! "), "lightbringer");
    }
    #[test]
    fn index_resolves_names_and_duplicate_quantities() {
        let map = build(vec![entry("Lightbringer", "godlies", "45")], BTreeMap::new(), BTreeMap::new());
        let item = RequestedItem { name: "LIGHT BRINGER".into(), quantity: 2, chroma: Some(false) };
        assert_eq!(resolve(&map, &item).unwrap().v.as_deref(), Some("45"));
    }
    #[test]
    fn chroma_filter_disambiguates_same_name() {
        let map = build(vec![entry("Seer", "godlies", "1"), entry("Seer", "chromas", "15")], BTreeMap::new(), BTreeMap::new());
        let item = RequestedItem { name: "Seer".into(), quantity: 1, chroma: Some(true) };
        assert_eq!(resolve(&map, &item).unwrap().c, "chromas");
    }
    #[test]
    fn ambiguous_matches_are_not_guessed() {
        let map = build(vec![entry("Seer", "godlies", "1"), entry("Seer", "rares", "2")], BTreeMap::new(), BTreeMap::new());
        let item = RequestedItem { name: "Seer".into(), quantity: 1, chroma: None };
        assert_eq!(resolve(&map, &item).unwrap_err(), "ambiguous");
    }
    #[test]
    fn parses_realistic_supreme_card_markup() {
        let html = r#"<html><div class="itemcolumn" data-year="2025" data-event="Halloween">
            <img alt="Travelers Gun"><div class="itemhead">Traveler's Gun</div>
            <div class="itemorigin">Halloween 2025 (Unboxed)</div>
            <span>Value - 5,100</span><span>Class - <b>Godly</b></span><span>Demand - 5</span>
        </div></html>"#;
        let (cards, entries) = parse_category("godlies", html);
        assert_eq!(cards, 1);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].n, "Traveler's Gun");
        assert_eq!(entries[0].v.as_deref(), Some("5100"));
        assert_eq!(entries[0].dm, "5");
        assert_eq!(entries[0].e, "Halloween");
    }
}
