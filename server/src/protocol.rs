use serde::{Deserialize, Serialize};

pub const MAX_LINE_BYTES: usize = 1024 * 1024;
// new_block adds 2 bytes to the type name and up to 26 bytes for ,"id":<u64>.
// Reserve 64 bytes conservatively; both sides use the same publication limit.
pub const NEW_BLOCK_OVERHEAD_BYTES: usize = 64;
pub const MAX_PUBLISH_LINE_BYTES: usize = MAX_LINE_BYTES - NEW_BLOCK_OVERHEAD_BYTES;

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
