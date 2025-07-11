# VideoStreaming Platform

A comprehensive video streaming platform with frontend, backend, and YouTube scraping capabilities.

## Project Structure

- **frontend**: React-based web interface
- **rust-backend**: Rust-based API server
- **youtube-scraper**: Service for scraping and processing YouTube videos

## Features

- User authentication and management
- Video uploading and streaming
- YouTube video scraping and importing
- Distributed job queue for video processing

## Development Setup

### Prerequisites

- Docker and Docker Compose
- Node.js 18+
- Rust 1.88+
- PostgreSQL 13+
- Python 3.10+ (for yt-dlp)

### Running Locally

1. Clone the repository
2. Start all services using Docker Compose:

```bash
docker-compose up
```

3. Access the frontend at http://localhost:3000
4. The backend API is available at http://localhost:5050
5. The YouTube scraper service is available at http://localhost:5060

### Running Individual Components

#### Frontend

```bash
cd frontend
npm install
npm start
```

#### Backend

```bash
cd rust-backend
cargo run
```

#### YouTube Scraper

```bash
cd youtube-scraper
cargo run -- --server
```

## Database Migrations

The project uses SQLx for database migrations:

```bash
cd rust-backend
cargo sqlx migrate run
```

## CI/CD Pipeline

This project uses GitHub Actions for continuous integration and deployment. The workflow:

1. Builds and tests all components
2. Runs database migrations
3. Performs integration tests
4. Builds and pushes Docker images (on main branch)

### Setting up CI/CD

1. Add the following secrets to your GitHub repository:
   - `DOCKERHUB_USERNAME`: Your Docker Hub username
   - `DOCKERHUB_TOKEN`: Your Docker Hub access token

2. Push to the main branch to trigger the workflow

## Recent Updates

- Added distributed job queue for YouTube scraper using PostgreSQL
- Improved error handling and logging
- Added GitHub Actions workflow for CI/CD
