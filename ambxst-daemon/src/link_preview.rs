use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use url::Url;

#[derive(Serialize, Deserialize, Debug)]
pub struct LinkPreview {
    pub title: String,
    pub description: String,
    pub image: String,
    pub url: String,
    pub request_url: String,
    pub site_name: String,
    pub r#type: String,
    pub favicon: String,
    pub author: String,
    pub error: Option<String>,
}

impl Default for LinkPreview {
    fn default() -> Self {
        Self {
            title: String::new(),
            description: String::new(),
            image: String::new(),
            url: String::new(),
            request_url: String::new(),
            site_name: String::new(),
            r#type: "website".to_string(),
            favicon: String::new(),
            author: String::new(),
            error: None,
        }
    }
}

pub async fn fetch_preview(request_url: &str) -> LinkPreview {
    let mut preview = LinkPreview {
        request_url: request_url.to_string(),
        url: request_url.to_string(),
        ..Default::default()
    };

    if let Ok(parsed) = Url::parse(request_url) {
        preview.site_name = parsed.host_str().unwrap_or("").to_string();
    } else {
        preview.error = Some("Invalid URL".to_string());
        return preview;
    }

    let client = Client::builder()
        .timeout(Duration::from_secs(5))
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build()
        .unwrap_or_default();

    let res = match client.get(request_url).send().await {
        Ok(r) => r,
        Err(e) => {
            preview.error = Some(e.to_string());
            return preview;
        }
    };

    if !res.status().is_success() {
        preview.error = Some(format!("HTTP Error {}", res.status()));
        return preview;
    }
    
    // We only need the URL after redirects to resolve relative paths
    let final_url = res.url().to_string();
    let final_parsed = Url::parse(&final_url).ok();
    
    // Fetch first 500KB
    let mut html = String::new();
    if let Ok(bytes) = res.bytes().await {
        let chunk = &bytes[..std::cmp::min(bytes.len(), 500 * 1024)];
        html = String::from_utf8_lossy(chunk).to_string();
    }

    extract_metadata(&html, &mut preview);

    if preview.title.is_empty() {
        if let Some(title) = extract_tag(&html, "title") {
            preview.title = title;
        } else {
            preview.title = preview.site_name.clone();
        }
    }

    if let Some(parsed) = final_parsed {
        if preview.favicon.is_empty() {
            preview.favicon = format!("{}://{}/favicon.ico", parsed.scheme(), parsed.host_str().unwrap_or(""));
        } else if !preview.favicon.starts_with("http") {
            if let Ok(u) = parsed.join(&preview.favicon) {
                preview.favicon = u.to_string();
            }
        }

        if !preview.image.starts_with("http") && !preview.image.is_empty() {
            if let Ok(u) = parsed.join(&preview.image) {
                preview.image = u.to_string();
            }
        }
    }

    preview
}

fn extract_metadata(html: &str, preview: &mut LinkPreview) {
    // Very basic regex-less extraction for performance
    let parts: Vec<&str> = html.split("<meta ").collect();
    for part in parts.iter().skip(1) {
        if let Some(end) = part.find('>') {
            let tag = &part[..end];
            let content = extract_attr(tag, "content");
            if content.is_empty() { continue; }

            let property = extract_attr(tag, "property");
            let name = extract_attr(tag, "name");
            
            let key = if !property.is_empty() { property } else { name };

            match key.as_str() {
                "og:title" | "twitter:title" => if preview.title.is_empty() { preview.title = content },
                "og:description" | "twitter:description" | "description" => if preview.description.is_empty() { preview.description = content },
                "og:image" | "twitter:image" => if preview.image.is_empty() { preview.image = content },
                "og:site_name" => if preview.site_name.is_empty() || preview.site_name == Url::parse(&preview.url).unwrap().host_str().unwrap_or("") { preview.site_name = content },
                "og:type" => preview.r#type = content,
                _ => {}
            }
        }
    }

    // Favicon extraction
    let parts: Vec<&str> = html.split("<link ").collect();
    for part in parts.iter().skip(1) {
        if let Some(end) = part.find('>') {
            let tag = &part[..end];
            let rel = extract_attr(tag, "rel").to_lowercase();
            if rel.contains("icon") && preview.favicon.is_empty() {
                preview.favicon = extract_attr(tag, "href");
            }
        }
    }
}

fn extract_attr(tag: &str, attr: &str) -> String {
    let search = format!("{}=\"", attr);
    if let Some(start) = tag.find(&search) {
        let after = &tag[start + search.len()..];
        if let Some(end) = after.find('"') {
            return after[..end].to_string();
        }
    }
    
    // Check single quotes
    let search = format!("{}='", attr);
    if let Some(start) = tag.find(&search) {
        let after = &tag[start + search.len()..];
        if let Some(end) = after.find('\'') {
            return after[..end].to_string();
        }
    }
    
    String::new()
}

fn extract_tag(html: &str, tag_name: &str) -> Option<String> {
    let open = format!("<{}>", tag_name);
    let close = format!("</{}>", tag_name);
    if let Some(start) = html.find(&open) {
        let after = &html[start + open.len()..];
        if let Some(end) = after.find(&close) {
            return Some(after[..end].to_string());
        }
    }
    None
}
