// 文件路径: rust/src/api/optimizer.rs

use anyhow::{anyhow, Context, Result};
use futures::stream::{StreamExt, FuturesUnordered};
use once_cell::sync::Lazy;
use rand::random;
use reqwest::Client;
use serde::Deserialize;
use std::collections::HashMap;
use std::net::IpAddr;
use std::str::FromStr;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use surge_ping::{Client as PingClient, Config, PingIdentifier, PingSequence};
use tokio::time::timeout;

use crate::api::io::update_hosts_file;
use crate::api::models::OptimizationTarget;

// 创建一个全局的、懒加载的 reqwest 客户端，以确保 TLS 只初始化一次。
static HTTP_CLIENT: Lazy<Client> = Lazy::new(|| {
    reqwest::Client::new()
});

struct DomainList {
    core: Vec<&'static str>,
    optional: Vec<&'static str>,
}

fn get_domains_for_target(target: &OptimizationTarget) -> DomainList {
    match target {
        OptimizationTarget::GitHub => DomainList {
            core: vec![
                "github.com",
                "github.githubassets.com",
                "raw.githubusercontent.com",
                "avatars.githubusercontent.com",
            ],
            optional: vec![
                "avatars0.githubusercontent.com", 
                "avatars1.githubusercontent.com",
                "avatars2.githubusercontent.com", 
                "avatars3.githubusercontent.com",
                "avatars4.githubusercontent.com", 
                "avatars5.githubusercontent.com",
                "camo.githubusercontent.com", 
                "codeload.github.com",
                "desktop.githubusercontent.com", 
                // "assets-cdn.github.com",
                "gist.github.com", 
                "github.io", 
                "api.github.com",
                "live.github.com", 
                "media.githubusercontent.com",
                "central.github.com", 
                "cloud.githubusercontent.com",
                "user-images.githubusercontent.com", 
                "objects.githubusercontent.com",
                "ghcr.io", 
                "github.global.ssl.fastly.net",
            ],
        },
        OptimizationTarget::Cloudflare => DomainList {
            core: vec![
                "dash.cloudflare.com",
                "cloudflare.com",
                "one.one.one.one",
            ],
            optional: vec![
                "api.cloudflare.com",
                "cdnjs.cloudflare.com",
                "images.cloudflare.com",
                "workers.dev",
                "pages.dev",
            ],
        },
        OptimizationTarget::NexusMods => DomainList {
            core: vec![
                "www.nexusmods.com",
                "staticdelivery.nexusmods.com",
            ],
            optional: vec![
                "cf-files.nexusmods.com",
                "staticstats.nexusmods.com",
                "users.nexusmods.com",
            ],
        },
    }
}

/// DoH 响应中 Answer 字段的结构
#[derive(Debug, Clone, Deserialize)]
struct DohAnswer {
    // 【警告修复】直接使用 `name` 字段，并通过 #[allow(dead_code)] 宏
    // 来告诉编译器我们知道这个字段未被读取，这是最清晰的做法。
    #[allow(dead_code)]
    name: String,
    data: String,
}

/// 完整的 DoH 响应结构
#[derive(Debug, Clone, Deserialize)]
struct DohResponse {
    #[serde(rename = "Answer")]
    answer: Option<Vec<DohAnswer>>,
}

/// 并发地为每个域名轮询 DoH 服务器以解析 IP 地址。
async fn fetch_ips_via_doh(domains: Vec<&'static str>) -> Result<HashMap<String, Vec<IpAddr>>> {
    // 【恢复】使用完整的 DoH 服务器列表，以提高成功率
    let doh_servers: &[&str] = &[
        "https://doh.pub/dns-query",
        "https://dns.alidns.com/dns-query",
        "https://cloudflare-dns.com/dns-query",
        "https://dns.google/resolve",
    ];
    
    let mut domain_to_ips = HashMap::new();
    let mut tasks = FuturesUnordered::new();

    for &domain in domains.iter() {
        tasks.push(tokio::spawn(async move {
            for &server in doh_servers {
                let url = format!("{}?name={}&type=A", server, domain);
                let request_future = HTTP_CLIENT.get(&url).header("accept", "application/dns-json").send();

                match timeout(Duration::from_secs(2), request_future).await {
                    Ok(Ok(response)) => {
                        if let Ok(json) = response.json::<DohResponse>().await {
                            if let Some(answers) = json.answer {
                                let ips: Vec<IpAddr> = answers.into_iter()
                                    .filter_map(|ans| IpAddr::from_str(&ans.data).ok())
                                    .collect();
                                
                                if !ips.is_empty() {
                                    println!("[HostPreferred] DoH OK for {} via {}", domain, server);
                                    return Some((domain, ips));
                                }
                            }
                        }
                    },
                    Err(_) => {
                        println!("[HostPreferred] DoH TIMEOUT for {} via {}", domain, server);
                    },
                    Ok(Err(e)) => {
                        // 保留详细错误日志，这对于用户反馈问题很有帮助
                        println!("[HostPreferred] DoH FAILED for {} via {}: {:?}", domain, server, e);
                    }
                }
            }
            println!("[HostPreferred] All DoH servers FAILED for {}", domain);
            None
        }));
    }

    while let Some(join_result) = tasks.next().await {
        match join_result {
            Ok(Some((domain, ips))) => {
                domain_to_ips.insert(domain.to_string(), ips);
            }
            Ok(None) => {} // 任务正常失败
            Err(join_error) => {
                // 保留 Panic 日志，以防万一
                println!("[CRITICAL] A Tokio task PANICKED: {:?}", join_error);
            }
        }
    }
    
    Ok(domain_to_ips)
}

