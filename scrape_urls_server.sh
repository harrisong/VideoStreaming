#!/bin/bash

# Script to scrape YouTube URLs using the youtube-scraper in server mode

# Start the youtube-scraper in server mode in the background
echo "Starting youtube-scraper in server mode..."
cd youtube-scraper && cargo run -- --server &
SCRAPER_PID=$!

# Wait for the server to start
echo "Waiting for server to start..."
sleep 5

# Check if the urls_to_scrape file exists
if [ ! -f "urls_to_scrape" ]; then
    echo "Error: urls_to_scrape file not found"
    kill $SCRAPER_PID
    exit 1
fi

# Read each URL from the file and scrape it via the API
while IFS= read -r url; do
    # Skip empty lines
    if [ -z "$url" ]; then
        continue
    fi
    
    echo "Scraping URL: $url"
    
    # Make a POST request to the scrape endpoint
    response=$(curl -s -X POST "http://localhost:5060/api/scrape" \
        -H "Content-Type: application/json" \
        -d "{\"youtube_url\": \"$url\"}")
    
    # Extract the job ID from the response
    job_id=$(echo $response | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$job_id" ]; then
        echo "Job submitted with ID: $job_id"
        
        # Poll for job status
        status="pending"
        while [ "$status" == "pending" ] || [ "$status" == "processing" ]; do
            sleep 2
            status_response=$(curl -s "http://localhost:5060/api/jobs/$job_id")
            status=$(echo $status_response | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            echo "Job status: $status"
        done
        
        if [ "$status" == "completed" ]; then
            echo "Successfully scraped: $url"
        else
            echo "Failed to scrape: $url"
            echo "Error details: $status_response"
        fi
    else
        echo "Failed to submit job for: $url"
        echo "Response: $response"
    fi
    
    echo "-----------------------------------"
done < "urls_to_scrape"

echo "All URLs have been processed"

# Terminate the scraper server
echo "Stopping youtube-scraper server..."
kill $SCRAPER_PID
