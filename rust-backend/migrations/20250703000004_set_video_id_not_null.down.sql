-- Allow video_id column to be NULL in comments table
ALTER TABLE comments
ALTER COLUMN video_id DROP NOT NULL;
