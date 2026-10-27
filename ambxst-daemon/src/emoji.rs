use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use crate::app_search::fff_match;

#[derive(Deserialize, Debug)]
struct RawEmojiInfo {
    name: Option<String>,
    slug: Option<String>,
    group: Option<String>,
    #[serde(default)]
    skin_tone_support: bool,
    #[serde(default)]
    keywords: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct EmojiItem {
    pub emoji: String,
    pub name: String,
    pub slug: String,
    pub group: String,
    pub skin_tone_support: bool,
    #[serde(skip_serializing)]
    pub keywords: Vec<String>,
    #[serde(skip_serializing)]
    pub search_haystack: String,
}

pub struct EmojiManager {
    emojis: Vec<EmojiItem>,
    groups: HashMap<String, Vec<EmojiItem>>,
}

impl EmojiManager {
    pub fn new() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/verse".to_string());
        let candidate_paths = vec![
            PathBuf::from(format!("{}/Ambxst/assets/emojis.json", home)),
            PathBuf::from(format!("{}/.config/quickshell/assets/emojis.json", home)),
            PathBuf::from("assets/emojis.json"),
        ];

        let mut file_content = None;
        for p in candidate_paths {
            if p.exists() {
                if let Ok(content) = fs::read_to_string(&p) {
                    file_content = Some(content);
                    break;
                }
            }
        }

        let mut emojis = Vec::new();
        let mut groups: HashMap<String, Vec<EmojiItem>> = HashMap::new();

        if let Some(content) = file_content {
            if let Ok(raw_map) = serde_json::from_str::<HashMap<String, RawEmojiInfo>>(&content) {
                for (em, info) in raw_map {
                    let name = info.name.unwrap_or_default();
                    let slug = info.slug.unwrap_or_default();
                    let group = info.group.unwrap_or_else(|| "Other".to_string());
                    let kw_joined = info.keywords.join(" ").to_lowercase();
                    let search_haystack = format!("{} {} {} {}", name.to_lowercase(), slug.to_lowercase(), group.to_lowercase(), kw_joined);

                    let item = EmojiItem {
                        emoji: em,
                        name,
                        slug,
                        group: group.clone(),
                        skin_tone_support: info.skin_tone_support,
                        keywords: info.keywords,
                        search_haystack,
                    };

                    groups.entry(group).or_default().push(item.clone());
                    emojis.push(item);
                }
            }
        }

        Self { emojis, groups }
    }

    pub fn search(&self, query: &str, limit: usize) -> Vec<EmojiItem> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return Vec::new();
        }

        let terms: Vec<&str> = q.split_whitespace().collect();
        let mut scored: Vec<(i32, &EmojiItem)> = Vec::new();

        for item in &self.emojis {
            // direct character match
            if item.emoji == q {
                scored.push((10000, item));
                continue;
            }

            let name_lower = item.name.to_lowercase();
            let slug_lower = item.slug.to_lowercase();

            // exact name or slug match
            if name_lower == q || slug_lower == q {
                scored.push((5000, item));
                continue;
            }

            let mut match_all_terms = true;
            let mut total_score = 0;

            for &term in &terms {
                let mut term_score = 0;

                if name_lower.starts_with(term) {
                    term_score += 600;
                } else if name_lower.contains(term) {
                    term_score += 300;
                }

                if slug_lower.contains(term) {
                    term_score += 200;
                }

                for kw in &item.keywords {
                    let kw_low = kw.to_lowercase();
                    if kw_low == term {
                        term_score += 500;
                    } else if kw_low.starts_with(term) {
                        term_score += 250;
                    } else if kw_low.contains(term) {
                        term_score += 100;
                    }
                }

                // fallback to fuzzy match if no direct substring match in keywords/name
                if term_score == 0 {
                    if let Some(f_score) = fff_match(term, &item.search_haystack) {
                        term_score += f_score;
                    }
                }

                if term_score == 0 {
                    match_all_terms = false;
                    break;
                } else {
                    total_score += term_score;
                }
            }

            if match_all_terms && total_score > 0 {
                scored.push((total_score, item));
            }
        }

        scored.sort_by(|a, b| b.0.cmp(&a.0));
        scored.into_iter().take(limit).map(|(_, item)| item.clone()).collect()
    }

    pub fn get_all_grouped(&self) -> HashMap<String, Vec<EmojiItem>> {
        self.groups.clone()
    }

    #[allow(dead_code)]
    pub fn get_group(&self, group: &str) -> Vec<EmojiItem> {
        self.groups.get(group).cloned().unwrap_or_default()
    }
}
