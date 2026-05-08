use log::{info, warn};
use std::path::{Path, PathBuf};

use crate::save_index::{self, SaveEntry, SaveIndex, load_index, rebuild_index, write_index};

pub struct SaveIndexManager {
    saves_dir: PathBuf,
    index_path: PathBuf,
    index: SaveIndex,
    index_needs_rebuild: bool,
}

impl SaveIndexManager {
    pub fn init(saves_dir: &Path) -> Result<Self, String> {
        let index_path = saves_dir.join("save_index.json");
        let (index, index_needs_rebuild) = match load_index(&index_path)? {
            Some(index) => (index, false),
            None => {
                info!("[save_manager] save index missing, deferring rebuild until needed");
                (SaveIndex::new(), true)
            }
        };

        info!(
            "[save_manager] initialized with {} saves",
            index.saves.len()
        );

        Ok(Self {
            saves_dir: saves_dir.to_path_buf(),
            index_path,
            index,
            index_needs_rebuild,
        })
    }

    pub fn ensure_loaded(&mut self) -> Result<(), String> {
        if !self.index_needs_rebuild {
            return Ok(());
        }

        let (index, validations) = rebuild_index(&self.saves_dir)?;

        for validation in &validations {
            if let save_index::DbValidation::Invalid { filename, reason } = validation {
                warn!(
                    "[save_manager] invalid database during deferred rebuild: {} — {}",
                    filename, reason
                );
            }
        }

        write_index(&self.index_path, &index)?;
        self.index = index;
        self.index_needs_rebuild = false;
        info!(
            "[save_manager] deferred save index rebuild loaded {} saves",
            self.index.saves.len()
        );
        Ok(())
    }

    pub fn list_saves(&self) -> &[SaveEntry] {
        &self.index.saves
    }

    pub fn find(&self, save_id: &str) -> Option<&SaveEntry> {
        self.index.find(save_id)
    }

    pub fn record_new_save(&mut self, entry: SaveEntry) -> Result<(), String> {
        self.index.add(entry);
        self.persist()
    }

    pub fn update_save(&mut self, entry: SaveEntry) -> Result<(), String> {
        if !self.index.update(&entry) {
            return Err(format!("Failed to update index for save '{}'", entry.id));
        }

        self.persist()
    }

    pub fn remove_save(&mut self, save_id: &str) -> Result<bool, String> {
        let removed = self.index.remove(save_id);
        self.persist()?;
        Ok(removed)
    }

    fn persist(&self) -> Result<(), String> {
        write_index(&self.index_path, &self.index)
    }
}
