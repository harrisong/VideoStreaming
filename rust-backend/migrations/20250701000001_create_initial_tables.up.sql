-- Create users table
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create videos table
CREATE TABLE IF NOT EXISTS videos (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  s3_key VARCHAR(255) UNIQUE NOT NULL,
  thumbnail_url VARCHAR(255),
  uploaded_by INTEGER REFERENCES users(id),
  upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  view_count INTEGER DEFAULT 0
);

-- Create comments table
CREATE TABLE IF NOT EXISTS comments (
  id SERIAL PRIMARY KEY,
  video_id INTEGER REFERENCES videos(id) ON DELETE CASCADE,
  user_id INTEGER REFERENCES users(id),
  content TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create jobs table
CREATE TABLE IF NOT EXISTS jobs (
    id SERIAL PRIMARY KEY,
    job_id TEXT UNIQUE NOT NULL,
    request JSONB NOT NULL,
    status TEXT NOT NULL,
    response JSONB,
    error TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS jobs_job_id_idx ON jobs (job_id);
CREATE INDEX IF NOT EXISTS jobs_status_idx ON jobs (status);

-- Insert sample data for testing
-- Insert a sample user (password is hashed for 'password123')
INSERT INTO users (username, email, password) 
VALUES ('testuser', 'test@example.com', '$2b$10$X7VYFDe.9uoyfW7Mbdzc/.8U9tR5FTfAZrB6iZ9eMW8o7G7o9eP7W')
ON CONFLICT (username) DO NOTHING;

-- Insert a sample video (note: we need a unique constraint on s3_key for this to work properly)
INSERT INTO videos (title, description, s3_key, thumbnail_url, uploaded_by, tags)
VALUES ('Sample Video 4', 'This is a sample video for testing purposes.', 'videos/sample_video_4.webm', 'https://via.placeholder.com/150', 1, ARRAY['_some-tag'])
ON CONFLICT (s3_key) DO NOTHING;
