use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use tokio::process::Command;
use std::time::SystemTime;
use futures::future::join_all;

pub async fn generate_thumbnails(config_path: &str, cache_base_path: &str, fallback_path: Option<String>) -> bool {
    let config_p = Path::new(config_path);
    let cache_base_p = Path::new(cache_base_path);
    
    let mut wall_path: Option<PathBuf> = None;
    
    if let Ok(content) = fs::read_to_string(config_p) {
        if let Ok(config) = serde_json::from_str::<Value>(&content) {
            if let Some(wp) = config.get("wallPath").and_then(|v| v.as_str()) {
                if !wp.is_empty() {
                    wall_path = Some(PathBuf::from(shellexpand::tilde(wp).to_string()));
                }
            }
        }
    }
    
    if wall_path.is_none() {
        if let Some(fb) = fallback_path {
            wall_path = Some(PathBuf::from(shellexpand::tilde(&fb).to_string()));
        }
    }
    
    let wall_path = match wall_path {
        Some(p) if p.exists() => p,
        _ => return false,
    };
    
    let thumbnails_dir = cache_base_p.join("thumbnails");
    let _ = fs::create_dir_all(&thumbnails_dir);
    
    let mut files_to_process = Vec::new();
    
    let walker = walkdir::WalkDir::new(&wall_path).into_iter();
    for entry in walker.filter_map(Result::ok) {
        let path = entry.path();
        if path.is_file() {
            let name = path.file_name().unwrap_or_default().to_string_lossy();
            if name.starts_with('.') {
                continue;
            }
            
            // Check if parent dirs are hidden
            if let Ok(rel) = path.strip_prefix(&wall_path) {
                let mut hidden = false;
                for component in rel.components().take(rel.components().count().saturating_sub(1)) {
                    if component.as_os_str().to_string_lossy().starts_with('.') {
                        hidden = true;
                        break;
                    }
                }
                if hidden { continue; }
            }
            
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                let ext = ext.to_lowercase();
                if matches!(ext.as_str(), "mp4"|"webm"|"mov"|"avi"|"mkv"|"jpg"|"jpeg"|"png"|"webp"|"tif"|"tiff"|"bmp"|"gif") {
                    
                    let rel = path.strip_prefix(&wall_path).unwrap();
                    let thumb_name = format!("{}.jpg", name);
                    let thumb_path = thumbnails_dir.join(rel.parent().unwrap()).join(thumb_name);
                    
                    let needs_thumb = if !thumb_path.exists() {
                        true
                    } else {
                        let file_mtime = fs::metadata(&path).and_then(|m| m.modified()).unwrap_or(SystemTime::UNIX_EPOCH);
                        let thumb_mtime = fs::metadata(&thumb_path).and_then(|m| m.modified()).unwrap_or(SystemTime::UNIX_EPOCH);
                        file_mtime > thumb_mtime
                    };
                    
                    if needs_thumb {
                        files_to_process.push((path.to_path_buf(), thumb_path, ext));
                    }
                }
            }
        }
    }
    
    if files_to_process.is_empty() {
        return true; // Already done
    }
    
    let mut futures = Vec::new();
    let semaphore = std::sync::Arc::new(tokio::sync::Semaphore::new(4));
    
    for (file_path, thumb_path, ext) in files_to_process {
        let sem = semaphore.clone();
        futures.push(tokio::spawn(async move {
            let _permit = sem.acquire().await.unwrap();
            let _ = fs::create_dir_all(thumb_path.parent().unwrap());
            
            let mut cmd = Command::new("convert"); // placeholder
            
            if matches!(ext.as_str(), "mp4"|"webm"|"mov"|"avi"|"mkv") {
                cmd = Command::new("ffmpeg");
                cmd.args(&["-y", "-i", file_path.to_str().unwrap(), "-ss", "00:00:01", "-vframes", "1", "-vf", "scale=140:140:force_original_aspect_ratio=increase,crop=140:140", "-q:v", "2", "-f", "image2", thumb_path.to_str().unwrap()]);
            } else if ext == "gif" {
                cmd = Command::new("ffmpeg");
                cmd.args(&["-y", "-i", file_path.to_str().unwrap(), "-vframes", "1", "-vf", "scale=140:140:force_original_aspect_ratio=increase,crop=140:140", "-q:v", "2", "-f", "image2", thumb_path.to_str().unwrap()]);
            } else {
                cmd = Command::new("convert");
                cmd.args(&[file_path.to_str().unwrap(), "-resize", "140x140^", "-gravity", "center", "-extent", "140x140", "-quality", "85", thumb_path.to_str().unwrap()]);
            }
            
            let _ = tokio::time::timeout(std::time::Duration::from_secs(30), cmd.output()).await;
        }));
    }
    
    join_all(futures).await;
    true
}
