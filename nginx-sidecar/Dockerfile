FROM nginx:alpine

# Copy ECS-specific nginx configuration (uses localhost)
COPY nginx.ecs.conf /etc/nginx/nginx.conf

# Expose port 80
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
