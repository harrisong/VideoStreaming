# YouTube Video Scraper

A service that downloads videos from YouTube, uploads them to a MinIO bucket, and updates a PostgreSQL database with the video metadata.

## Usage

Run as a server:
```
youtube_scraper --server
```

Run as a CLI tool:
```
youtube_scraper --url "https://www.youtube.com/watch?v=VIDEO_ID" --user-id 1
```

You can also use short options:
```
youtube_scraper -u "https://www.youtube.com/watch?v=VIDEO_ID" -i 1
```

## API Endpoints

### Submit a scraping job

```
POST /api/scrape
{
  "youtube_url": "https://www.youtube.com/watch?v=VIDEO_ID",
  "title": "Optional Custom Title",
  "description": "Optional Custom Description",
  "tags": ["tag1", "tag2"],
  "user_id": 1
}
```

Response:
```json
{
  "job_id": "123e4567-e89b-12d3-a456-426614174000"
}
```

### Search YouTube and queue videos

```
POST /api/search
{
  "query": "search term",
  "max_results": 10,
  "user_id": 1
}
```

Response:
```json
{
  "job_ids": [
    "123e4567-e89b-12d3-a456-426614174000",
    "223e4567-e89b-12d3-a456-426614174001",
    "323e4567-e89b-12d3-a456-426614174002"
  ]
}
```

This endpoint searches YouTube for videos matching the query, and automatically queues them for scraping. The `max_results` parameter is optional and defaults to 10. The `user_id` parameter is optional.

### Check job status

```
GET /api/jobs/{job_id}
```

Response (job queued):
```json
{
  "Queued": null
}
```

Response (job in progress):
```json
{
  "Processing": null
}
```

Response (job completed):
```json
{
  "Completed": {
    "video_id": 123,
    "title": "Video Title",
    "s3_key": "videos/uuid.mp4",
    "thumbnail_url": "thumbnails/uuid.jpg"
  }
}
```

Response (job failed):
```json
{
  "Failed": "Error message describing what went wrong"
}
```

### Check service status

```
POST /api/status
```

Response:
```json
{
  "status": "running"
}
```

## Asynchronous Processing

The YouTube scraper now processes video downloads asynchronously:

1. Submit a job using the `/api/scrape` endpoint
2. Receive a job ID in the response
3. Poll the job status using the `/api/jobs/{job_id}` endpoint
4. When the job status is "Completed", the video has been successfully downloaded, uploaded to MinIO, and added to the database

This asynchronous approach allows for better handling of long-running downloads and prevents timeouts when processing large videos.

## Example with curl

### Submit a job:

```bash
curl -X POST http://localhost:5060/api/scrape \
  -H "Content-Type: application/json" \
  -d '{
    "youtube_url": "https://www.youtube.com/watch?v=Kz1vI2uUhLw",
    "title": null,
    "description": null,
    "tags": ["demo"],
    "user_id": 1
  }'
```

Response:
```json
{
  "job_id": "123e4567-e89b-12d3-a456-426614174000"
}
```

### Search YouTube and queue videos:

```bash
curl -X POST http://localhost:5060/api/search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "funny cats",
    "max_results": 5,
    "user_id": 1
  }'
```

Response:
```json
{
  "job_ids": [
    "123e4567-e89b-12d3-a456-426614174000",
    "223e4567-e89b-12d3-a456-426614174001",
    "323e4567-e89b-12d3-a456-426614174002",
    "423e4567-e89b-12d3-a456-426614174003",
    "523e4567-e89b-12d3-a456-426614174004"
  ]
}
```

### Check job status:

```bash
curl -X GET http://localhost:5060/api/jobs/123e4567-e89b-12d3-a456-426614174000
```

Response (when completed):
```json
{
  "Completed": {
    "video_id": 123,
    "title": "Example Video Title",
    "s3_key": "videos/uuid.mp4",
    "thumbnail_url": "thumbnails/uuid.jpg"
  }
}
```
