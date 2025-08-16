# OpenDiscourse Proxmox Deployment Guide

## Prerequisites

1. Proxmox VE server with:
   - Minimum 8 vCPUs
   - 32GB RAM (16GB minimum)
   - 200GB+ storage
   - Network access to the internet
   - API access enabled

2. Domain name (e.g., opendiscourse.net) with wildcard DNS configured

3. Required credentials:
   - Proxmox API token with sufficient permissions
   - GitHub OAuth credentials (if using GitHub authentication)
   - SMTP server details (for email notifications)

## Deployment Steps

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/opendiscourse.git
cd opendiscourse
```

### 2. Configure Terraform

1. Copy the example variables file:
   ```bash
   cp terraform/proxmox/terraform.tfvars.example terraform/proxmox/terraform.tfvars
   ```

2. Edit the configuration:
   ```bash
   nano terraform/proxmox/terraform.tfvars
   ```

   Update the following variables:
   - `pm_api_url`: Your Proxmox API URL
   - `pm_api_token_id`: Your Proxmox API token ID
   - `pm_api_token_secret`: Your Proxmox API token secret
   - `vm_ip`: Desired IP address for the VM
   - `vm_gateway`: Network gateway
   - `vm_password`: Password for the default user

### 3. Run the Deployment

```bash
./deploy_proxmox.sh
```

This will:
1. Create a new VM on your Proxmox server
2. Install all required dependencies
3. Deploy the OpenDiscourse stack
4. Configure all services

### 4. Post-Deployment Tasks

1. **Verify Services**:
   - Check all services are running: `docker ps`
   - Verify Traefik logs: `docker logs traefik`

2. **Configure DNS**:
   - Point your domain (e.g., opendiscourse.net) to the VM's IP
   - Add wildcard DNS record (*.opendiscourse.net) to the same IP

3. **Access Services**:
   - Dashboard: https://opendiscourse.net
   - Supabase Studio: https://supabase.opendiscourse.net
   - Grafana: https://grafana.opendiscourse.net
   - (Other services as listed in the deployment output)

## Troubleshooting

### Common Issues

1. **VM Not Starting**:
   - Check Proxmox logs: `journalctl -u pve-cluster -f`
   - Verify network settings in Proxmox

2. **Services Not Accessible**:
   - Check Traefik logs: `docker logs traefik`
   - Verify DNS resolution
   - Check firewall rules

3. **Authentication Issues**:
   - Verify OAuth configuration
   - Check service logs for authentication errors

## Maintenance

### Backups

1. **VM-Level Backups**:
   - Use Proxmox backup solutions
   - Schedule regular snapshots

2. **Application Data**:
   - Database dumps: `docker exec -t postgres pg_dumpall -c -U postgres > dump_$(date +%Y-%m-%d).sql`
   - Volume backups: Backup all Docker volumes

### Updates

1. **Application Updates**:
   ```bash
   cd /opt/opendiscourse
   git pull
   docker-compose pull
   docker-compose up -d
   ```

2. **Infrastructure Updates**:
   - Update Terraform configuration
   - Run `terraform apply`

## Security Considerations

1. **Firewall Rules**:
   - Only expose necessary ports (80, 443)
   - Use cloud firewall if available

2. **Authentication**:
   - Enable 2FA for all services
   - Regularly rotate API keys and passwords

3. **Monitoring**:
   - Set up alerts in Grafana
   - Monitor resource usage

## Support

For issues, please:
1. Check the logs
2. Review the documentation
3. Open an issue on GitHub with relevant details
