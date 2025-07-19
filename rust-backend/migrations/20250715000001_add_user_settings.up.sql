-- Add settings column to users table to store theme preferences
ALTER TABLE users ADD COLUMN settings JSONB DEFAULT '{}';
