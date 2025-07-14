-- Drop indexes
DROP INDEX IF EXISTS jobs_status_idx;
DROP INDEX IF EXISTS jobs_job_id_idx;

-- Drop tables in reverse order (due to foreign key constraints)
DROP TABLE IF EXISTS jobs;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS videos;
DROP TABLE IF EXISTS users;
