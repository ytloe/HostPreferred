// 文件路径: rust/src/api/io.rs

use anyhow::{anyhow, Context, Result};
use flutter_rust_bridge::frb;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use crate::api::models::OptimizationTarget; // 引入枚举

const BACKUP_HOSTS_FILENAME: &str = "hosts.bak.hostpreferred";

/// 获取系统 hosts 文件和备份文件的路径
fn get_paths() -> Result<(PathBuf, PathBuf)> {
    let system_root = std::env::var("SystemRoot")
        .context("未能获取 SystemRoot 环境变量, 请确保在 Windows 系统上运行")?;
    let mut hosts_path = PathBuf::from(system_root);
    hosts_path.push("System32/drivers/etc/hosts");
    let backup_path = hosts_path.with_file_name(BACKUP_HOSTS_FILENAME);
    Ok((hosts_path, backup_path))
}

/// [FRB] 获取 hosts 文件所在的目录路径，供 UI 调用
#[frb(sync)]
pub fn get_hosts_dir() -> Result<String> {
    let (hosts_path, _) = get_paths()?;
    if let Some(dir) = hosts_path.parent() {
        Ok(dir.to_string_lossy().into_owned())
    } else {
        anyhow::bail!("无法获取 hosts 文件的父目录");
    }
}

/// [FRB] 备份当前的 hosts 文件
pub fn save_current_hosts() -> Result<String> {
    let (hosts_path, backup_path) = get_paths()?;
    if !hosts_path.exists() {
        anyhow::bail!("系统 Hosts 文件不存在于: {:?}", hosts_path);
    }
    let content = fs::read_to_string(&hosts_path)
        .map_err(|e| anyhow!("读取 Hosts 文件失败: {}", e))?;
    fs::write(&backup_path, &content)
        .map_err(|e| anyhow!("写入备份文件失败: {}", e))?;
    Ok(backup_path.to_string_lossy().into_owned())
}

/// [FRB]【新功能】从备份文件还原 hosts
#[frb]
pub fn revert_hosts() -> Result<String> {
    let (hosts_path, backup_path) = get_paths()?;
    if !backup_path.exists() {
        anyhow::bail!("备份文件 {:?} 不存在，无法还原。", backup_path);
    }
    let content = fs::read_to_string(&backup_path)
        .map_err(|e| anyhow!("读取备份文件失败: {}", e))?;
    fs::write(&hosts_path, &content)
        .map_err(|e| anyhow!("写入 Hosts 文件失败，请尝试以管理员权限运行: {}", e))?;
    Ok("Hosts 文件已成功从备份还原。".to_string())
}

/// 【新格式】智能更新 hosts 文件，为不同目标创建独立区块
pub fn update_hosts_file(target: OptimizationTarget, optimized_hosts: &Vec<(String, String)>) -> Result<()> {
    let (hosts_path, _) = get_paths()?;
    let file = File::open(&hosts_path).context("无法打开 hosts 文件进行读取")?;
    let reader = BufReader::new(file);
    let lines: Vec<String> = reader.lines().collect::<Result<_, _>>()?;

    // 根据目标确定区块的标记
    let (start_marker, end_marker) = match target {
        OptimizationTarget::GitHub => ("# == Github ==", "# ========="),
        OptimizationTarget::Cloudflare => ("# == Cloudflare ==", "# ============"),
        OptimizationTarget::NexusMods => ("# == Nexusmods ==", "# ============"),
    };

    let mut new_lines = Vec::new();
    let mut in_target_block = false;

    // 1. 遍历旧文件内容，移除当前目标的旧区块
    for line in lines.iter() {
        if line.trim() == start_marker {
            in_target_block = true;
            continue; // 丢弃旧的开始标记
        }
        if line.trim() == end_marker && in_target_block {
            in_target_block = false;
            continue; // 丢弃旧的结束标记
        }
        if in_target_block {
            continue; // 丢弃旧区块内的所有行
        }
        // 保留所有不相关的行
        new_lines.push(line.clone());
    }
    
    // 2. 在文件末尾追加新区块
    if !optimized_hosts.is_empty() {
        new_lines.push(String::new()); // 添加一个空行以作分隔
        new_lines.push(start_marker.to_string());
        for (domain, ip_str) in optimized_hosts {
            println!("[HostPreferred] 新增/更新 {} -> {}", domain, ip_str);
            new_lines.push(format!("{} {}", ip_str, domain));
        }
        new_lines.push(end_marker.to_string());
    }

    // 3. 将更新后的内容写回 hosts 文件
    let mut file = OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(&hosts_path)
        .context("无法以写入模式打开 hosts 文件。请尝试以管理员权限运行本程序。")?;

    for line in new_lines {
        writeln!(file, "{}", line)?;
    }

    Ok(())
}

/// 这是一个未被优选流程使用，但可能被FRB引用的辅助函数。
/// 为了安全起见，我们保留它。
pub fn save_content_to_file(filename: String, content: String) -> Result<String> {
    let (hosts_path, _) = get_paths()?;
    let target_path = hosts_path.with_file_name(filename);
    fs::write(&target_path, content)
        .map_err(|e| anyhow!("写入文件 {:?} 失败: {}", &target_path, e))?;
    Ok(target_path.to_string_lossy().into_owned())
}