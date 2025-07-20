-- Restore the sample video "Sample Video 4" if the migration is rolled back
INSERT INTO videos (title, description, s3_key, thumbnail_url, uploaded_by, tags)
SELECT 'Sample Video 4', 'This is a sample video for testing purposes.', 'videos/sample_video_4.webm', 'https://via.placeholder.com/150', 1, ARRAY['_some-tag']
WHERE NOT EXISTS (SELECT 1 FROM videos WHERE title = 'Sample Video 4');
