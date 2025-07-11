#!/bin/bash

# Script to search YouTube for videos using the YouTube scraper API

# Check if a search term was provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <search term> [number of results]"
    echo "Example: $0 \"cats playing piano\" 5"
    exit 1
fi

# Get the search term and number of results
SEARCH_TERM="$1"
NUM_RESULTS=${2:-10}  # Default to 10 if not provided

# API endpoint
API_URL="http://localhost:5060/api/search"

echo "Searching YouTube for: $SEARCH_TERM"
echo "Number of results: $NUM_RESULTS"

# Send request to the API
response=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"query\": \"$SEARCH_TERM\",
        \"max_results\": $NUM_RESULTS
    }")

# Check if the request was successful
if [[ $response == *"job_ids"* ]]; then
    # Extract job IDs
    job_ids=$(echo $response | grep -o '"job_ids":\[[^]]*\]' | sed 's/"job_ids":\[//g' | sed 's/\]//g' | sed 's/"//g' | sed 's/,/ /g')
    
    echo "Search successful! Job IDs:"
    for job_id in $job_ids; do
        echo "  $job_id"
    done
    
    # Ask if user wants to poll for job status
    read -p "Do you want to poll for job status? (y/n): " poll_status
    
    if [[ $poll_status == "y" || $poll_status == "Y" ]]; then
        echo "Polling for job status (press Ctrl+C to stop)..."
        
        while true; do
            clear
            echo "Job Status:"
            
            for job_id in $job_ids; do
                status_response=$(curl -s "http://localhost:5060/api/jobs/$job_id")
                
                # Extract status
                if [[ $status_response == *"Queued"* ]]; then
                    status="Queued"
                elif [[ $status_response == *"Processing"* ]]; then
                    status="Processing"
                elif [[ $status_response == *"Completed"* ]]; then
                    video_id=$(echo $status_response | grep -o '"video_id":[0-9]*' | cut -d':' -f2)
                    title=$(echo $status_response | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
                    status="Completed - Video ID: $video_id, Title: $title"
                elif [[ $status_response == *"Failed"* ]]; then
                    error=$(echo $status_response | grep -o '"Failed":"[^"]*"' | cut -d'"' -f4)
                    status="Failed - $error"
                else
                    status="Unknown"
                fi
                
                echo "  Job $job_id: $status"
            done
            
            sleep 5
        done
    fi
else
    echo "Error: Failed to search YouTube"
    echo "Response: $response"
    exit 1
fi
