<#
.SYNOPSIS
    Retrieves all Entra (Azure AD) objects related to Workday provisioning.
    
.DESCRIPTION
    This script connects to Microsoft Graph API and extracts:
    - Service Principals (Workday App)
    - Provisioning Configurations
    - User Mappings
    - Synchronization Rules
    - Directory Extensions
    - Service Principal Owners
    
.PARAMETERS
    -OutputPath
        Path where JSON output files will be saved
        
.EXAMPLE
    .\Get-WorkdayEntraObjects.ps1 -OutputPath ".\output"
#>

param(
    [string]$OutputPath = "./output"
)

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "=== Workday Entra Objects Extractor ===" -ForegroundColor Cyan
Write-Host "Output Directory: $OutputPath`n" -ForegroundColor Gray

# Check if Microsoft Graph module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.ServicePrincipal)) {
    Write-Host "Installing Microsoft.Graph modules..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph.Identity.ServicePrincipal -Scope CurrentUser -Force
    Install-Module -Name Microsoft.Graph.Applications -Scope CurrentUser -Force
}

try {
    # Connect to Microsoft Graph (will prompt for authentication)
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "Application.Read.All", "Directory.Read.All", "ServicePrincipalEndpoint.Read.All" -ErrorAction Stop
    
    $context = Get-MgContext
    Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
    Write-Host "Tenant ID: $($context.TenantId)`n" -ForegroundColor Green
    
    # 1. Find Workday Service Principal
    Write-Host "Extracting Workday Service Principals..." -ForegroundColor Cyan
    $workdayAppNames = @("Workday", "workday", "WORKDAY")
    $workdayServicePrincipals = @()
    
    foreach ($appName in $workdayAppNames) {
        $workdayServicePrincipals += Get-MgServicePrincipal -Filter "displayName eq '$appName' or appDisplayName eq '$appName'" -ErrorAction SilentlyContinue
    }
    
    if ($workdayServicePrincipals.Count -eq 0) {
        Write-Host "Warning: No Workday Service Principals found. Searching with filter..." -ForegroundColor Yellow
        $workdayServicePrincipals = Get-MgServicePrincipal -All | Where-Object { 
            $_.DisplayName -like "*Workday*" -or 
            $_.AppDisplayName -like "*Workday*" -or
            $_.ServicePrincipalNames -like "*workday*"
        }
    }
    
    if ($workdayServicePrincipals.Count -gt 0) {
        Write-Host "Found $($workdayServicePrincipals.Count) Workday Service Principal(s)" -ForegroundColor Green
        $workdayServicePrincipals | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OutputPath/workday_service_principals.json" -Force
        Write-Host "  ✓ Saved to workday_service_principals.json" -ForegroundColor Green
    } else {
        Write-Host "No Workday Service Principals found in tenant" -ForegroundColor Yellow
    }
    
    # 2. Extract Provisioning Configurations
    Write-Host "`nExtracting Provisioning Configurations..." -ForegroundColor Cyan
    $provisioningConfigs = @()
    
    foreach ($sp in $workdayServicePrincipals) {
        try {
            $syncJobs = Get-MgServicePrincipalSynchronizationJob -ServicePrincipalId $sp.Id -ErrorAction SilentlyContinue
            
            if ($syncJobs) {
                Write-Host "Found $($syncJobs.Count) sync job(s) for $($sp.DisplayName)" -ForegroundColor Green
                
                foreach ($job in $syncJobs) {
                    # Get detailed synchronization schema
                    $schema = Get-MgServicePrincipalSynchronizationJobSchema -ServicePrincipalId $sp.Id -SynchronizationJobId $job.Id -ErrorAction SilentlyContinue
                    
                    $provisioningConfigs += @{
                        ServicePrincipalId = $sp.Id
                        ServicePrincipalName = $sp.DisplayName
                        SyncJobId = $job.Id
                        SyncJobStatus = $job.Status
                        SyncJobProgress = $job.Progress
                        SyncSchedule = $job.Schedule
                        Schema = $schema
                    }
                }
            }
        }
        catch {
            Write-Host "Error retrieving sync jobs for $($sp.DisplayName): $_" -ForegroundColor Yellow
        }
    }
    
    if ($provisioningConfigs.Count -gt 0) {
        Write-Host "Found $($provisioningConfigs.Count) provisioning configuration(s)" -ForegroundColor Green
        $provisioningConfigs | ConvertTo-Json -Depth 20 | Out-File -FilePath "$OutputPath/provisioning_configs.json" -Force
        Write-Host "  ✓ Saved to provisioning_configs.json" -ForegroundColor Green
    } else {
        Write-Host "No provisioning configurations found" -ForegroundColor Yellow
    }
    
    # 3. Extract Attribute Mappings
    Write-Host "`nExtracting Attribute Mappings..." -ForegroundColor Cyan
    $attributeMappings = @()
    
    foreach ($sp in $workdayServicePrincipals) {
        try {
            $syncJobs = Get-MgServicePrincipalSynchronizationJob -ServicePrincipalId $sp.Id -ErrorAction SilentlyContinue
            
            foreach ($job in $syncJobs) {
                $schema = Get-MgServicePrincipalSynchronizationJobSchema -ServicePrincipalId $sp.Id -SynchronizationJobId $job.Id -ErrorAction SilentlyContinue
                
                if ($schema.Mappings) {
                    foreach ($mapping in $schema.Mappings) {
                        $attributeMappings += @{
                            ServicePrincipal = $sp.DisplayName
                            SyncJobId = $job.Id
                            SourceObjectName = $mapping.SourceObjectName
                            TargetObjectName = $mapping.TargetObjectName
                            AttributeMappings = $mapping.AttributeMappings | ConvertTo-Json -Depth 10
                        }
                    }
                }
            }
        }
        catch {
            Write-Host "Error retrieving attribute mappings for $($sp.DisplayName): $_" -ForegroundColor Yellow
        }
    }
    
    if ($attributeMappings.Count -gt 0) {
        Write-Host "Found $($attributeMappings.Count) attribute mapping(s)" -ForegroundColor Green
        $attributeMappings | ConvertTo-Json -Depth 15 | Out-File -FilePath "$OutputPath/attribute_mappings.json" -Force
        Write-Host "  ✓ Saved to attribute_mappings.json" -ForegroundColor Green
    } else {
        Write-Host "No attribute mappings found" -ForegroundColor Yellow
    }
    
    # 4. Extract Directory Extensions
    Write-Host "`nExtracting Directory Extensions..." -ForegroundColor Cyan
    $dirExtensions = Get-MgDirectoryObjectSchema -All -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -like "*workday*" -or $_.Description -like "*workday*" }
    
    if ($dirExtensions) {
        Write-Host "Found $($dirExtensions.Count) directory extension(s)" -ForegroundColor Green
        $dirExtensions | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OutputPath/directory_extensions.json" -Force
        Write-Host "  ✓ Saved to directory_extensions.json" -ForegroundColor Green
    } else {
        Write-Host "No Workday-related directory extensions found" -ForegroundColor Gray
    }
    
    # 5. Extract Application Roles
    Write-Host "`nExtracting Application Roles..." -ForegroundColor Cyan
    $appRoles = @()
    
    foreach ($sp in $workdayServicePrincipals) {
        if ($sp.AppRoles) {
            Write-Host "Found $($sp.AppRoles.Count) role(s) for $($sp.DisplayName)" -ForegroundColor Green
            $appRoles += $sp.AppRoles | Add-Member -PassThru -MemberType NoteProperty -Name ServicePrincipal -Value $sp.DisplayName
        }
    }
    
    if ($appRoles.Count -gt 0) {
        $appRoles | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OutputPath/app_roles.json" -Force
        Write-Host "  ✓ Saved to app_roles.json" -ForegroundColor Green
    }
    
    # 6. Create Summary Report
    Write-Host "`nGenerating Summary Report..." -ForegroundColor Cyan
    $summary = @{
        ExtractionDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TenantId = $context.TenantId
        WorkdayServicePrincipals = $workdayServicePrincipals | Select-Object Id, DisplayName, AppId, ServicePrincipalNames
        ProvisioningConfigCount = $provisioningConfigs.Count
        AttributeMappingCount = $attributeMappings.Count
        DirectoryExtensionCount = $dirExtensions.Count
        AppRolesCount = $appRoles.Count
    }
    
    $summary | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OutputPath/extraction_summary.json" -Force
    Write-Host "  ✓ Saved to extraction_summary.json" -ForegroundColor Green
    
    Write-Host "`n=== Extraction Complete ===" -ForegroundColor Green
    Write-Host "Output files saved to: $OutputPath`n" -ForegroundColor Green
    
}
catch {
    Write-Error "Error during extraction: $_"
    exit 1
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}
