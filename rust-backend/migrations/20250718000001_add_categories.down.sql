-- Remove category_id column from videos table
ALTER TABLE videos DROP COLUMN IF EXISTS category_id;

-- Drop categories table
DROP TABLE IF EXISTS categories;

-- Drop index
DROP INDEX IF EXISTS videos_category_id_idx;
