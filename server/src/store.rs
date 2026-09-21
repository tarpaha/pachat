use crate::protocol::NewBlock;

pub const HISTORY_PAGE_SIZE: usize = 100;

/// Stores opaque blocks. Implementations own ID allocation and persistence.
pub trait BlockStore: Send {
    fn database_id(&self) -> &str;
    fn append(&mut self, block: String) -> Result<NewBlock, String>;
    fn page_after(&self, after_id: u64) -> Result<Vec<NewBlock>, String>;
}

#[cfg(test)]
#[derive(Default)]
pub struct InMemoryBlockStore {
    blocks: Vec<NewBlock>,
}

#[cfg(test)]
impl BlockStore for InMemoryBlockStore {
    fn database_id(&self) -> &str {
        "00000000000000000000000000000000"
    }
    fn page_after(&self, after_id: u64) -> Result<Vec<NewBlock>, String> {
        let records: Vec<_> = self
            .blocks
            .iter()
            .filter(|record| record.id > after_id)
            .take(HISTORY_PAGE_SIZE)
            .cloned()
            .collect();
        Ok(records)
    }

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
    fn history_returns_first_page_after_cursor_in_order() {
        let mut store = InMemoryBlockStore::default();
        assert!(store.page_after(0).unwrap().is_empty());
        for _ in 0..1000 {
            store.append("opaque".into()).unwrap();
        }
        let ids = |after| {
            store
                .page_after(after)
                .unwrap()
                .iter()
                .map(|r| r.id)
                .collect::<Vec<_>>()
        };
        assert_eq!(ids(0), (1..=100).collect::<Vec<_>>());
        assert_eq!(ids(990), (991..=1000).collect::<Vec<_>>());
        assert!(ids(1000).is_empty());
        assert!(ids(1001).is_empty());
    }
    #[test]
    fn stores_exact_blocks_with_increasing_ids() {
        let mut store = InMemoryBlockStore::default();
        assert_eq!(store.append("opaque".into()).unwrap().id, 1);
        assert_eq!(store.append("another".into()).unwrap().id, 2);
        assert_eq!(store.blocks[0].block, "opaque");
    }
}
