-- Allow user_id column to be NULL in comments table
ALTER TABLE comments
ALTER COLUMN user_id DROP NOT NULL;
