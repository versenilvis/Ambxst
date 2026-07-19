use std::path::{Path, PathBuf};
use std::fs;
use serde::{Deserialize, Serialize};
use ini::Ini;
use std::sync::{Arc, Mutex};
use std::cmp::Ordering;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AppEntry {
    pub id: String,
    pub name: String,
    pub generic_name: Option<String>,
    pub exec: String,
    pub icon: Option<String>,
    pub keywords: Vec<String>,
    pub categories: Vec<String>,
    pub desktop_path: String,
    #[serde(skip)]
    pub search_string: String,
}

#[derive(Clone)]
pub struct AppSearcher {
    apps: Arc<Mutex<Vec<AppEntry>>>,
}

impl AppSearcher {
    pub fn new() -> Self {
        let searcher = Self {
            apps: Arc::new(Mutex::new(Vec::new())),
        };
        searcher.index_apps();
        searcher
    }

    pub fn index_apps(&self) {
        let mut apps = Vec::new();
        let home_dir = std::env::var("HOME").unwrap_or_default();
        let local_apps = format!("{}/.local/share/applications", home_dir);
        let dirs = vec![
            "/usr/share/applications".to_string(),
            "/usr/local/share/applications".to_string(),
            local_apps,
            "/var/lib/flatpak/exports/share/applications".to_string(),
            "/var/lib/snapd/desktop/applications".to_string(),
        ];

        let mut seen_ids = std::collections::HashSet::new();

        for dir in dirs {
            let path = Path::new(&dir);
            if !path.exists() { continue; }

            if let Ok(entries) = fs::read_dir(path) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.extension().map_or(false, |e| e == "desktop") {
                        if let Some(app) = parse_desktop_file(&p) {
                            if !seen_ids.contains(&app.id) {
                                seen_ids.insert(app.id.clone());
                                apps.push(app);
                            }
                        }
                    }
                }
            }
        }

        if let Ok(mut lock) = self.apps.lock() {
            *lock = apps;
        }
    }

    pub fn search(&self, query: &str) -> Vec<AppEntry> {
        let apps = match self.apps.lock() {
            Ok(lock) => lock.clone(),
            Err(_) => return Vec::new(),
        };

        if query.is_empty() {
            let mut sorted = apps;
            sorted.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
            return sorted;
        }

        let query_lower = query.to_lowercase();
        
        let mut scored_apps: Vec<(i32, AppEntry)> = apps.into_iter().filter_map(|app| {
            if let Some(score) = fff_match(&query_lower, &app.search_string) {
                Some((score, app))
            } else {
                None
            }
        }).collect();

        // Sort by highest score first, then alphabetically
        scored_apps.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.name.cmp(&b.1.name)));

        scored_apps.into_iter().map(|(_, app)| app).collect()
    }
}

fn parse_desktop_file(path: &Path) -> Option<AppEntry> {
    let conf = Ini::load_from_file(path).ok()?;
    let section = conf.section(Some("Desktop Entry"))?;

    let nodisplay = section.get("NoDisplay").unwrap_or("false").to_lowercase();
    if nodisplay == "true" {
        return None;
    }
    let hidden = section.get("Hidden").unwrap_or("false").to_lowercase();
    if hidden == "true" {
        return None;
    }
    let type_val = section.get("Type").unwrap_or("");
    if type_val != "Application" {
        return None;
    }

    let name = section.get("Name")?.to_string();
    let exec = section.get("Exec")?.to_string();
    let generic_name = section.get("GenericName").map(|s| s.to_string());
    let icon = section.get("Icon").map(|s| s.to_string());
    
    let keywords: Vec<String> = section.get("Keywords")
        .map(|s| s.split(';').map(|k| k.trim().to_string()).filter(|k| !k.is_empty()).collect())
        .unwrap_or_default();
        
    let categories: Vec<String> = section.get("Categories")
        .map(|s| s.split(';').map(|k| k.trim().to_string()).filter(|k| !k.is_empty()).collect())
        .unwrap_or_default();

    let id = path.file_name()?.to_string_lossy().to_string();

    let mut search_string = name.to_lowercase();
    if let Some(ref gn) = generic_name {
        search_string.push_str(" ");
        search_string.push_str(&gn.to_lowercase());
    }
    search_string.push_str(" ");
    search_string.push_str(&exec.to_lowercase());
    for k in &keywords {
        search_string.push_str(" ");
        search_string.push_str(&k.as_str().to_lowercase());
    }

    Some(AppEntry {
        id,
        name,
        generic_name,
        exec,
        icon,
        keywords,
        categories,
        desktop_path: path.to_string_lossy().to_string(),
        search_string,
    })
}

// FFF: Fast Fuzzy Finder matching algorithm
fn fff_match(query: &str, target: &str) -> Option<i32> {
    if query.is_empty() { return Some(0); }
    
    let mut q_chars = query.chars();
    let mut curr_q = q_chars.next()?;
    let mut score = 0;
    let mut consecutive = 0;
    let mut is_start_of_word = true;
    let mut first_match_index: i32 = -1;
    
    for (i, c) in target.chars().enumerate() {
        let current_char_is_start = is_start_of_word;
        is_start_of_word = c.is_whitespace() || c == '-' || c == '_';
        
        if c == curr_q {
            if first_match_index == -1 {
                first_match_index = i as i32;
            }
            score += 10 + consecutive * 5;
            if current_char_is_start {
                score += 20; // Bonus for start of word
            }
            consecutive += 1;
            if let Some(next_q) = q_chars.next() {
                curr_q = next_q;
            } else {
                return Some(score - first_match_index);
            }
        } else {
            consecutive = 0;
        }
    }
    None
}
