-- Update any NULL video_id values in comments table to a default or valid video_id if necessary
-- Assuming video_id should not be NULL, and if there are NULLs, they might be invalid data
-- You may need to adjust this based on your data; this is a placeholder to set to a default video_id if one exists
UPDATE comments
SET video_id = (SELECT id FROM videos LIMIT 1)
WHERE video_id IS NULL;

-- Set video_id column to NOT NULL in comments table
ALTER TABLE comments
ALTER COLUMN video_id SET NOT NULL;
