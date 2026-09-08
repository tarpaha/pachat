use serde::{Deserialize, Serialize};

pub const MAX_LINE_BYTES: usize = 1024 * 1024;

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Request {
    Publish { block: String },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NewBlock {
    #[serde(rename = "type")]
    pub kind: String,
    pub id: u64,
    pub block: String,
}
