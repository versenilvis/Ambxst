use std::process::Command;
use std::io::Write;
use std::env;

pub fn colorpicker() {
    tokio::task::spawn_blocking(|| {
        let coords = match Command::new("slurp").arg("-p").output() {
            Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout).trim().to_string(),
            _ => return, // Cancelled or failed
        };

        if coords.is_empty() { return; }

        let grim_output = match Command::new("grim")
            .args(&["-g", &coords, "-t", "ppm", "-"])
            .output() {
            Ok(output) if output.status.success() => output.stdout,
            _ => return,
        };

        let magick_output = match execute_with_input(
            Command::new("magick").args(&["-", "-format", "%[fx:int(255*r)] %[fx:int(255*g)] %[fx:int(255*b)]", "info:-"]),
            &grim_output
        ) {
            Some(out) => out,
            None => return,
        };
        
        let rgb_parts: Vec<&str> = magick_output.split_whitespace().collect();
        if rgb_parts.len() != 3 { return; }

        let r: u8 = rgb_parts[0].parse().unwrap_or(0);
        let g: u8 = rgb_parts[1].parse().unwrap_or(0);
        let b: u8 = rgb_parts[2].parse().unwrap_or(0);

        let hex_color = format!("#{r:02X}{g:02X}{b:02X}");
        
        let mut tmp_dir = env::temp_dir();
        tmp_dir.push("color_picker_preview.png");
        
        let _ = Command::new("magick")
            .args(&["-size", "64x64", &format!("xc:{}", hex_color), tmp_dir.to_str().unwrap()])
            .status();

        // Copy to clipboard
        let mut child = Command::new("wl-copy")
            .stdin(std::process::Stdio::piped())
            .spawn()
            .expect("Failed to spawn wl-copy");
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(hex_color.as_bytes());
        }
        let _ = child.wait();

        // Notify
        let _ = Command::new("notify-send")
            .args(&[
                "Color Picked",
                &format!("{} copied to clipboard", hex_color),
                "-i", tmp_dir.to_str().unwrap(),
                "-a", "ColorPicker",
                "-u", "normal"
            ])
            .status();
    });
}

pub fn ocr(langs: Vec<String>) {
    tokio::task::spawn_blocking(move || {
        let coords = match Command::new("slurp").output() {
            Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout).trim().to_string(),
            _ => return,
        };

        if coords.is_empty() { return; }

        let grim_output = match Command::new("grim")
            .args(&["-g", &coords, "-"])
            .output() {
            Ok(output) if output.status.success() => output.stdout,
            _ => return,
        };

        let lang_str = if langs.is_empty() {
            "eng".to_string()
        } else {
            langs.join("+")
        };

        let tesseract_out = match execute_with_input(
            Command::new("tesseract").args(&["-", "-", "-l", &lang_str]),
            &grim_output
        ) {
            Some(out) => out,
            None => "".to_string(),
        };

        if !tesseract_out.is_empty() {
            let mut child = Command::new("wl-copy")
                .stdin(std::process::Stdio::piped())
                .spawn()
                .expect("Failed to spawn wl-copy");
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(tesseract_out.as_bytes());
            }
            let _ = child.wait();
            
            let _ = Command::new("notify-send")
                .args(&["OCR Result", "Text copied to clipboard", "-i", "edit-paste"])
                .status();
        } else {
            let _ = Command::new("notify-send")
                .args(&["OCR Result", "No text detected", "-u", "low", "-i", "dialogue-error"])
                .status();
        }
    });
}

fn execute_with_input(cmd: &mut Command, input: &[u8]) -> Option<String> {
    cmd.stdin(std::process::Stdio::piped());
    cmd.stdout(std::process::Stdio::piped());
    if let Ok(mut child) = cmd.spawn() {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(input);
        }
        if let Ok(output) = child.wait_with_output() {
            if output.status.success() {
                return Some(String::from_utf8_lossy(&output.stdout).trim().to_string());
            }
        }
    }
    None
}

pub fn qr_scan() {
    tokio::task::spawn_blocking(move || {
        let coords = match Command::new("slurp").output() {
            Ok(output) if output.status.success() => String::from_utf8_lossy(&output.stdout).trim().to_string(),
            _ => return,
        };

        if coords.is_empty() { return; }

        let grim_output = match Command::new("grim")
            .args(&["-g", &coords, "-"])
            .output() {
            Ok(output) if output.status.success() => output.stdout,
            _ => return,
        };

        let result = match execute_with_input(
            Command::new("zbarimg").args(&["-q", "--raw", "-"]),
            &grim_output
        ) {
            Some(out) => out,
            None => "".to_string(),
        };

        if !result.is_empty() {
            let mut child = Command::new("wl-copy")
                .stdin(std::process::Stdio::piped())
                .spawn()
                .expect("Failed to spawn wl-copy");
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(result.as_bytes());
            }
            let _ = child.wait();
            
            let _ = Command::new("notify-send")
                .args(&["QR/Barcode Result", "Content copied to clipboard", "-i", "qr-code"])
                .status();
        } else {
            let _ = Command::new("notify-send")
                .args(&["QR/Barcode Result", "No code detected", "-u", "low", "-i", "dialogue-error"])
                .status();
        }
    });
}
