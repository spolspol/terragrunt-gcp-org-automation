# SQL Server VM Configuration
# Parent configuration for SQL Server instance

locals {
  # VM-specific configuration
  vm_name = basename(get_terragrunt_dir())
  
  # SQL Server specific settings
  sql_server_config = {
    machine_type = "n2-standard-4"
    disk_size_gb = 200
    disk_type    = "pd-ssd"
    
    # Windows Server image with SQL Server
    image_family  = "sql-std-2019-win-2019"
    image_project = "windows-sql-cloud"
    
    # SQL Server ports
    sql_ports = ["1433", "1434"]
    
    # Additional Windows management ports
    windows_ports = ["3389", "5985", "5986"] # RDP, WinRM HTTP/HTTPS
  }
}