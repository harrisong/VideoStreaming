-- Drop video_time column from comments table
ALTER TABLE comments
DROP COLUMN IF EXISTS video_time;
