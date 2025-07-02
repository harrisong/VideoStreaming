# Video Streaming Application

This project is a video streaming website with a React frontend, Rust backend, PostgreSQL database, and MinIO for object storage. The application is containerized using Docker for easy deployment and scalability.

## Prerequisites

- Docker
- Docker Compose

## Getting Started with Docker

1. **Clone the Repository** (if not already done):
   ```bash
   git clone <repository-url>
   cd VideoStreaming
   ```

2. **Build and Run the Containers**:
   Use Docker Compose to build and start all the services:
   ```bash
   docker-compose up --build
   ```

   This command will:
   - Build the frontend and backend images
   - Start containers for frontend, Rust backend, PostgreSQL, and MinIO
   - Initialize the database with necessary tables and sample data
   - Create the MinIO bucket if it doesn't exist

3. **Access the Application**:
   - Frontend: Open your browser and navigate to `http://localhost:3000`
   - Backend API: Available at `http://localhost:5050`
   - MinIO Console: Available at `http://localhost:9001` (username: `minio`, password: `minio123`)

4. **Stopping the Containers**:
   When you're done, stop the containers with:
   ```bash
   docker-compose down
   ```

   **Important**: Using the `-v` flag with `docker-compose down` will remove the volumes, which deletes all persisted data for PostgreSQL and MinIO. Only use this if you want to reset all data:
   ```bash
   docker-compose down -v
   ```

## Development

If you want to make changes to the code and see them reflected in the containers, you can use volume mounting to map your local code into the containers. Update the `docker-compose.yml` file to include volume mounts for the frontend and backend services.

### Rust Backend Development

- The Rust backend is located in the `rust-backend` directory.
- To build and run locally, ensure you have Rust and Cargo installed, set the `DATABASE_URL` environment variable, and run `cargo sqlx prepare` followed by `cargo run` in the `rust-backend` directory.
- For Docker builds, ensure the `DATABASE_URL` is set correctly during the build process or use `docker-compose build backend` to build within the Docker environment.

## Troubleshooting

- **Database Connection Issues**: Ensure that the database name, user, and password in the backend environment variables match those defined in the PostgreSQL service.
- **MinIO Bucket Initialization**: The backend container may run a script to create the bucket on startup. Check the container logs if you encounter issues with file uploads.
- **Frontend Routing**: The Nginx configuration in the frontend container is set up to handle React's client-side routing. Ensure the `nginx.conf` file is correctly copied during the build process.
- **MinIO Connection Errors**: If you encounter DNS or connection errors with MinIO, ensure the `MINIO_ENDPOINT` environment variable in `.env` or Docker Compose is set to the correct address (e.g., `http://minio:9000` for Docker Compose setups). The Rust backend is configured to use path-style addressing for MinIO compatibility.

## License

[Add your license information here]
