<#
.SYNOPSIS
    Analyzes provisioning flows and creates detailed flow diagrams and analysis.
    
.DESCRIPTION
    Creates visual representations and detailed analysis of provisioning flows including:
    - Flow diagrams in ASCII and Mermaid format
    - Attribute transformation mappings
    - Data flow analysis
    - Integration points
    
.PARAMETERS
    -InputPath
        Path containing extracted JSON files
        
    -OutputPath
        Path where analysis will be saved
        
.EXAMPLE
    .\Analyze-ProvisioningFlows.ps1 -InputPath "./output" -OutputPath "./docs"
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

Write-Host "=== Provisioning Flows Analysis ===" -ForegroundColor Cyan
Write-Host "Input Directory: $InputPath" -ForegroundColor Gray
Write-Host "Output Directory: $OutputPath`n" -ForegroundColor Gray

try {
    # Load data
    Write-Host "Loading provisioning data..." -ForegroundColor Cyan
    
    $provisioningConfigs = @()
    $attributeMappings = @()
    
    if (Test-Path "$InputPath/provisioning_configs.json") {
        $provisioningConfigs = Get-Content "$InputPath/provisioning_configs.json" | ConvertFrom-Json
    }
    
    if (Test-Path "$InputPath/attribute_mappings.json") {
        $attributeMappings = Get-Content "$InputPath/attribute_mappings.json" | ConvertFrom-Json
    }
    
    # Create flow analysis document
    Write-Host "Analyzing provisioning flows..." -ForegroundColor Cyan
    
    $flowAnalysis = @"
# Provisioning Flow Analysis

## Overview

This document provides detailed analysis of all Workday provisioning flows configured in your tenant.

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Flow Diagrams

### Main Provisioning Architecture

\`\`\`mermaid
graph LR
    A[Workday System] -->|Extract Employee Data| B[Workday Sync Connector]
    B -->|Transform Attributes| C[Attribute Mapping Engine]
    C -->|Apply Rules| D[Azure AD User Objects]
    D -->|Scoping Filters| E[Provision to Apps]
    E -->|Sync Enabled Apps| F[Connected Applications]
    
    style A fill:#e1f5ff
    style B fill:#fff3e0
    style C fill:#f3e5f5
    style D fill:#e8f5e9
    style E fill:#fce4ec
    style F fill:#f1f8e9
\`\`\`

## Data Flow Analysis

"@
    
    # Analyze each provisioning configuration
    if ($provisioningConfigs) {
        $configs = if ($provisioningConfigs -is [array]) { $provisioningConfigs } else { @($provisioningConfigs) }
        
        foreach ($i = 0; $i -lt $configs.Count; $i++) {
            $config = $configs[$i]
            
            $flowAnalysis += @"

### Flow $($i + 1): $($config.ServicePrincipalName)

#### System Components

\`\`\`mermaid
graph TD
    WD["Workday<br/>($($config.ServicePrincipalName))"]
    WD --> SYNC["Sync Job<br/>ID: $($config.SyncJobId.Substring(0, 8))..."]
    SYNC --> SCHEMA["Schema<br/>Processing"]
    SCHEMA --> MAPPING["Attribute<br/>Mapping"]
    MAPPING --> RULES["Scoping<br/>Rules"]
    RULES --> PROVISION["Provision to<br/>Azure AD"]
    
    style WD fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    style SYNC fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style SCHEMA fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    style MAPPING fill:#fff9c4,stroke:#f57f17,stroke-width:2px
    style RULES fill:#e0f2f1,stroke:#004d40,stroke-width:2px
    style PROVISION fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
\`\`\`

#### Configuration Details

| Property | Value |
|----------|-------|
| Service Principal | $($config.ServicePrincipalName) |
| Service Principal ID | \`$($config.ServicePrincipalId)\` |
| Sync Job ID | \`$($config.SyncJobId)\` |
| Current Status | $($config.SyncJobStatus) |
| Job Type | User Provisioning |

"@
            
            # Find related mappings
            $relatedMappings = if ($attributeMappings -is [array]) { 
                $attributeMappings | Where-Object { $_.SyncJobId -eq $config.SyncJobId } 
            } else {
                if ($attributeMappings.SyncJobId -eq $config.SyncJobId) { $attributeMappings } else { $null }
            }
            
            if ($relatedMappings) {
                $mappingList = if ($relatedMappings -is [array]) { $relatedMappings } else { @($relatedMappings) }
                
                $flowAnalysis += @"

#### Attribute Transformations

Number of object type mappings: **$($mappingList.Count)**

"@
                
                foreach ($mapping in $mappingList) {
                    $flowAnalysis += @"

**Mapping: $($mapping.SourceObjectName) → $($mapping.TargetObjectName)**

\`\`\`mermaid
graph LR
    subgraph Source["Source (Workday)"]
        S1["$($mapping.SourceObjectName)"]
    end
    
    subgraph Transform["Transformation Engine"]
        T1["Parse Attributes"]
        T2["Apply Expressions"]
        T3["Validate Values"]
    end
    
    subgraph Target["Target (Azure AD)"]
        TG1["$($mapping.TargetObjectName)"]
    end
    
    S1 --> T1 --> T2 --> T3 --> TG1
    
    style Source fill:#e1f5ff
    style Transform fill:#fff3e0
    style Target fill:#e8f5e9
\`\`\`

Detailed attribute mappings:
"@
                    
                    try {
                        $attrMappings = $mapping.AttributeMappings | ConvertFrom-Json
                        $mappingList2 = if ($attrMappings -is [array]) { $attrMappings } else { @($attrMappings) }
                        
                        $flowAnalysis += "`n| Workday Attribute | Azure AD Attribute | Type |`n|---|---|---|`n"
                        
                        foreach ($attr in $mappingList2) {
                            $source = if ($attr.source) { $attr.source } else { "N/A" }
                            $target = if ($attr.target) { $attr.target } else { "N/A" }
                            $type = if ($attr.type) { $attr.type } else { "Standard" }
                            $flowAnalysis += "| \`$source\` | \`$target\` | $type |`n"
                        }
                    }
                    catch {
                        $flowAnalysis += "`n[Error parsing attribute mappings]`n"
                    }
                }
            }
        }
    }
    
    $flowAnalysis += @"

