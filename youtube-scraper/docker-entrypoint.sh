#!/bin/bash
set -e

# Function to scrape URLs from a file
scrape_urls() {
    local urls_file=$1
    
    # Check if the file exists
    if [ ! -f "$urls_file" ]; then
        echo "URLs file not found: $urls_file"
        return 1
    fi
    
    echo "Starting to process URLs from $urls_file"
    
    # Wait for the server to be ready
    echo "Waiting for scraper server to be ready..."
    until curl -s http://localhost:5060/api/status > /dev/null; do
        echo "Waiting for server..."
        sleep 2
    done
    echo "Server is ready!"
    
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
        
        echo "Response: $response"
        
        # Extract the job ID from the response
        job_id=$(echo $response | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$job_id" ]; then
            echo "Job submitted with ID: $job_id"
            
            # Poll for job status
            status="pending"
            max_attempts=30
            attempt=0
            
            while [ "$status" == "pending" ] || [ "$status" == "processing" ]; do
                sleep 5
                status_response=$(curl -s "http://localhost:5060/api/jobs/$job_id")
                echo "Status response: $status_response"
                
                if [[ $status_response == *"status"* ]]; then
                    status=$(echo $status_response | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
                    echo "Job status: $status"
                else
                    echo "Could not parse status from response"
                    break
                fi
                
                # Prevent infinite loop
                attempt=$((attempt + 1))
                if [ $attempt -ge $max_attempts ]; then
                    echo "Maximum polling attempts reached. Moving on."
                    break
                fi
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
    done < "$urls_file"
    
    echo "All URLs have been processed"
}

# Start the youtube-scraper in server mode in the background
echo "Starting youtube-scraper in server mode..."
youtube_scraper --server &
SCRAPER_PID=$!

# Check if we have a URLs file to process
if [ -f "/usr/src/app/urls_to_scrape" ]; then
    # Process the URLs
    scrape_urls "/usr/src/app/urls_to_scrape"
fi

# Keep the container running with the server
echo "Scraper server is running. Use Ctrl+C to stop."
wait $SCRAPER_PID
