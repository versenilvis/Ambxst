use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use serde::{Deserialize, Serialize};

use fff_search::file_picker::{FilePicker, FilePickerOptions, FuzzySearchOptions};
use fff_search::shared::{SharedFilePicker, SharedFrecency};
use fff_search::types::PaginationArgs;
use fff_search::QueryParser;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct FileHit {
    pub path: String,
    pub name: String,
    pub dir: String,
    pub score: i32,
}

#[derive(Clone)]
pub struct FileSearcher {
    shared_picker: SharedFilePicker,
    shared_frecency: SharedFrecency,
    indexing_started: Arc<AtomicBool>,
}

impl FileSearcher {
    pub fn new() -> Self {
        let searcher = Self {
            shared_picker: SharedFilePicker::default(),
            shared_frecency: SharedFrecency::default(),
            indexing_started: Arc::new(AtomicBool::new(false)),
        };
        searcher.start_indexing();
        searcher
    }

    pub fn start_indexing(&self) {
        if self.indexing_started.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_ok() {
            let shared_picker = self.shared_picker.clone();
            let shared_frecency = self.shared_frecency.clone();
            std::thread::spawn(move || {
                let home_dir = std::env::var("HOME").unwrap_or_else(|_| "/home/verse".to_string());
                let options = FilePickerOptions {
                    base_path: home_dir,
                    watch: true,
                    enable_home_dir_scanning: true,
                    ..Default::default()
                };
                if let Err(err) = FilePicker::new_with_shared_state(shared_picker, shared_frecency, options) {
                    eprintln!("failed to initialize file picker: {}", err);
                }
            });
        }
    }

    pub fn search(&self, query: &str, limit: usize) -> Vec<FileHit> {
        let trimmed = query.trim();
        if trimmed.is_empty() {
            return Vec::new();
        }

        self.start_indexing();

        let guard = match self.shared_picker.read() {
            Ok(guard) => guard,
            Err(_) => return Vec::new(),
        };

        let picker = match guard.as_ref() {
            Some(p) => p,
            None => return Vec::new(),
        };

        if picker.is_scan_active() {
            return Vec::new();
        }

        let parser = QueryParser::default();
        let parsed_query = parser.parse(trimmed);

        let cap = if limit == 0 { 50 } else { limit.min(50) };

        let options = FuzzySearchOptions {
            pagination: PaginationArgs {
                offset: 0,
                limit: cap,
            },
            ..Default::default()
        };

        let search_results = picker.fuzzy_search(&parsed_query, None, options);

        let mut hits = Vec::with_capacity(search_results.items.len());
        for (i, item) in search_results.items.iter().enumerate() {
            let abs_path = item.absolute_path(picker, &picker.base_path);
            let path = abs_path.to_string_lossy().to_string();
            let name = item.file_name(picker);
            let dir = abs_path
                .parent()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default();
            let score = search_results.scores.get(i).map(|s| s.total).unwrap_or(0);

            hits.push(FileHit {
                path,
                name,
                dir,
                score,
            });
        }

        hits
    }
}
