-- Update any NULL created_at values in comments table to the current timestamp if necessary
UPDATE comments
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

-- Set created_at column to NOT NULL in comments table
ALTER TABLE comments
ALTER COLUMN created_at SET NOT NULL;
