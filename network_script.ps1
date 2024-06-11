# Check if the script is running with administrative privileges
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    return $currentUser.IsInRole($adminRole)
}

if (-not (Test-Administrator)) {
    # Re-launch the script with elevated privileges
    $scriptPath = $MyInvocation.MyCommand.Path
    $scriptArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    Start-Process powershell -ArgumentList $scriptArgs -Verb RunAs
    exit
}

# Predefined network configurations (EDIT HERE TO ADD MORE CONFIGURATION 1/3)
$predefinedConfigs = @(
    @{ Name = "Config1"; IPAddress = "192.168.1.250"; SubnetMask = 32; Gateway = "192.168.1.1" },
    @{ Name = "Config2"; IPAddress = "192.168.10.250"; SubnetMask = 32; Gateway = "192.168.1.1" }
)

# Save current network configuration
$networkAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

if ($null -eq $networkAdapter) {
    Write-Host "No active network adapters found. Exiting."
    exit
}

$currentIPConfig = Get-NetIPAddress -InterfaceAlias $networkAdapter.Name -AddressFamily IPv4
$currentGateway = Get-NetRoute -InterfaceAlias $networkAdapter.Name -DestinationPrefix "0.0.0.0/0" | Select-Object -First 1

if ($null -eq $currentIPConfig -or $null -eq $currentGateway) {
    Write-Host "Failed to retrieve current network configuration. Exiting."
    exit
}

$backupFile = "$env:TEMP\netconfig_backup.txt"

$backupContent = @{
    IPAddress = $currentIPConfig.IPAddress
    PrefixLength = $currentIPConfig.PrefixLength
    DefaultGateway = $currentGateway.NextHop
} | ConvertTo-Json

Set-Content -Path $backupFile -Value $backupContent

Write-Host "Current network configuration saved to $backupFile"

# Prompt to choose predefined configuration or custom (EDIT HERE TO ADD MORE CONFIGURATION 2/3)
Write-Host "Choose a network configuration:"
Write-Host "1. Config1 (IP: 192.168.1.250, Subnet Prefix: 32, Gateway: 192.168.1.1)"
Write-Host "2. Config2 (IP: 192.168.10.250, Subnet Prefix: 32, Gateway: 192.168.1.1)"
Write-Host "3. Custom configuration"

$configChoice = Read-Host "Enter the number of the desired configuration"

#(EDIT HERE TO ADD MORE CONFIGURATION 3/3)
switch ($configChoice) {
    1 {
        $selectedConfig = $predefinedConfigs[0]
    }
    2 {
        $selectedConfig = $predefinedConfigs[1]
    }
    3 {
        $selectedConfig = @{
            IPAddress = Read-Host "Enter the IP address"
            SubnetMask = Read-Host "Enter the Subnet Mask (as prefix length, e.g., 24 for 255.255.255.0)"
            Gateway = Read-Host "Enter the Default Gateway"
        }
    }
    default {
        Write-Host "Invalid choice. Exiting."
        exit
    }
}

# Save the current IP configuration
$currentIPConfig = Get-NetIPAddress -InterfaceAlias $networkAdapter.Name -AddressFamily IPv4
$currentGateway = Get-NetRoute -InterfaceAlias $networkAdapter.Name -DestinationPrefix "0.0.0.0/0" | Select-Object -First 1

if ($null -eq $currentIPConfig -or $null -eq $currentGateway) {
    Write-Host "Failed to retrieve current network configuration after setting new IP address. Exiting."
    exit
}

# Display the selected details for confirmation
Write-Host "IP Address: $($selectedConfig.IPAddress)"
Write-Host "Subnet Mask: $($selectedConfig.SubnetMask)"
Write-Host "Default Gateway: $($selectedConfig.Gateway)"

# Set the new IP address and subnet mask
if ($selectedConfig.Gateway -ne "") {
    # Remove existing default gateway if it exists
    $existingGateway = Get-NetRoute -InterfaceAlias $networkAdapter.Name -AddressFamily IPv4 | Where-Object {$_.DestinationPrefix -eq "0.0.0.0/0"}
    if ($null -ne $existingGateway) {
        Write-Host "Removing existing default gateway: $($existingGateway.NextHop)"
        Remove-NetRoute -InterfaceAlias $networkAdapter.Name -DestinationPrefix "0.0.0.0/0" -Confirm:$false
    }
}

New-NetIPAddress -InterfaceAlias $networkAdapter.Name -IPAddress $selectedConfig.IPAddress -PrefixLength $selectedConfig.SubnetMask

$backupContent = @{
    IPAddress = $currentIPConfig.IPAddress
    PrefixLength = $currentIPConfig.PrefixLength
    DefaultGateway = $currentGateway.NextHop
} | ConvertTo-Json

Set-Content -Path $backupFile -Value $backupContent

Write-Host "New IP Address set."

# Disable and enable the network adapter to apply changes
Write-Host "Disabling network adapter..."
Disable-NetAdapter -Name $networkAdapter.Name
Start-Sleep -Seconds 5  # Wait for 5 seconds
Write-Host "Enabling network adapter..."
Enable-NetAdapter -Name $networkAdapter.Name

# Prompt to restore the previous network configuration
$restore = Read-Host "Do you want to restore the previous network configuration? (yes/no)"
if ($restore -eq "yes") {
    # Restore previous network configuration
    $backupContent = Get-Content -Path $backupFile | ConvertFrom-Json
#    $oldIPAddress = $backupContent.IPAddress
#    $oldPrefixLength = $backupContent.PrefixLength
#    $oldGateway = $backupContent.DefaultGateway

    Write-Host "Restoring previous network configuration..."
    $currentIPConfig = Get-NetIPAddress -InterfaceAlias $networkAdapter.Name -AddressFamily IPv4
    if ($null -ne $currentIPConfig) {
        Write-Host "Setting IP Address to obtain dynamically from DHCP..."
        Remove-NetIPAddress -InterfaceAlias $networkAdapter.Name -Confirm:$false  # Remove any existing IP address
        
        # Set interface to obtain IP address dynamically from DHCP
        Set-NetIPInterface -InterfaceAlias $networkAdapter.Name -Dhcp Enabled
        
        # Disable and enable the network adapter to apply changes
        Write-Host "Disabling network adapter..."
        Disable-NetAdapter -Name $networkAdapter.Name
        Start-Sleep -Seconds 5  # Wait for 5 seconds
        Write-Host "Enabling network adapter..."
        Enable-NetAdapter -Name $networkAdapter.Name
        Write-Host "Previous network configuration restored."
    } else {
        Write-Host "Failed to retrieve current IP configuration. Exiting."
        exit
    }
} else {
    Write-Host "Exiting without restoring previous network configuration."
}
