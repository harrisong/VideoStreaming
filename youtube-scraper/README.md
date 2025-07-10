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

## API Endpoint

```
POST /api/scrape
{
  "youtube_url": "https://www.youtube.com/watch?v=VIDEO_ID",
  "title": "Optional Custom Title",
  "description": "Optional Custom Description",
  "tags": ["tag1", "tag2"],
  "user_id": 1
}
