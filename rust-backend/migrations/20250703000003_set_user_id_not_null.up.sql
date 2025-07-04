-- Update any NULL user_id values in comments table to a default or valid user_id if necessary
-- Assuming user_id should not be NULL, and if there are NULLs, they might be invalid data
-- This sets NULL user_id to the first user in the users table as a fallback
UPDATE comments
SET user_id = (SELECT id FROM users LIMIT 1)
WHERE user_id IS NULL;

-- Set user_id column to NOT NULL in comments table
ALTER TABLE comments
ALTER COLUMN user_id SET NOT NULL;
