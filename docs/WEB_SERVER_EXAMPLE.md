# Web Server Example

This example deploys an nginx web server on GCP Compute Engine with SSL, static content from a GCS bucket, and firewall-controlled access.

## Architecture

```
web-project/
├── vpc-network/              # VPC network
├── secrets/
│   ├── ssl-cert-email/       # Let's Encrypt email
│   └── ssl-domains/          # SSL domain list
└── europe-west2/
    ├── external-ip/
    │   └── web-server-ip/    # Static external IP
    ├── firewall-rules/
    │   └── allow-web-traffic/ # HTTP/HTTPS ingress
    ├── buckets/
    │   └── static-content/   # Website files
    └── compute/
        └── web-server-01/
            ├── scripts/      # Bootstrap and setup scripts
            ├── iam-bindings/ # Service account permissions
            └── vm/           # Compute instance
```

## Deployment

```bash
cd live/non-production/development/platform/dp-dev-01

# Deploy in dependency order
terragrunt apply -auto-approve  # in vpc-network/
terragrunt apply -auto-approve  # in secrets/ssl-cert-email/ and ssl-domains/
terragrunt apply -auto-approve  # in europe-west2/external-ip/web-server-ip/
terragrunt apply -auto-approve  # in europe-west2/firewall-rules/allow-web-traffic/
terragrunt apply -auto-approve  # in europe-west2/buckets/static-content/
terragrunt apply -auto-approve  # in europe-west2/compute/web-server-01/
```

Upload scripts and content:

```bash
# Scripts (automated via GitHub Actions on push)
gsutil cp scripts/*.sh gs://[PROJECT]-vm-scripts/web-server-01/

# Static content
gsutil -m cp -r ./website/* gs://[PROJECT]-static-content/
```

Access the server:

```bash
gcloud compute instances describe web-server-01 --zone=europe-west2-a
# Visit http://[EXTERNAL_IP]
```

## SSL Configuration

Update the secrets, then the server obtains certificates automatically on first boot:

```bash
echo -n "your-email@example.com" | gcloud secrets versions add ssl-cert-email --data-file=-
echo -n "yourdomain.com,www.yourdomain.com" | gcloud secrets versions add ssl-domains --data-file=-
```

## Static Content

Files uploaded to the `static-content` bucket are synced to `/var/www/html` on the server. Directory structure is preserved.

## Customisation

**Machine type** -- edit `terragrunt.hcl`:
```hcl
machine_type = include.base.locals.merged.compute_defaults.machine_types[include.base.locals.environment].medium
```

**Startup script** -- customise `nginx-setup.sh` to install additional packages, change nginx configuration, or add monitoring agents.

**Firewall rules** -- add custom rules in `firewall-rules/allow-web-traffic/terragrunt.hcl`:
```hcl
{
  name        = "${include.base.locals.merged.project_name}-allow-custom"
  description = "Allow custom application port"
  direction   = "INGRESS"
  priority    = 1000
  ranges      = ["0.0.0.0/0"]
  target_tags = ["web-server"]
  allow       = [{ protocol = "tcp", ports = ["8080"] }]
}
```

## Monitoring

- **Logs**: Cloud Logging under the `nginx` log group
- **Metrics**: CPU, memory, and disk in Cloud Monitoring
- **Health Check**: `/health` endpoint for simple verification

## Security

- SSL/TLS enabled by default when domains are configured
- Firewall rules restrict access to necessary ports only
- SSH access limited to Cloud IAP
- Service account follows least privilege
- Static content bucket is read-only from the instance

## Cost Optimisation

- Preemptible instances in non-production
- Default machine type: `e2-micro`
- Regional bucket for lower storage costs
- Lifecycle rules clean up old content versions

## Troubleshooting

```bash
# Serial port output
gcloud compute instances get-serial-port-output web-server-01 --zone=europe-west2-a

# SSH via IAP
gcloud compute ssh web-server-01 --zone=europe-west2-a --tunnel-through-iap

# Nginx status and config test
sudo systemctl status nginx
sudo nginx -t

# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```
