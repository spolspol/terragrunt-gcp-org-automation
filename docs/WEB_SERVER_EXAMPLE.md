# Web Server Example

This example demonstrates how to deploy a simple nginx web server using Terragrunt and GCP Compute Engine.

## Overview

The web server example includes:
- **Nginx Web Server**: Serves static content with SSL support
- **Static Content Bucket**: GCS bucket for website files
- **SSL Certificates**: Automated SSL via Let's Encrypt
- **External IP**: Static IP address for consistent access
- **Firewall Rules**: Allow HTTP/HTTPS traffic

## Architecture

```
web-project/
├── vpc-network/              # VPC network configuration
├── secrets/                  # SSL configuration secrets
│   ├── ssl-cert-email/      # Email for Let's Encrypt
│   └── ssl-domains/         # Domains for SSL certificates
└── europe-west2/
    ├── external-ip/         # Static IP address
    │   └── web-server-ip/
    ├── firewall-rules/      # HTTP/HTTPS access rules
    │   └── allow-web-traffic/
    ├── buckets/             # Static content storage
    │   └── static-content/
    └── compute/             # Web server instance
        └── web-server-01/
            ├── scripts/     # Bootstrap & setup scripts
            ├── iam-bindings/# Service account permissions
            └── vm/          # Compute instance
```

## Deployment Steps

1. **Deploy Infrastructure**:
   ```bash
   cd live/non-production/development/dev-01
   
   # Deploy in order
   terragrunt run-all apply --terragrunt-include-dir vpc-network
   terragrunt run-all apply --terragrunt-include-dir secrets
   terragrunt run-all apply --terragrunt-include-dir europe-west2/external-ip
   terragrunt run-all apply --terragrunt-include-dir europe-west2/firewall-rules
   terragrunt run-all apply --terragrunt-include-dir europe-west2/buckets
   terragrunt run-all apply --terragrunt-include-dir europe-west2/compute
   ```

2. **Upload Scripts to GCS**:
   The GitHub Actions workflow automatically uploads scripts when changes are pushed.
   
   Manual upload:
   ```bash
   gsutil cp scripts/*.sh gs://[PROJECT]-vm-scripts/web-server-01/
   ```

3. **Upload Static Content**:
   ```bash
   # Upload your website files
   gsutil -m cp -r ./website/* gs://[PROJECT]-static-content/
   ```

4. **Access the Server**:
   - Get the external IP: `gcloud compute instances describe web-server-01 --zone=europe-west2-a`
   - Visit: `http://[EXTERNAL_IP]`

## Configuration

### SSL Setup

1. Update the SSL secrets with your information:
   ```bash
   # Update email
   echo -n "your-email@example.com" | gcloud secrets versions add ssl-cert-email --data-file=-
   
   # Update domains
   echo -n "yourdomain.com,www.yourdomain.com" | gcloud secrets versions add ssl-domains --data-file=-
   ```

2. The server will automatically obtain SSL certificates on first boot.

### Static Content

- Upload files to the `static-content` bucket
- Files are synced to `/var/www/html` on the server
- Directory structure is preserved

## Customization

### Machine Type
Edit `terragrunt.hcl` to change the instance size:
```hcl
machine_type = local.common_vars.locals.compute_defaults.machine_types[local.environment_type].medium
```

### Startup Script
The `nginx-setup.sh` script can be customized to:
- Install additional packages
- Configure nginx differently
- Set up application servers
- Add monitoring agents

### Firewall Rules
Add custom rules in `firewall-rules/allow-web-traffic/terragrunt.hcl`:
```hcl
{
  name        = "${local.project_vars.locals.project_name}-allow-custom"
  description = "Allow custom application port"
  direction   = "INGRESS"
  priority    = 1000
  ranges      = ["0.0.0.0/0"]
  target_tags = ["web-server"]
  
  allow = [{
    protocol = "tcp"
    ports    = ["8080"]
  }]
}
```

## Monitoring

- **Logs**: Available in Cloud Logging under `nginx` log group
- **Metrics**: CPU, memory, and disk metrics in Cloud Monitoring
- **Health Check**: Access `/health` endpoint for simple health verification

## Security Considerations

- SSL/TLS enabled by default (when domains configured)
- Firewall rules restrict access to necessary ports only
- SSH access limited to Cloud IAP
- Service account follows least privilege principle
- Static content bucket is read-only from the instance

## Cost Optimization

- Uses preemptible instances in non-production
- Small machine type by default (e2-micro)
- Regional bucket for lower storage costs
- Lifecycle rules to clean up old content versions

## Troubleshooting

1. **Check Instance Logs**:
   ```bash
   gcloud compute instances get-serial-port-output web-server-01 --zone=europe-west2-a
   ```

2. **SSH to Instance**:
   ```bash
   gcloud compute ssh web-server-01 --zone=europe-west2-a --tunnel-through-iap
   ```

3. **Check Nginx Status**:
   ```bash
   sudo systemctl status nginx
   sudo nginx -t  # Test configuration
   ```

4. **View Nginx Logs**:
   ```bash
   sudo tail -f /var/log/nginx/access.log
   sudo tail -f /var/log/nginx/error.log
   ```