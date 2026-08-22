use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AppUsage {
    pub count: u32,
    #[serde(rename = "lastUsed")]
    pub last_used: u64,
}

#[derive(Serialize, Clone, Debug)]
pub struct TopAppEntry {
    pub app_id: String,
    pub score: f32,
    pub count: u32,
    pub last_used: u64,
}

pub struct UsageTracker {
    file_path: PathBuf,
    usage_data: HashMap<String, AppUsage>,
}

impl UsageTracker {
    pub fn new() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());
        let data_dir = std::env::var("XDG_DATA_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| Path::new(&home).join(".local").join("share"));
        let file_path = data_dir.join("quickshell").join("usage.json");

        let mut tracker = Self {
            file_path,
            usage_data: HashMap::new(),
        };
        let _ = tracker.load();
        tracker.prune_old_entries();
        tracker
    }

    pub fn load(&mut self) -> Result<(), String> {
        if !self.file_path.exists() {
            if let Some(parent) = self.file_path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let _ = fs::write(&self.file_path, "{}");
            return Ok(());
        }

        let content = fs::read_to_string(&self.file_path).map_err(|e| e.to_string())?;
        self.usage_data = serde_json::from_str(&content).unwrap_or_default();
        Ok(())
    }

    pub fn save(&self) -> Result<(), String> {
        let content = serde_json::to_string_pretty(&self.usage_data).map_err(|e| e.to_string())?;
        fs::write(&self.file_path, content).map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn record_usage(&mut self, app_id: String) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);

        let entry = self.usage_data.entry(app_id).or_insert(AppUsage {
            count: 0,
            last_used: now,
        });
        entry.count += 1;
        entry.last_used = now;

        let _ = self.save();
    }

    pub fn get_usage_score(&self, app_id: &str, now: u64) -> f32 {
        let entry = match self.usage_data.get(app_id) {
            Some(e) => e,
            None => return 0.0,
        };

        let day_in_ms = 86_400_000.0;
        let days_since_last_use = (now.saturating_sub(entry.last_used) as f32) / day_in_ms;

        // time decay formula matching QML
        let time_boost = 200.0 * (-days_since_last_use / 7.0).exp();
        let frequency_score = ((entry.count + 1) as f32).ln() * 20.0;

        time_boost + frequency_score
    }

    pub fn get_top_apps(&self, limit: usize) -> Vec<TopAppEntry> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);

        let mut entries = Vec::new();
        for (app_id, data) in &self.usage_data {
            let score = self.get_usage_score(app_id, now);
            entries.push(TopAppEntry {
                app_id: app_id.clone(),
                score,
                count: data.count,
                last_used: data.last_used,
            });
        }

        entries.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
        entries.truncate(limit);
        entries
    }

    pub fn prune_old_entries(&mut self) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);

        let ninety_days_in_ms = 86_400_000 * 90;
        let initial_len = self.usage_data.len();

        self.usage_data.retain(|_, data| {
            now.saturating_sub(data.last_used) <= ninety_days_in_ms
        });

        if self.usage_data.len() != initial_len {
            let _ = self.save();
        }
    }
}