## Integration Points

### Workday System Integration

- **Connection**: Azure AD Provisioning Connector for Workday
- **Authentication**: Service Principal with Workday API credentials
- **Data Extraction**: Real-time and scheduled sync
- **Update Frequency**: Configured in sync schedule
- **Scope**: User provisioning and deprovisioning

### Azure AD Integration

- **Target**: Azure AD User Objects
- **Operation**: Create, Update, Delete
- **Filtering**: Scoping rules determine which users are provisioned
- **Attributes**: Mapped through attribute mapping engine
- **Compliance**: Audit logs track all provisioning activities

### Connected Applications

After provisioning to Azure AD, users can be:
1. Synchronized to other cloud apps via Directory Extensions
2. Assigned to applications based on group membership
3. Configured for cloud-only or hybrid scenarios

## Sync Schedule Analysis

"@
    
    if ($provisioningConfigs) {
        $configs = if ($provisioningConfigs -is [array]) { $provisioningConfigs } else { @($provisioningConfigs) }
        
        foreach ($config in $configs) {
            if ($config.SyncSchedule) {
                $schedule = $config.SyncSchedule | ConvertTo-Json -Compress
                $flowAnalysis += @"

### $($config.ServicePrincipalName)

Schedule Configuration:
\`\`\`json
$($config.SyncSchedule | ConvertTo-Json -Depth 5)
\`\`\`

"@
            }
        }
    }
    
    $flowAnalysis += @"

## Data Quality Checks

### Attribute Mapping Validation

All attribute mappings should:
- [ ] Have source attributes that exist in Workday
- [ ] Have valid target attribute names in Azure AD
- [ ] Handle null/empty values appropriately
- [ ] Apply correct data type transformations
- [ ] Include transformation expressions if needed

### Sync Progress Monitoring

Key metrics to monitor:
- **Successful provisions**: Number of users successfully provisioned
- **Failed provisions**: Errors requiring manual remediation
- **Quarantined jobs**: Paused due to errors
- **Last sync time**: Recent activity indicator
- **Sync duration**: Performance baseline

## Troubleshooting Scenarios

### Scenario 1: Users Not Provisioning
1. Check sync job status (should be "Enabled")
2. Verify scoping rules include target users
3. Validate attribute mappings have required fields
4. Review error logs in provisioning activities
5. Test with single user account

### Scenario 2: Incomplete Attribute Mapping
1. Compare source and target attributes
2. Check attribute name spelling and case sensitivity
3. Verify data type conversions
4. Test transformation expressions
5. Review attribute sync rules

### Scenario 3: Performance Issues
1. Check sync schedule interval
2. Review attribute mapping complexity
3. Analyze scoping rule performance
4. Monitor Azure AD API limits
5. Consider staggered sync timing

## Recommendations

1. **Monitor Regularly**: Check sync status weekly
2. **Audit Mappings**: Quarterly attribute mapping review
3. **Test Changes**: Always test in pilot scope first
4. **Document Updates**: Keep this analysis current
5. **Performance Tune**: Optimize attribute mappings for speed

---

**Analysis Complete** - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
    
    $flowAnalysis | Out-File -FilePath "$OutputPath/06-FlowAnalysis.md" -Force
    Write-Host "  ✓ Flow analysis saved to 06-FlowAnalysis.md" -ForegroundColor Green
    
    Write-Host "`n=== Flow Analysis Complete ===" -ForegroundColor Green
    
}
catch {
    Write-Error "Error during flow analysis: $_"
    exit 1
}
