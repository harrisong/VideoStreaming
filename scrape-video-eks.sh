#!/bin/bash

# Scrape a video using EKS Kubernetes Job with browser cookies
# This script extracts cookies from your local browser and runs a scraper job on the EKS cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 <youtube_url> [user_id] [browser]"
    echo ""
    echo "Examples:"
    echo "  $0 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'"
    echo "  $0 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' 2"
    echo "  $0 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' 1 firefox"
    echo ""
    echo "Arguments:"
    echo "  youtube_url  - The YouTube URL to scrape (required)"
    echo "  user_id      - User ID to associate with the video (default: 1)"
    echo "  browser      - Browser to extract cookies from: chrome, firefox, safari, edge (default: chrome)"
    echo ""
    echo "Supported browsers:"
    echo "  chrome   - Google Chrome"
    echo "  firefox  - Mozilla Firefox"
    echo "  safari   - Safari (macOS only)"
    echo "  edge     - Microsoft Edge"
}

# Function to extract cookies from different browsers
extract_cookies() {
    local browser="$1"
    local temp_cookies_file="/tmp/all_cookies_$(date +%s).txt"
    local youtube_cookies_file="/tmp/youtube_cookies_$(date +%s).txt"
    
    echo -e "${YELLOW}Extracting cookies from $browser...${NC}" >&2
    
    case "$browser" in
        "chrome")
            # Chrome cookies extraction - extract cookies without downloading video
            if command -v yt-dlp >/dev/null 2>&1; then
                echo -e "${YELLOW}Running: yt-dlp --cookies-from-browser chrome --cookies \"$temp_cookies_file\" --skip-download \"https://www.youtube.com/watch?v=EtdGcM_Ira0\"${NC}" >&2
                yt-dlp --cookies-from-browser chrome --cookies "$temp_cookies_file" --skip-download "https://www.youtube.com/watch?v=EtdGcM_Ira0" >&2 || {
                    echo -e "${RED}❌ Failed to extract Chrome cookies${NC}" >&2
                    echo "Make sure Chrome is installed and you're logged into YouTube" >&2
                    return 1
                }
            else
                echo -e "${RED}❌ yt-dlp not found. Please install yt-dlp locally:${NC}" >&2
                echo "brew install yt-dlp" >&2
                return 1
            fi
            ;;
        "firefox")
            # Firefox cookies extraction - extract cookies without downloading video
            if command -v yt-dlp >/dev/null 2>&1; then
                yt-dlp --cookies-from-browser firefox --cookies "$temp_cookies_file" --skip-download "https://www.youtube.com/watch?v=EtdGcM_Ira0" 2>/dev/null || {
                    echo -e "${RED}❌ Failed to extract Firefox cookies${NC}"
                    echo "Make sure Firefox is installed and you're logged into YouTube"
                    return 1
                }
            else
                echo -e "${RED}❌ yt-dlp not found. Please install yt-dlp locally:${NC}"
                echo "brew install yt-dlp"
                return 1
            fi
            ;;
        "safari")
            # Safari cookies extraction (macOS only) - extract cookies without downloading video
            if [[ "$OSTYPE" != "darwin"* ]]; then
                echo -e "${RED}❌ Safari is only available on macOS${NC}"
                return 1
            fi
            if command -v yt-dlp >/dev/null 2>&1; then
                yt-dlp --cookies-from-browser safari --cookies "$temp_cookies_file" --skip-download "https://www.youtube.com/watch?v=EtdGcM_Ira0" 2>/dev/null || {
                    echo -e "${RED}❌ Failed to extract Safari cookies${NC}"
                    echo "Make sure Safari is installed and you're logged into YouTube"
                    return 1
                }
            else
                echo -e "${RED}❌ yt-dlp not found. Please install yt-dlp locally:${NC}"
                echo "brew install yt-dlp"
                return 1
            fi
            ;;
        "edge")
            # Edge cookies extraction - extract cookies without downloading video
            if command -v yt-dlp >/dev/null 2>&1; then
                yt-dlp --cookies-from-browser edge --cookies "$temp_cookies_file" --skip-download "https://www.youtube.com/watch?v=EtdGcM_Ira0" 2>/dev/null || {
                    echo -e "${RED}❌ Failed to extract Edge cookies${NC}"
                    echo "Make sure Edge is installed and you're logged into YouTube"
                    return 1
                }
            else
                echo -e "${RED}❌ yt-dlp not found. Please install yt-dlp locally:${NC}"
                echo "brew install yt-dlp"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}❌ Unsupported browser: $browser${NC}"
            echo "Supported browsers: chrome, firefox, safari, edge"
            return 1
            ;;
    esac
    
    # Filter cookies to only include YouTube domains for security
    if [[ -f "$temp_cookies_file" && -s "$temp_cookies_file" ]]; then
        echo -e "${YELLOW}Filtering cookies to YouTube domains only...${NC}" >&2
        
        # Create proper Netscape cookies file with header
        echo "# Netscape HTTP Cookie File" > "$youtube_cookies_file"
        echo "# This is a generated file!  Do not edit." >> "$youtube_cookies_file"
        
        # Extract only YouTube-related cookies (youtube.com, googlevideo.com, ytimg.com, etc.)
        grep -E '\.(youtube|googlevideo|ytimg|ggpht)\.com' "$temp_cookies_file" >> "$youtube_cookies_file" 2>/dev/null || {
            # If grep fails, we still have the header, so the file is valid
            echo -e "${YELLOW}No YouTube cookies found in browser${NC}" >&2
        }
        
        # Clean up the temporary file with all cookies
        rm -f "$temp_cookies_file"
        
        # Count actual cookie lines (excluding header comments)
        local cookie_count=$(grep -v '^#' "$youtube_cookies_file" | wc -l)
        
        if [[ $cookie_count -gt 0 ]]; then
            echo -e "${GREEN}✅ Extracted $cookie_count YouTube-specific cookies${NC}" >&2
            echo "$youtube_cookies_file"
            return 0
        else
            echo -e "${YELLOW}⚠️  No YouTube cookies found, but proceeding with empty cookies file${NC}" >&2
            echo -e "${YELLOW}   (You might not be logged into YouTube in this browser)${NC}" >&2
            echo "$youtube_cookies_file"
            return 0
        fi
    else
        echo -e "${RED}❌ Failed to extract cookies or cookies file is empty${NC}" >&2
        rm -f "$temp_cookies_file"
        return 1
    fi
}

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}❌ Error: YouTube URL is required${NC}"
    show_usage
    exit 1
