use crate::protocol::NewBlock;

/// Stores opaque blocks. Implementations own ID allocation and persistence.
pub trait BlockStore: Send + Sync {
    fn append(&mut self, block: String) -> Result<NewBlock, String>;
}

#[derive(Default)]
pub struct InMemoryBlockStore {
    blocks: Vec<NewBlock>,
}

impl BlockStore for InMemoryBlockStore {
    fn append(&mut self, block: String) -> Result<NewBlock, String> {
        let id = u64::try_from(self.blocks.len())
            .map_err(|_| "ID overflow")?
            .checked_add(1)
            .ok_or("ID overflow")?;
        let record = NewBlock {
            kind: "new_block".into(),
            id,
            block,
        };
        self.blocks.push(record.clone());
        Ok(record)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stores_exact_blocks_with_increasing_ids() {
        let mut store = InMemoryBlockStore::default();
        assert_eq!(store.append("opaque".into()).unwrap().id, 1);
        assert_eq!(store.append("another".into()).unwrap().id, 2);
        assert_eq!(store.blocks[0].block, "opaque");
    }
}
