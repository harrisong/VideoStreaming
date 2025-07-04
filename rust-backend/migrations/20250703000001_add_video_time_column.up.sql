-- Drop video_time column from comments table if it exists
ALTER TABLE comments
DROP COLUMN IF EXISTS video_time;

-- Add video_time column to comments table with NOT NULL constraint and default value
ALTER TABLE comments
ADD COLUMN video_time INTEGER NOT NULL DEFAULT 0;