fi

YOUTUBE_URL="$1"
USER_ID="${2:-1}"
BROWSER="${3:-chrome}"

# Validate YouTube URL
if [[ ! "$YOUTUBE_URL" =~ ^https?://(www\.)?(youtube\.com|youtu\.be) ]]; then
    echo -e "${RED}❌ Error: Invalid YouTube URL${NC}"
    echo "Please provide a valid YouTube URL (youtube.com or youtu.be)"
    exit 1
fi

echo -e "${BLUE}🎬 Starting video scraping job on EKS cluster...${NC}"
echo "YouTube URL: $YOUTUBE_URL"
echo "User ID: $USER_ID"
echo "Browser: $BROWSER"

# Check kubectl access
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ kubectl not configured for EKS cluster${NC}"
    echo "Please configure kubectl:"
    echo "aws eks update-kubeconfig --region us-west-2 --name prod-video-streaming-eks"
    exit 1
fi

# Extract cookies from browser
echo -e "${YELLOW}Starting cookie extraction...${NC}"
COOKIES_FILE=$(extract_cookies "$BROWSER")
EXTRACT_RESULT=$?

echo -e "${YELLOW}Cookie extraction completed with result: $EXTRACT_RESULT${NC}"
echo -e "${YELLOW}Cookies file path: $COOKIES_FILE${NC}"

if [ $EXTRACT_RESULT -ne 0 ]; then
    echo -e "${RED}❌ Failed to extract cookies${NC}"
    exit 1
fi

# Verify the cookies file exists and is readable
if [ ! -f "$COOKIES_FILE" ]; then
    echo -e "${RED}❌ Cookies file does not exist: $COOKIES_FILE${NC}"
    exit 1
fi

if [ ! -r "$COOKIES_FILE" ]; then
    echo -e "${RED}❌ Cookies file is not readable: $COOKIES_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Cookies file verified: $COOKIES_FILE${NC}"
ls -la "$COOKIES_FILE"

# Get ECR registry URL
ECR_REGISTRY=$(aws ecr describe-repositories --repository-names prod-video-streaming-scraper --region us-west-2 --query 'repositories[0].repositoryUri' --output text 2>/dev/null | cut -d'/' -f1)

if [ -z "$ECR_REGISTRY" ]; then
    echo -e "${RED}❌ Could not get ECR registry URL${NC}"
    echo "Please ensure AWS credentials are configured and ECR repository exists"
    rm -f "$COOKIES_FILE"
    exit 1
fi

# Generate unique job name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JOB_NAME="video-scraper-${TIMESTAMP}"

echo -e "${YELLOW}Creating scraper job: $JOB_NAME${NC}"

# Create a ConfigMap with the cookies file
COOKIES_CONFIGMAP="cookies-${TIMESTAMP}"
echo -e "${YELLOW}Creating cookies ConfigMap: $COOKIES_CONFIGMAP${NC}"

kubectl create configmap "$COOKIES_CONFIGMAP" \
    --from-file=cookies.txt="$COOKIES_FILE" \
    -n video-streaming

# Create the job YAML
cat > "/tmp/${JOB_NAME}.yaml" << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: video-streaming
  labels:
    app: video-streaming-app
    component: scraper
    scrape-type: manual
spec:
  template:
    metadata:
      labels:
        app: video-streaming-app
        component: scraper
        job: ${JOB_NAME}
    spec:
      restartPolicy: OnFailure
      containers:
      - name: scraper
        image: ${ECR_REGISTRY}/prod-video-streaming-scraper:latest
        command: ["youtube_scraper", "--url", "${YOUTUBE_URL}", "--user-id", "${USER_ID}", "--cookies", "/tmp/cookies/cookies.txt"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: video-streaming-secrets
              key: DATABASE_URL
        - name: AWS_REGION
          valueFrom:
            secretKeyRef:
              name: video-streaming-secrets
              key: AWS_REGION
        - name: S3_BUCKET
          valueFrom:
            secretKeyRef:
              name: video-streaming-secrets
              key: S3_BUCKET
        - name: RUST_LOG
          value: "info"
        volumeMounts:
        - name: cookies-volume
          mountPath: /tmp/cookies
          readOnly: true
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
      volumes:
      - name: cookies-volume
        configMap:
          name: ${COOKIES_CONFIGMAP}
      serviceAccountName: video-streaming-sa
  backoffLimit: 3
  ttlSecondsAfterFinished: 3600  # Clean up after 1 hour
EOF

# Apply the job
echo -e "${YELLOW}Applying job to Kubernetes cluster...${NC}"
kubectl apply -f "/tmp/${JOB_NAME}.yaml"

# Wait a moment for the job to start
sleep 3

# Show job status
echo -e "${YELLOW}Job Status:${NC}"
kubectl get job "$JOB_NAME" -n video-streaming

# Show pod status
echo -e "${YELLOW}Pod Status:${NC}"
kubectl get pods -n video-streaming -l job="$JOB_NAME"

# Get pod name for logs
POD_NAME=$(kubectl get pods -n video-streaming -l job="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
    echo -e "${YELLOW}Pod Name: $POD_NAME${NC}"
    echo ""
    echo -e "${BLUE}📋 Useful Commands:${NC}"
    echo "# Watch job progress:"
    echo "kubectl get job $JOB_NAME -n video-streaming -w"
    echo ""
    echo "# View logs:"
    echo "kubectl logs $POD_NAME -n video-streaming -f"
    echo ""
    echo "# Check pod status:"
    echo "kubectl describe pod $POD_NAME -n video-streaming"
    echo ""
    echo "# Delete job when done:"
    echo "kubectl delete job $JOB_NAME -n video-streaming"
    echo "kubectl delete configmap $COOKIES_CONFIGMAP -n video-streaming"
    echo ""
    
    # Ask if user wants to follow logs
    echo -e "${YELLOW}Would you like to follow the scraper logs? (y/n)${NC}"
    read -r FOLLOW_LOGS
    
    if [[ "$FOLLOW_LOGS" =~ ^[Yy] ]]; then
        echo -e "${BLUE}Following scraper logs (Ctrl+C to exit):${NC}"
        kubectl logs "$POD_NAME" -n video-streaming -f
    fi
else
    echo -e "${YELLOW}Pod not ready yet. Use these commands to monitor:${NC}"
    echo "kubectl get pods -n video-streaming -l job=$JOB_NAME -w"
fi

# Clean up temp files
rm -f "/tmp/${JOB_NAME}.yaml"
rm -f "$COOKIES_FILE"

echo ""
echo -e "${GREEN}✅ Scraper job '$JOB_NAME' has been started with your browser cookies!${NC}"
echo -e "${BLUE}The job and cookies ConfigMap will automatically clean up after 1 hour.${NC}"
echo ""
echo -e "${YELLOW}Cleanup commands (if needed):${NC}"
echo "kubectl delete job $JOB_NAME -n video-streaming"
echo "kubectl delete configmap $COOKIES_CONFIGMAP -n video-streaming"
