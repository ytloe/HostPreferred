// api/models.rs

use std::fmt::{Display, Formatter, Result as FmtResult};
use flutter_rust_bridge::frb;

#[frb]
#[derive(Debug, Clone, Copy)]
pub enum OptimizationTarget {
    GitHub,
    Cloudflare, // 【新增】
}

// 【新增】为枚举实现 Display trait，方便在日志和UI中显示名称
impl Display for OptimizationTarget {
    fn fmt(&self, f: &mut Formatter<'_>) -> FmtResult {
        match self {
            OptimizationTarget::GitHub => write!(f, "GitHub"),
            OptimizationTarget::Cloudflare => write!(f, "Cloudflare"),
        }
    }
}