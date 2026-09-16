use crate::{protocol::NewBlock, store::BlockStore};
use rusqlite::Connection;
use std::{path::Path, time::Duration};

pub struct SqliteBlockStore {
    connection: Connection,
    database_id: String,
}

impl SqliteBlockStore {
    pub fn open(path: &Path) -> Result<Self, String> {
        if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let connection = Connection::open(path).map_err(|e| e.to_string())?;
        connection
            .busy_timeout(Duration::from_secs(5))
            .map_err(|e| e.to_string())?;
        connection
            .execute_batch(
                "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=FULL;
             CREATE TABLE IF NOT EXISTS blocks (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 block TEXT NOT NULL
             );
             CREATE TABLE IF NOT EXISTS metadata (
                 key TEXT PRIMARY KEY,
                 value TEXT NOT NULL
             );
             INSERT OR IGNORE INTO metadata (key, value)
                 VALUES ('database_id', lower(hex(randomblob(16))));",
            )
            .map_err(|e| e.to_string())?;
        let database_id = connection
            .query_row(
                "SELECT value FROM metadata WHERE key = 'database_id'",
                [],
                |row| row.get::<_, String>(0),
            )
            .map_err(|e| e.to_string())?;
        if database_id.len() != 32 || !database_id.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err("Invalid database ID".into());
        }
        Ok(Self {
            connection,
            database_id,
        })
    }
}

impl BlockStore for SqliteBlockStore {
    fn database_id(&self) -> &str {
        &self.database_id
    }
    fn append(&mut self, block: String) -> Result<NewBlock, String> {
        // The insert's implicit transaction commits before the caller broadcasts.
        self.connection
            .execute("INSERT INTO blocks (block) VALUES (?1)", [&block])
            .map_err(|e| e.to_string())?;
        Ok(NewBlock {
            kind: "new_block".into(),
            id: self.connection.last_insert_rowid() as u64,
            block,
        })
    }

    fn latest_after(&self, after_id: u64) -> Result<Vec<NewBlock>, String> {
        let Ok(after_id) = i64::try_from(after_id) else {
            return Ok(Vec::new());
        };
        let mut statement = self
            .connection
            .prepare("SELECT id, block FROM blocks WHERE id > ?1 ORDER BY id DESC LIMIT 20")
            .map_err(|e| e.to_string())?;
        let mut records = statement
            .query_map([after_id], |row| {
                Ok(NewBlock {
                    kind: "new_block".into(),
                    id: row.get::<_, i64>(0)? as u64,
                    block: row.get(1)?,
                })
            })
            .map_err(|e| e.to_string())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;
        records.reverse();
        Ok(records)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn database_identity_survives_reopen_and_differs_for_new_databases() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("old.db");
        // Upgrade an existing database without changing its messages.
        {
            let connection = Connection::open(&path).unwrap();
            connection.execute_batch("CREATE TABLE blocks (id INTEGER PRIMARY KEY AUTOINCREMENT, block TEXT NOT NULL); INSERT INTO blocks (block) VALUES ('old');").unwrap();
        }
        let id = {
            let store = SqliteBlockStore::open(&path).unwrap();
            assert_eq!(store.latest_after(0).unwrap()[0].block, "old");
            store.database_id().to_owned()
        };
        assert_eq!(SqliteBlockStore::open(&path).unwrap().database_id(), id);
        assert_ne!(
            SqliteBlockStore::open(&dir.path().join("new.db"))
                .unwrap()
                .database_id(),
            id
        );
    }

    #[test]
    fn persists_exact_blocks_and_never_reuses_deleted_ids() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("nested/chat.db");
        let block = "opaque\0Привет\n🔐";
        {
            let mut store = SqliteBlockStore::open(&path).unwrap();
            assert_eq!(store.append(block.into()).unwrap().id, 1);
            assert_eq!(store.append("deleted".into()).unwrap().id, 2);
            store
                .connection
                .execute("DELETE FROM blocks WHERE id = 2", [])
                .unwrap();
        }
        let mut store = SqliteBlockStore::open(&path).unwrap();
        assert_eq!(store.latest_after(0).unwrap()[0].block, block);
        assert_eq!(store.append("next".into()).unwrap().id, 3);
    }

    #[test]
    fn limits_history_and_handles_large_cursors() {
        let mut store = SqliteBlockStore::open(Path::new(":memory:")).unwrap();
        assert!(store.latest_after(0).unwrap().is_empty());
        for _ in 0..1000 {
            store.append("opaque".into()).unwrap();
        }
        let ids = |after| {
            store
                .latest_after(after)
                .unwrap()
                .iter()
                .map(|r| r.id)
                .collect::<Vec<_>>()
        };
        assert_eq!(ids(0), (981..=1000).collect::<Vec<_>>());
        assert_eq!(ids(995), (996..=1000).collect::<Vec<_>>());
        assert!(ids(1000).is_empty());
        assert!(ids(u64::MAX).is_empty());
    }

    #[test]
    fn preserves_corrupt_file_and_reports_storage_errors() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("chat.db");
        std::fs::write(&path, b"not a database").unwrap();
        assert!(SqliteBlockStore::open(&path).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), b"not a database");
        let mut store = SqliteBlockStore::open(Path::new(":memory:")).unwrap();
        store
            .connection
            .execute_batch("PRAGMA query_only=ON;")
            .unwrap();
        assert!(store.append("unsaved".into()).is_err());
        assert!(store.latest_after(0).unwrap().is_empty());
        store
            .connection
            .execute_batch("PRAGMA query_only=OFF; DROP TABLE blocks;")
            .unwrap();
        assert!(store.latest_after(0).is_err());
    }
}
