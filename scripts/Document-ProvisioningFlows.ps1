<#
.SYNOPSIS
    Documents all provisioning flows extracted from Entra.
    
.DESCRIPTION
    Reads the extracted JSON files and creates comprehensive documentation
    including flow diagrams, attribute mappings, and configuration details.
    
.PARAMETERS
    -InputPath
        Path containing extracted JSON files
        
    -OutputPath
        Path where documentation will be saved
        
.EXAMPLE
    .\Document-ProvisioningFlows.ps1 -InputPath "./output" -OutputPath "./docs"
#>

param(
    [string]$InputPath = "./output",
    [string]$OutputPath = "./docs"
)

if (-not (Test-Path $InputPath)) {
    Write-Error "Input path not found: $InputPath"
    exit 1
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "=== Provisioning Flows Documentation Generator ===" -ForegroundColor Cyan
Write-Host "Input Directory: $InputPath" -ForegroundColor Gray
Write-Host "Output Directory: $OutputPath`n" -ForegroundColor Gray

# Function to create markdown documentation
function New-MarkdownDoc {
    param(
        [string]$Title,
        [string]$Content,
        [string]$OutputFile
    )
    
    $markdown = @"
# $Title

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

$Content

---
**Last Updated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
    
    $markdown | Out-File -FilePath $OutputFile -Force
    Write-Host "  ✓ Created: $(Split-Path $OutputFile -Leaf)" -ForegroundColor Green
}

try {
    # 1. Load extracted data
    Write-Host "Loading extracted data..." -ForegroundColor Cyan
    
    $summary = @{}
    $servicePrincipals = @{}
    $provisioningConfigs = @{}
    $attributeMappings = @{}
    
    if (Test-Path "$InputPath/extraction_summary.json") {
        $summary = Get-Content "$InputPath/extraction_summary.json" | ConvertFrom-Json -AsHashtable
        Write-Host "  ✓ Loaded extraction summary" -ForegroundColor Green
    }
    
    if (Test-Path "$InputPath/workday_service_principals.json") {
        $servicePrincipals = Get-Content "$InputPath/workday_service_principals.json" | ConvertFrom-Json -AsHashtable
        Write-Host "  ✓ Loaded service principals" -ForegroundColor Green
    }
    
    if (Test-Path "$InputPath/provisioning_configs.json") {
        $provisioningConfigs = Get-Content "$InputPath/provisioning_configs.json" | ConvertFrom-Json -AsHashtable
        Write-Host "  ✓ Loaded provisioning configs" -ForegroundColor Green
    }
    
    if (Test-Path "$InputPath/attribute_mappings.json") {
        $attributeMappings = Get-Content "$InputPath/attribute_mappings.json" | ConvertFrom-Json -AsHashtable
        Write-Host "  ✓ Loaded attribute mappings" -ForegroundColor Green
    }
    
    # 2. Create Overview Documentation
    Write-Host "`nGenerating documentation..." -ForegroundColor Cyan
    
    $overviewContent = @"
## Executive Summary

- **Extraction Date**: $($summary.ExtractionDate)
- **Tenant ID**: $($summary.TenantId)
- **Service Principals Found**: $($summary.WorkdayServicePrincipals.Count)
- **Provisioning Configurations**: $($summary.ProvisioningConfigCount)
- **Attribute Mappings**: $($summary.AttributeMappingCount)

## Service Principals Discovered

| ID | Display Name | App ID |
|----|--------------|--------|
"@
    
    if ($summary.WorkdayServicePrincipals) {
        foreach ($sp in $summary.WorkdayServicePrincipals) {
            $overviewContent += "`n| ``$($sp.Id)`` | $($sp.DisplayName) | ``$($sp.AppId)`` |"
        }
    }
    
    $overviewContent += @"

## Provisioning Flows Overview

Total flows configured: **$($summary.ProvisioningConfigCount)**

### Detailed Flows

"@
    
    if ($provisioningConfigs -is [array]) {
        foreach ($i = 0; $i -lt $provisioningConfigs.Count; $i++) {
            $config = $provisioningConfigs[$i]
            $overviewContent += @"

#### Flow $($i + 1): $($config.ServicePrincipalName)

- **Service Principal**: $($config.ServicePrincipalName)
- **Sync Job ID**: ``$($config.SyncJobId)``
- **Status**: $($config.SyncJobStatus)
- **Schedule**: $($config.SyncSchedule | ConvertTo-Json -Compress)

"@
        }
    } elseif ($provisioningConfigs) {
        $overviewContent += @"

#### Flow 1: $($provisioningConfigs.ServicePrincipalName)

- **Service Principal**: $($provisioningConfigs.ServicePrincipalName)
- **Sync Job ID**: ``$($provisioningConfigs.SyncJobId)``
- **Status**: $($provisioningConfigs.SyncJobStatus)
- **Schedule**: $($provisioningConfigs.SyncSchedule | ConvertTo-Json -Compress)

"@
    }
    
    New-MarkdownDoc -Title "Workday Provisioning Overview" -Content $overviewContent -OutputFile "$OutputPath/01-Overview.md"
    
    # 3. Create Attribute Mappings Documentation
    Write-Host "  Generating attribute mappings documentation..." -ForegroundColor Gray
    
    $mappingsContent = @"
## Attribute Mapping Configuration

### Summary
- **Total Mappings**: $($summary.AttributeMappingCount)

### Mapping Details

"@
    
    if ($attributeMappings -is [array]) {
        $mappingsByFlow = $attributeMappings | Group-Object -Property SyncJobId
        
        foreach ($flow in $mappingsByFlow) {
            $mappingsContent += @"

#### Flow: $($flow.Group[0].ServicePrincipal)

**Sync Job ID**: ``$($flow.Name)``

| Source Object | Target Object | Attribute Mappings |
|---|---|---|
"@
            
            foreach ($mapping in $flow.Group) {
                $srcObj = $mapping.SourceObjectName
                $tgtObj = $mapping.TargetObjectName
                $mappingsContent += "`n| $srcObj | $tgtObj | [View Mappings](#mapping-$($mapping.SyncJobId)) |"
            }
            
            # Add detailed mappings
            foreach ($mapping in $flow.Group) {
                $mappingsContent += @"

##### Mapping: $($mapping.SourceObjectName) → $($mapping.TargetObjectName)

\`\`\`json
$($mapping.AttributeMappings)
\`\`\`

"@
            }
        }
    } elseif ($attributeMappings) {
        $mappingsContent += @"

#### Flow: $($attributeMappings.ServicePrincipal)

| Source Object | Target Object | Attribute Mappings |
|---|---|---|
| $($attributeMappings.SourceObjectName) | $($attributeMappings.TargetObjectName) | [View Mappings](#mapping-details) |

##### Detailed Mapping

\`\`\`json
$($attributeMappings.AttributeMappings)
\`\`\`

"@
    }
    
    New-MarkdownDoc -Title "Attribute Mappings Documentation" -Content $mappingsContent -OutputFile "$OutputPath/02-AttributeMappings.md"
    
    # 4. Create Configuration Details Documentation
    Write-Host "  Generating configuration details..." -ForegroundColor Gray
    
    $configContent = @"
## Provisioning Configuration Details

"@
    
    if ($provisioningConfigs -is [array]) {
        foreach ($i = 0; $i -lt $provisioningConfigs.Count; $i++) {
            $config = $provisioningConfigs[$i]
            $configContent += @"

### Configuration $($i + 1): $($config.ServicePrincipalName)

**Service Principal Details**
- ID: ``$($config.ServicePrincipalId)``
- Name: $($config.ServicePrincipalName)

**Synchronization Job**
- Job ID: ``$($config.SyncJobId)``
- Status: $($config.SyncJobStatus)

**Progress**
\`\`\`json
$($config.SyncJobProgress | ConvertTo-Json -Depth 10)
\`\`\`

**Schedule**
\`\`\`json
$($config.SyncSchedule | ConvertTo-Json -Depth 10)
\`\`\`

**Schema Information**
- Object Mappings: $($config.Schema.Mappings.Count) mapping(s) found

"@
        }
    } elseif ($provisioningConfigs) {
        $configContent += @"

### Configuration 1: $($provisioningConfigs.ServicePrincipalName)

**Service Principal Details**
- ID: ``$($provisioningConfigs.ServicePrincipalId)``
- Name: $($provisioningConfigs.ServicePrincipalName)

**Synchronization Job**
- Job ID: ``$($provisioningConfigs.SyncJobId)``
- Status: $($provisioningConfigs.SyncJobStatus)

**Progress**
\`\`\`json
$($provisioningConfigs.SyncJobProgress | ConvertTo-Json -Depth 10)
\`\`\`

**Schedule**
\`\`\`json
$($provisioningConfigs.SyncSchedule | ConvertTo-Json -Depth 10)
\`\`\`

"@
    }
    
    New-MarkdownDoc -Title "Configuration Details" -Content $configContent -OutputFile "$OutputPath/03-ConfigurationDetails.md"
    
    # 5. Create JSON reference documentation
    Write-Host "  Generating JSON reference..." -ForegroundColor Gray
    
    $jsonRefContent = @"
## JSON Configuration References

This section contains the complete JSON exports of all extracted configurations.

### Raw Extracts

The following JSON files contain the raw extracted data:

- **extraction_summary.json** - Summary of all extracted objects
- **workday_service_principals.json** - Service Principal configurations
- **provisioning_configs.json** - Provisioning configurations and sync jobs
- **attribute_mappings.json** - Attribute mapping configurations
- **directory_extensions.json** - Directory extension definitions
- **app_roles.json** - Application role definitions

All JSON files are located in the output directory.

### How to Use These References

1. **For Validation**: Compare against your expected configurations
2. **For Troubleshooting**: Check sync job status and progress
3. **For Audit**: Review extraction date and tenant information
4. **For Migration**: Use as baseline for new tenant setup

"@
    
    New-MarkdownDoc -Title "JSON Reference Guide" -Content $jsonRefContent -OutputFile "$OutputPath/04-JSONReference.md"
    
    # 6. Create Troubleshooting Guide
    Write-Host "  Generating troubleshooting guide..." -ForegroundColor Gray
    
    $troubleshootContent = @"
## Troubleshooting Guide

### Common Issues and Resolutions

#### Issue: No Workday Service Principal Found

**Possible Causes:**
1. Workday app not installed in the tenant
2. Different naming convention used
3. Insufficient permissions to read service principals

**Resolution:**
1. Verify Workday app is installed in Azure AD
2. Check app display name matches expected value
3. Ensure you have Application.Read.All permission
4. Run script with elevated privileges

#### Issue: Provisioning Not Running

**Check Points:**
1. Verify sync job status: Should be "Enabled" or "Running"
2. Check last sync execution time
3. Review provisioning rules for syntax errors
4. Validate attribute mapping expressions

**Resolution Steps:**
1. Navigate to Azure AD > Enterprise Applications > [Workday App]
2. Check Provisioning status and progress
3. Review error logs if any failed operations
4. Test attribute mappings with sample data

#### Issue: Attribute Mappings Not Working

**Validation Steps:**
1. Verify source attributes exist in Workday
2. Check target attribute syntax
3. Review transformation expressions
4. Test with user account directly affected

**Common Mapping Errors:**
- Invalid attribute names
- Type mismatch (string vs. array)
- Scoping rule exclusions
- Conditional attribute mapping not triggered

### Validation Checklist

- [ ] Service Principal is created and enabled
- [ ] Provisioning is set to enabled
- [ ] Attribute mappings are valid JSON
- [ ] Source attributes exist in Workday system
- [ ] Target attributes are correctly formatted
- [ ] Scoping rules are appropriate
- [ ] Test sync has completed without errors
- [ ] User accounts show expected attribute values

"@
    
    New-MarkdownDoc -Title "Troubleshooting Guide" -Content $troubleshootContent -OutputFile "$OutputPath/05-Troubleshooting.md"
    
    # 7. Create index
    Write-Host "  Generating documentation index..." -ForegroundColor Gray
    
    $indexContent = @"
# Workday Provisioning Documentation Index

## Quick Links

1. [Overview](01-Overview.md) - Executive summary and service principals
2. [Attribute Mappings](02-AttributeMappings.md) - Detailed attribute mapping configurations
3. [Configuration Details](03-ConfigurationDetails.md) - Sync job and provisioning details
4. [JSON Reference](04-JSONReference.md) - Reference to raw JSON exports
5. [Troubleshooting](05-Troubleshooting.md) - Common issues and solutions

## Documentation Structure

```
docs/
├── 01-Overview.md              # High-level overview
├── 02-AttributeMappings.md    # All attribute mappings
├── 03-ConfigurationDetails.md # Detailed configurations
├── 04-JSONReference.md        # JSON reference guide
├── 05-Troubleshooting.md      # Troubleshooting guide
├── INDEX.md                    # This file
└── README.md                   # Getting started
```

## Document Descriptions

### 01-Overview.md
Contains the executive summary, discovered service principals, and high-level provisioning flow descriptions.

### 02-AttributeMappings.md
Details all attribute mappings, including source-to-target mappings and transformation rules.

### 03-ConfigurationDetails.md
Contains detailed configuration information for each provisioning job including schedules and sync status.

### 04-JSONReference.md
Guide to the raw JSON files exported during extraction, useful for deep-dive analysis.

### 05-Troubleshooting.md
Troubleshooting guide with common issues, resolutions, and validation checklist.

## Key Metrics

- **Extraction Date**: $($summary.ExtractionDate)
- **Service Principals**: $($summary.WorkdayServicePrincipals.Count)
- **Provisioning Flows**: $($summary.ProvisioningConfigCount)
- **Attribute Mappings**: $($summary.AttributeMappingCount)

## Next Steps

1. Review the Overview document
2. Check attribute mappings against your business requirements
3. Validate configurations using the troubleshooting checklist
4. Monitor provisioning jobs for successful synchronization

"@
    
    New-MarkdownDoc -Title "Documentation Index" -Content $indexContent -OutputFile "$OutputPath/INDEX.md"
    
    Write-Host "`n=== Documentation Generation Complete ===" -ForegroundColor Green
    Write-Host "Documentation saved to: $OutputPath`n" -ForegroundColor Green
    Write-Host "View the documentation by opening: $OutputPath/INDEX.md" -ForegroundColor Cyan
    
}
catch {
    Write-Error "Error during documentation generation: $_"
    exit 1
}
