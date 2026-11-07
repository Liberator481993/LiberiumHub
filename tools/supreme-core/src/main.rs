use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, env, fs, process};

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
    entry_count: usize,
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
fn is_chroma(e: &SupremeEntry) -> bool {
    e.c.eq_ignore_ascii_case("chromas")
        || e.cl.to_ascii_lowercase().contains("chroma")
        || e.n.to_ascii_lowercase().starts_with("chroma ")
}
fn add(index: &mut BTreeMap<String, Vec<usize>>, key: String, id: usize) {
    if !key.is_empty() {
        let ids = index.entry(key).or_default();
        if ids.last().copied() != Some(id) { ids.push(id); }
    }
}
fn build(input: InputFile) -> MappingFile {
    let mut by_name = BTreeMap::new();
    let mut by_image_alt = BTreeMap::new();
    for (id, entry) in input.entries.iter().enumerate() {
        add(&mut by_name, normalize(&entry.n), id);
        let alt = normalize(&entry.im);
        if !alt.is_empty() && alt != normalize(&entry.n) {
            add(&mut by_image_alt, alt, id);
        }
    }
    MappingFile {
        schema_version: 1,
        source: "Supreme Values MM2 export".into(),
        entry_count: input.entries.len(),
        entries: input.entries,
        by_name,
        by_image_alt,
    }
}
fn resolve<'a>(map: &'a MappingFile, item: &RequestedItem) -> Result<&'a SupremeEntry, &'static str> {
    let key = normalize(&item.name);
    let ids = map.by_name.get(&key).or_else(|| map.by_image_alt.get(&key)).ok_or("not_found")?;
    let mut candidates: Vec<&SupremeEntry> = ids.iter().filter_map(|id| map.entries.get(*id)).collect();
    if let Some(want_chroma) = item.chroma {
        candidates.retain(|entry| is_chroma(entry) == want_chroma);
    }
    if candidates.len() != 1 { return Err(if candidates.is_empty() { "not_found" } else { "ambiguous" }); }
    Ok(candidates[0])
}
fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("build") if args.len() == 4 => {
            let raw = fs::read_to_string(&args[2]).map_err(|e| e.to_string())?;
            let input: InputFile = serde_json::from_str(&raw).map_err(|e| format!("invalid input JSON: {e}"))?;
            let mapping = build(input);
            let json = serde_json::to_string_pretty(&mapping).map_err(|e| e.to_string())?;
            fs::write(&args[3], json).map_err(|e| e.to_string())?;
            println!("Built {} entries; name keys: {}; image-alt keys: {}", mapping.entry_count, mapping.by_name.len(), mapping.by_image_alt.len());
        }
        Some("total") if args.len() == 4 => {
            let map_raw = fs::read_to_string(&args[2]).map_err(|e| e.to_string())?;
            let items_raw = fs::read_to_string(&args[3]).map_err(|e| e.to_string())?;
            let map: MappingFile = serde_json::from_str(&map_raw).map_err(|e| format!("invalid mapping: {e}"))?;
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
        _ => return Err("Usage:\n  supreme-trade-core build <supreme-export.json> <mapping.json>\n  supreme-trade-core total <mapping.json> <items.json>".into()),
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
        let map = build(InputFile { schema_version: 1, entries: vec![entry("Lightbringer", "godlies", "45")] });
        let item = RequestedItem { name: "LIGHT BRINGER".into(), quantity: 2, chroma: Some(false) };
        assert_eq!(resolve(&map, &item).unwrap().v.as_deref(), Some("45"));
    }
    #[test]
    fn chroma_filter_disambiguates_same_name() {
        let map = build(InputFile { schema_version: 1, entries: vec![entry("Seer", "godlies", "1"), entry("Seer", "chromas", "15")] });
        let item = RequestedItem { name: "Seer".into(), quantity: 1, chroma: Some(true) };
        assert_eq!(resolve(&map, &item).unwrap().c, "chromas");
    }
    #[test]
    fn ambiguous_matches_are_not_guessed() {
        let map = build(InputFile { schema_version: 1, entries: vec![entry("Seer", "godlies", "1"), entry("Seer", "rares", "2")] });
        let item = RequestedItem { name: "Seer".into(), quantity: 1, chroma: None };
        assert_eq!(resolve(&map, &item).unwrap_err(), "ambiguous");
    }
}
