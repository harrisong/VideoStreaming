-- Allow created_at column to be NULL in comments table
ALTER TABLE comments
ALTER COLUMN created_at DROP NOT NULL;
