-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create unique constraint on name
CREATE UNIQUE INDEX IF NOT EXISTS categories_name_unique_idx ON categories (name);

-- Add category_id column to videos table if it doesn't exist
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='videos' AND column_name='category_id') THEN
        ALTER TABLE videos ADD COLUMN category_id INTEGER REFERENCES categories(id);
    END IF;
END $$;

-- Insert default categories only if they don't exist
DO $$
BEGIN
    -- Insert categories one by one to avoid conflicts
    INSERT INTO categories (name, description) 
    SELECT 'Entertainment', 'Entertainment and fun videos'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Entertainment');
    
    INSERT INTO categories (name, description) 
    SELECT 'Education', 'Educational and learning content'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Education');
    
    INSERT INTO categories (name, description) 
    SELECT 'Music', 'Music videos and performances'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Music');
    
    INSERT INTO categories (name, description) 
    SELECT 'Gaming', 'Gaming content and gameplay'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Gaming');
    
    INSERT INTO categories (name, description) 
    SELECT 'Sports', 'Sports and fitness content'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Sports');
    
    INSERT INTO categories (name, description) 
    SELECT 'Technology', 'Technology and programming content'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Technology');
    
    INSERT INTO categories (name, description) 
    SELECT 'Comedy', 'Comedy and humor videos'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Comedy');
    
    INSERT INTO categories (name, description) 
    SELECT 'News', 'News and current events'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'News');
    
    INSERT INTO categories (name, description) 
    SELECT 'Lifestyle', 'Lifestyle and vlog content'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Lifestyle');
    
    INSERT INTO categories (name, description) 
    SELECT 'Other', 'Miscellaneous content'
    WHERE NOT EXISTS (SELECT 1 FROM categories WHERE name = 'Other');
END $$;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS videos_category_id_idx ON videos (category_id);
