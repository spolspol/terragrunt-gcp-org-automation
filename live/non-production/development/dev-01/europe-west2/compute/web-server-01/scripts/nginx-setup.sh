#!/bin/bash
#
# Main setup script for Nginx web server
# This script installs and configures nginx with SSL support
#

set -euo pipefail

# Logging setup
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] nginx-setup: $*"
}

log "Starting nginx web server setup..."

# Update system packages
log "Updating system packages..."
apt-get update -qq

# Install required packages
log "Installing nginx and certbot..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nginx \
    certbot \
    python3-certbot-nginx \
    gcsfuse

# Retrieve secrets from Secret Manager
log "Retrieving configuration from Secret Manager..."
SSL_EMAIL=$(gcloud secrets versions access latest --secret="${SSL_CERT_EMAIL_SECRET##*/}" --project="$PROJECT_ID" 2>/dev/null || echo "admin@example.com")
SSL_DOMAINS=$(gcloud secrets versions access latest --secret="${SSL_DOMAINS_SECRET##*/}" --project="$PROJECT_ID" 2>/dev/null || echo "example.com")

# Create directory for static content
CONTENT_DIR="/var/www/html"
log "Setting up content directory at $CONTENT_DIR"

# Mount GCS bucket for static content (optional)
if [[ -n "${STATIC_CONTENT_BUCKET:-}" ]]; then
    log "Mounting static content bucket: $STATIC_CONTENT_BUCKET"
    mkdir -p /mnt/gcs-content
    gcsfuse --implicit-dirs "$STATIC_CONTENT_BUCKET" /mnt/gcs-content
    
    # Sync content to local directory
    if [[ -d "/mnt/gcs-content" ]] && [[ "$(ls -A /mnt/gcs-content)" ]]; then
        log "Syncing content from GCS bucket..."
        rsync -av /mnt/gcs-content/ "$CONTENT_DIR/"
    fi
fi

# Create a simple default page if no content exists
if [[ ! -f "$CONTENT_DIR/index.html" ]]; then
    log "Creating default index page..."
    cat > "$CONTENT_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to Your Web Server</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        .info { 
            background-color: #e7f3ff; 
            padding: 15px; 
            border-radius: 5px;
            margin: 20px 0;
        }
        code {
            background-color: #f0f0f0;
            padding: 2px 5px;
            border-radius: 3px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 Welcome to Your Nginx Web Server!</h1>
        <p>Your web server is up and running successfully.</p>
        
        <div class="info">
            <h2>Quick Start Guide</h2>
            <ul>
                <li>Upload your static content to the GCS bucket: <code>${STATIC_CONTENT_BUCKET}</code></li>
                <li>Content will be automatically synced to this server</li>
                <li>SSL certificates are managed by Let's Encrypt</li>
                <li>Server configuration is in <code>/etc/nginx/sites-available/default</code></li>
            </ul>
        </div>
        
        <div class="info">
            <h2>Server Information</h2>
            <ul>
                <li>Project: <code>${PROJECT_ID}</code></li>
                <li>Instance: <code>${INSTANCE_NAME}</code></li>
                <li>Region: <code>${REGION}</code></li>
                <li>Server Time: <span id="time"></span></li>
            </ul>
        </div>
    </div>
    
    <script>
        document.getElementById('time').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF
fi

# Configure nginx
log "Configuring nginx..."
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    root $CONTENT_DIR;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
EOF

# Test nginx configuration
log "Testing nginx configuration..."
nginx -t

# Start nginx
log "Starting nginx service..."
systemctl start nginx
systemctl enable nginx

# Set up SSL with Let's Encrypt (only if we have a real domain)
if [[ "$SSL_DOMAINS" != "example.com" ]] && [[ -n "$SSL_EMAIL" ]]; then
    log "Setting up SSL certificates for domains: $SSL_DOMAINS"
    
    # Split comma-separated domains
    IFS=',' read -ra DOMAIN_ARRAY <<< "$SSL_DOMAINS"
    DOMAIN_ARGS=""
    for domain in "${DOMAIN_ARRAY[@]}"; do
        DOMAIN_ARGS="$DOMAIN_ARGS -d $domain"
    done
    
    # Obtain SSL certificate
    certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "$SSL_EMAIL" \
        $DOMAIN_ARGS \
        --redirect \
        --expand || log "Warning: SSL setup failed, continuing with HTTP only"
    
    # Set up auto-renewal
    log "Setting up SSL certificate auto-renewal..."
    echo "0 0,12 * * * root certbot renew --quiet --no-self-upgrade" > /etc/cron.d/certbot-renew
fi

# Create a simple health check endpoint
cat > "$CONTENT_DIR/health" << EOF
OK
EOF

# Set up log rotation
cat > /etc/logrotate.d/nginx << EOF
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
EOF

# Final status check
if systemctl is-active --quiet nginx; then
    log "✅ Nginx is running successfully"
    log "✅ Web server setup completed"
    
    # Log access information
    EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
    log "📌 Server is accessible at: http://$EXTERNAL_IP"
    
    if [[ "$SSL_DOMAINS" != "example.com" ]]; then
        log "📌 SSL-enabled domains: $SSL_DOMAINS"
    fi
else
    log "❌ ERROR: Nginx failed to start"
    exit 1
fi

log "Setup script completed successfully"