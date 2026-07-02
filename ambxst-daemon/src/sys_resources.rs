use std::fs;
use std::path::Path;
use std::process::Command;
use serde::Serialize;
use sysinfo::{System, Disks};

#[derive(Serialize, Clone, Debug)]
pub struct CpuInfo {
    pub usage: f32,
    pub temp: i32,
}

#[derive(Serialize, Clone, Debug)]
pub struct RamInfo {
    pub usage: f32,
    pub total: u64,
    pub used: u64,
    pub available: u64,
}

#[derive(Serialize, Clone, Debug)]
pub struct GpuInfo {
    pub detected: bool,
    pub vendor: String,
    pub count: usize,
    pub usages: Vec<f32>,
    pub temps: Vec<i32>,
}

#[derive(Serialize, Clone, Debug)]
pub struct SystemStats {
    pub cpu: CpuInfo,
    pub ram: RamInfo,
    pub disk: std::collections::HashMap<String, f32>,
    pub disk_used: std::collections::HashMap<String, u64>,
    pub disk_total: std::collections::HashMap<String, u64>,
    pub gpu: GpuInfo,
}

pub struct SysMonitor {
    sys: System,
    gpu_vendor: String,
    gpu_count: usize,
    amd_cards: Vec<String>,
}

impl SysMonitor {
    pub fn new() -> Self {
        let mut sys = System::new_all();
        sys.refresh_all();

        let mut gpu_vendor = "none".to_string();
        let mut gpu_count = 0;
        let mut amd_cards = Vec::new();

        // check for nvidia
        if Command::new("nvidia-smi").stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).status().is_ok() {
            gpu_vendor = "nvidia".to_string();
            if let Ok(out) = Command::new("nvidia-smi")
                .args(["--query-gpu=count", "--format=csv,noheader,nounits"])
                .output()
            {
                if let Ok(s) = std::str::from_utf8(&out.stdout) {
                    if let Ok(val) = s.trim().parse::<usize>() {
                        gpu_count = val;
                    }
                }
            }
        } else {
            // check for amd
            if let Ok(entries) = fs::read_dir("/sys/class/drm") {
                for entry in entries.flatten() {
                    let name = entry.file_name().to_string_lossy().into_owned();
                    if name.starts_with("card") {
                        let path = format!("/sys/class/drm/{}/device/gpu_busy_percent", name);
                        if Path::new(&path).exists() {
                            amd_cards.push(name);
                        }
                    }
                }
            }
            if !amd_cards.is_empty() {
                amd_cards.sort();
                gpu_vendor = "amd".to_string();
                gpu_count = amd_cards.len();
            } else if Command::new("intel_gpu_top").arg("-h").stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null()).status().is_ok() {
                gpu_vendor = "intel".to_string();
                gpu_count = 1;
            }
        }

        Self {
            sys,
            gpu_vendor,
            gpu_count,
            amd_cards,
        }
    }

    pub fn get_cpu_temp(&self) -> i32 {
        // scan standard hwmon directories
        if let Ok(entries) = fs::read_dir("/sys/class/hwmon") {
            for entry in entries.flatten() {
                let path = entry.path();
                let name_path = path.join("name");
                if let Ok(name) = fs::read_to_string(name_path) {
                    let name_trimmed = name.trim();
                    if ["coretemp", "k10temp", "zenpower", "cpu_thermal", "x86_pkg_temp", "amd_energy"].contains(&name_trimmed) {
                        if let Ok(sub_entries) = fs::read_dir(&path) {
                            for sub_entry in sub_entries.flatten() {
                                let file_name = sub_entry.file_name().to_string_lossy().into_owned();
                                if file_name.starts_with("temp") && file_name.ends_with("_input") {
                                    if let Ok(val_str) = fs::read_to_string(sub_entry.path()) {
                                        if let Ok(val) = val_str.trim().parse::<i32>() {
                                            if val > 10000 && val < 120000 {
                                                return val / 1000;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // fallback to thermal zone
        if let Ok(entries) = fs::read_dir("/sys/class/thermal") {
            for entry in entries.flatten() {
                let path = entry.path();
                let file_name = entry.file_name().to_string_lossy().into_owned();
                if file_name.starts_with("thermal_zone") {
                    if let Ok(t_type) = fs::read_to_string(path.join("type")) {
                        if ["x86_pkg_temp", "cpu-thermal", "soc_thermal", "proc_thermal"].contains(&t_type.trim()) {
                            if let Ok(val_str) = fs::read_to_string(path.join("temp")) {
                                if let Ok(val) = val_str.trim().parse::<i32>() {
                                    if val > 1000 && val < 120000 {
                                        return val / 1000;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        -1
    }

    pub fn get_gpu_stats(&self) -> (Vec<f32>, Vec<i32>) {
        let mut usages = vec![0.0; self.gpu_count];
        let mut temps = vec![-1; self.gpu_count];

        if self.gpu_vendor == "nvidia" && self.gpu_count > 0 {
            if let Ok(out) = Command::new("nvidia-smi")
                .args(["--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"])
                .output()
            {
                if let Ok(s) = std::str::from_utf8(&out.stdout) {
                    for (i, line) in s.trim().split('\n').enumerate() {
                        if i >= self.gpu_count {
                            break;
                        }
                        let parts: Vec<&str> = line.split(',').collect();
                        if parts.len() >= 2 {
                            if let Ok(u) = parts[0].trim().parse::<f32>() {
                                usages[i] = u;
                            }
                            if let Ok(t) = parts[1].trim().parse::<i32>() {
                                temps[i] = t;
                            }
                        }
                    }
                }
            }
        } else if self.gpu_vendor == "amd" && self.gpu_count > 0 {
            for (i, card) in self.amd_cards.iter().enumerate() {
                if i >= self.gpu_count {
                    break;
                }
                // usage
                let p = format!("/sys/class/drm/{}/device/gpu_busy_percent", card);
                if let Ok(s) = fs::read_to_string(&p) {
                    if let Ok(u) = s.trim().parse::<f32>() {
                        usages[i] = u;
                    }
                }
                // temp
                let hwmon_base = format!("/sys/class/drm/{}/device/hwmon", card);
                if let Ok(entries) = fs::read_dir(hwmon_base) {
                    if let Some(Ok(entry)) = entries.into_iter().next() {
                        let t_path = entry.path().join("temp1_input");
                        if let Ok(s) = fs::read_to_string(t_path) {
                            if let Ok(t) = s.trim().parse::<i32>() {
                                temps[i] = t / 1000;
                            }
                        }
                    }
                }
            }
        }

        (usages, temps)
    }

    pub fn get_stats(&mut self, disks_to_monitor: &[String]) -> SystemStats {
        self.sys.refresh_cpu_usage();
        self.sys.refresh_memory();

        let cpu_usage = self.sys.global_cpu_info().cpu_usage();
        let cpu_temp = self.get_cpu_temp();

        let mem_total = self.sys.total_memory();
        let mem_available = self.sys.available_memory();
        let mem_used = mem_total.saturating_sub(mem_available);
        let ram_usage = if mem_total > 0 {
            (mem_used as f32 / mem_total as f32) * 100.0
        } else {
            0.0
        };

        let mut disk_map = std::collections::HashMap::new();
        let mut disk_used_map = std::collections::HashMap::new();
        let mut disk_total_map = std::collections::HashMap::new();
        let disks = Disks::new_with_refreshed_list();
        for disk in disks.list() {
            let mount = disk.mount_point().to_string_lossy().into_owned();
            if disks_to_monitor.is_empty() || disks_to_monitor.contains(&mount) {
                let total = disk.total_space();
                let available = disk.available_space();
                let used = total.saturating_sub(available);
                let usage = if total > 0 {
                    (used as f32 / total as f32) * 100.0
                } else {
                    0.0
                };
                disk_map.insert(mount.clone(), usage);
                disk_used_map.insert(mount.clone(), used);
                disk_total_map.insert(mount, total);
            }
        }

        let (gpu_usages, gpu_temps) = self.get_gpu_stats();

        SystemStats {
            cpu: CpuInfo {
                usage: cpu_usage,
                temp: cpu_temp,
            },
            ram: RamInfo {
                usage: ram_usage,
                total: mem_total,
                used: mem_used,
                available: mem_available,
            },
            disk: disk_map,
            disk_used: disk_used_map,
            disk_total: disk_total_map,
            gpu: GpuInfo {
                detected: self.gpu_vendor != "none",
                vendor: self.gpu_vendor.clone(),
                count: self.gpu_count,
                usages: gpu_usages,
                temps: gpu_temps,
            },
        }
    }
}
