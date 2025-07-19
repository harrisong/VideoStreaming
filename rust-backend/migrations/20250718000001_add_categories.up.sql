-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) UNIQUE NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add category_id column to videos table
ALTER TABLE videos ADD COLUMN category_id INTEGER REFERENCES categories(id);

-- Insert default categories
INSERT INTO categories (name, description) VALUES 
  ('Entertainment', 'Entertainment and fun videos'),
  ('Education', 'Educational and learning content'),
  ('Music', 'Music videos and performances'),
  ('Gaming', 'Gaming content and gameplay'),
  ('Sports', 'Sports and fitness content'),
  ('Technology', 'Technology and programming content'),
  ('Comedy', 'Comedy and humor videos'),
  ('News', 'News and current events'),
  ('Lifestyle', 'Lifestyle and vlog content'),
  ('Other', 'Miscellaneous content')
ON CONFLICT (name) DO NOTHING;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS videos_category_id_idx ON videos (category_id);