/// 对单个 IP 地址进行 Ping 测试，返回平均延迟。
async fn ping_ip(ip: IpAddr) -> Option<(IpAddr, Duration)> {
    let client = PingClient::new(&Config::default()).ok()?;
    let mut pinger = client.pinger(ip, PingIdentifier(random())).await;
    pinger.timeout(Duration::from_secs(1));
    let mut rtts = Vec::new();
    for i in 0..3 {
        if let Ok((_, rtt)) = pinger.ping(PingSequence(i), &[]).await {
            rtts.push(rtt);
        }
    }
    if rtts.is_empty() { None } else {
        let sum: Duration = rtts.iter().sum();
        Some((ip, sum / rtts.len() as u32))
    }
}

/// 主优化函数，暴露给 Flutter 调用。
pub async fn optimize_hosts(target: OptimizationTarget) -> Result<String> {
    let total_timeout = Duration::from_millis(10000);
    let domain_list = Arc::new(get_domains_for_target(&target));
    
    let best_ips = Arc::new(Mutex::new(HashMap::<String, (IpAddr, Duration)>::new()));

    let optimization_logic = async {
        let all_domains: Vec<_> = domain_list.core.iter().chain(domain_list.optional.iter()).cloned().collect();
        let domain_to_ips = fetch_ips_via_doh(all_domains).await?;
        
        let ping_tasks = FuturesUnordered::new();

        for (domain, ips) in domain_to_ips {
            let best_ips_clone = Arc::clone(&best_ips);
            ping_tasks.push(tokio::spawn(async move {
                let mut host_ping_tasks = FuturesUnordered::new();
                for ip in ips { host_ping_tasks.push(ping_ip(ip)); }

                let mut best_rtt_for_domain = Duration::from_secs(999);
                let mut best_ip_for_domain = None;

                while let Some(Some((ip, rtt))) = host_ping_tasks.next().await {
                    println!("[HostPreferred] Pinged {}: {} -> {:?}", domain, ip, rtt);
                    if rtt < best_rtt_for_domain {
                        best_rtt_for_domain = rtt;
                        best_ip_for_domain = Some(ip);
                    }
                }

                if let Some(ip) = best_ip_for_domain {
                    let mut best = best_ips_clone.lock().unwrap();
                    best.insert(domain.clone(), (ip, best_rtt_for_domain));
                }
            }));
        }

        let _ : Vec<_> = ping_tasks.collect().await;

        let final_best_ips = best_ips.lock().unwrap();
        let missing_core_domains: Vec<_> = domain_list.core.iter()
            .filter(|domain| !final_best_ips.contains_key(**domain))
            .map(|domain| *domain)
            .collect();
            
        if !missing_core_domains.is_empty() {
            anyhow::bail!("核心域名未能优选成功: {}", missing_core_domains.join(", "));
        }
        Ok(())
    };
    
    if let Err(_) = timeout(total_timeout, optimization_logic).await {
        let final_best_ips = best_ips.lock().unwrap();
        let all_core_optimized = domain_list.core.iter().all(|d| final_best_ips.contains_key(*d));

        if !all_core_optimized {
            return Err(anyhow!("操作超时（10秒），且核心域名未能完成优选。"));
        }
        println!("[HostPreferred] 操作超时，但核心域名已优选成功，将继续写入。");
    }

    let final_hosts_with_rtt = best_ips.lock().unwrap().clone();
    if final_hosts_with_rtt.is_empty() { return Err(anyhow!("未能找到任何可用的 IP 地址。")); }
    
    let total_records = final_hosts_with_rtt.len();

    let mut final_hosts_to_write: Vec<(String, String)> = Vec::new();
    for domain in domain_list.core.iter() {
        if let Some((ip, _)) = final_hosts_with_rtt.get(*domain) {
            final_hosts_to_write.push((domain.to_string(), ip.to_string()));
        }
    }
    for domain in domain_list.optional.iter() {
        if let Some((ip, _)) = final_hosts_with_rtt.get(*domain) {
            final_hosts_to_write.push((domain.to_string(), ip.to_string()));
        }
    }
    
    update_hosts_file(target, &final_hosts_to_write)
        .context("更新 hosts 文件失败")?;

    Ok(format!("{} Host 优选成功！已更新/新增 {} 条记录。", target.to_string(), total_records))
}