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

-- Create index on job_id for faster lookups
CREATE INDEX IF NOT EXISTS jobs_job_id_idx ON jobs (job_id);

-- Create index on status for faster filtering
CREATE INDEX IF NOT EXISTS jobs_status_idx ON jobs (status);
