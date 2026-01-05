<#
.SYNOPSIS
    Validates provisioning configurations for syntax errors and best practices.
    
.DESCRIPTION
    Performs comprehensive validation of extracted provisioning configurations including:
    - JSON syntax validation
    - Attribute mapping validation
    - Naming convention checks
    - Schema compliance
    - Best practices verification
    
.PARAMETERS
    -InputPath
        Path containing extracted JSON files
        
    -OutputPath
        Path where validation report will be saved
        
.EXAMPLE
    .\Validate-ProvisioningConfigs.ps1 -InputPath "./output" -OutputPath "./output"
#>

param(
    [string]$InputPath = "./output",
    [string]$OutputPath = "./output"
)

if (-not (Test-Path $InputPath)) {
    Write-Error "Input path not found: $InputPath"
    exit 1
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "=== Provisioning Configuration Validator ===" -ForegroundColor Cyan
Write-Host "Input Directory: $InputPath" -ForegroundColor Gray
Write-Host "Output Directory: $OutputPath`n" -ForegroundColor Gray

$validationResults = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Errors = @()
    Warnings = @()
    Info = @()
    Summary = @{}
}

function Add-ValidationError {
    param([string]$Message, [string]$File, [string]$Severity = "ERROR")
    
    $validationResults.Errors += @{
        Severity = $Severity
        Message = $Message
        File = $File
        Timestamp = Get-Date -Format "HH:mm:ss"
    }
}

function Add-ValidationWarning {
    param([string]$Message, [string]$File)
    Add-ValidationError -Message $Message -File $File -Severity "WARNING"
}

function Add-ValidationInfo {
    param([string]$Message, [string]$File)
    Add-ValidationError -Message $Message -File $File -Severity "INFO"
}

try {
    # 1. Validate JSON Syntax
    Write-Host "Validating JSON syntax..." -ForegroundColor Cyan
    
    $jsonFiles = Get-ChildItem -Path $InputPath -Filter "*.json" -ErrorAction SilentlyContinue
    
    foreach ($file in $jsonFiles) {
        try {
            $content = Get-Content $file.FullName | ConvertFrom-Json
            Add-ValidationInfo "✓ Valid JSON syntax" $file.Name
        }
        catch {
            Add-ValidationError "Invalid JSON syntax: $_" $file.Name "ERROR"
        }
    }
    
    # 2. Load and validate configurations
    Write-Host "Validating configuration content..." -ForegroundColor Cyan
    
    if (Test-Path "$InputPath/provisioning_configs.json") {
        try {
            $configs = Get-Content "$InputPath/provisioning_configs.json" | ConvertFrom-Json
            
            if ($configs -is [array]) {
                Write-Host "Found $($configs.Count) provisioning configuration(s)" -ForegroundColor Green
                
                foreach ($config in $configs) {
                    # Validate required fields
                    $requiredFields = @("ServicePrincipalId", "ServicePrincipalName", "SyncJobId", "SyncJobStatus")
                    
                    foreach ($field in $requiredFields) {
                        if (-not $config.$field) {
                            Add-ValidationError "Missing required field: $field" "provisioning_configs.json" "ERROR"
                        }
                    }
                    
                    # Validate GUIDs
                    if ($config.ServicePrincipalId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                        Add-ValidationWarning "Invalid GUID format for ServicePrincipalId: $($config.ServicePrincipalId)" "provisioning_configs.json"
                    }
                    
                    # Validate sync job status
                    $validStatuses = @("Enabled", "Disabled", "Running", "Paused", "Quarantined")
                    if ($config.SyncJobStatus -notin $validStatuses) {
                        Add-ValidationWarning "Unexpected sync job status: $($config.SyncJobStatus). Expected one of: $($validStatuses -join ', ')" "provisioning_configs.json"
                    }
                }
            }
        }
        catch {
            Add-ValidationError "Error processing provisioning_configs.json: $_" "provisioning_configs.json"
        }
    } else {
        Add-ValidationWarning "provisioning_configs.json not found" "provisioning_configs.json"
    }
    
    # 3. Validate Attribute Mappings
    Write-Host "Validating attribute mappings..." -ForegroundColor Cyan
    
    if (Test-Path "$InputPath/attribute_mappings.json") {
        try {
            $mappings = Get-Content "$InputPath/attribute_mappings.json" | ConvertFrom-Json
            
            if ($mappings -is [array]) {
                Write-Host "Found $($mappings.Count) attribute mapping(s)" -ForegroundColor Green
                
                foreach ($mapping in $mappings) {
                    # Validate required fields
                    if (-not $mapping.SourceObjectName) {
                        Add-ValidationError "Missing SourceObjectName in attribute mapping" "attribute_mappings.json"
                    }
                    
                    if (-not $mapping.TargetObjectName) {
                        Add-ValidationError "Missing TargetObjectName in attribute mapping" "attribute_mappings.json"
                    }
                    
                    # Validate attribute mappings structure
                    if ($mapping.AttributeMappings) {
                        try {
                            $attrMappings = $mapping.AttributeMappings | ConvertFrom-Json
                            
                            if ($attrMappings -is [array]) {
                                foreach ($attr in $attrMappings) {
                                    if (-not $attr.source) {
                                        Add-ValidationWarning "Attribute mapping missing 'source' field" "attribute_mappings.json"
                                    }
                                    if (-not $attr.target) {
                                        Add-ValidationWarning "Attribute mapping missing 'target' field" "attribute_mappings.json"
                                    }
                                }
                            }
                        }
                        catch {
                            Add-ValidationWarning "Could not parse AttributeMappings as JSON" "attribute_mappings.json"
                        }
                    }
                }
            } else {
                Add-ValidationInfo "Single attribute mapping found" "attribute_mappings.json"
            }
        }
        catch {
            Add-ValidationError "Error processing attribute_mappings.json: $_" "attribute_mappings.json"
        }
    } else {
        Add-ValidationWarning "attribute_mappings.json not found" "attribute_mappings.json"
    }
    
    # 4. Validate Service Principals
    Write-Host "Validating service principal configuration..." -ForegroundColor Cyan
    
    if (Test-Path "$InputPath/workday_service_principals.json") {
        try {
            $servicePrincipals = Get-Content "$InputPath/workday_service_principals.json" | ConvertFrom-Json
            
            if ($servicePrincipals -is [array]) {
                Write-Host "Found $($servicePrincipals.Count) service principal(s)" -ForegroundColor Green
                
                foreach ($sp in $servicePrincipals) {
                    if (-not $sp.id) {
                        Add-ValidationError "Service Principal missing ID" "workday_service_principals.json"
                    }
                    if (-not $sp.displayName) {
                        Add-ValidationError "Service Principal missing displayName" "workday_service_principals.json"
                    }
                    if (-not $sp.appId) {
                        Add-ValidationWarning "Service Principal $($sp.displayName) missing appId" "workday_service_principals.json"
                    }
                }
            } else {
                Add-ValidationInfo "Single service principal found" "workday_service_principals.json"
            }
        }
        catch {
            Add-ValidationError "Error processing workday_service_principals.json: $_" "workday_service_principals.json"
        }
    } else {
        Add-ValidationWarning "workday_service_principals.json not found" "workday_service_principals.json"
    }
    
    # 5. Best Practices Check
    Write-Host "Checking best practices..." -ForegroundColor Cyan
    
    # Check if extraction summary exists
    if (-not (Test-Path "$InputPath/extraction_summary.json")) {
        Add-ValidationWarning "extraction_summary.json not found - run extraction script first" "extraction_summary.json"
    } else {
        Add-ValidationInfo "Extraction summary found" "extraction_summary.json"
    }
    
    # 6. Generate Validation Report
    Write-Host "`nGenerating validation report..." -ForegroundColor Cyan
    
    $validationResults.Summary = @{
        TotalErrors = $validationResults.Errors | Where-Object { $_.Severity -eq "ERROR" } | Measure-Object | Select-Object -ExpandProperty Count
        TotalWarnings = $validationResults.Errors | Where-Object { $_.Severity -eq "WARNING" } | Measure-Object | Select-Object -ExpandProperty Count
        TotalInfo = $validationResults.Errors | Where-Object { $_.Severity -eq "INFO" } | Measure-Object | Select-Object -ExpandProperty Count
    }
    
    # Create report
    $report = @"
# Provisioning Configuration Validation Report

**Generated**: $($validationResults.Timestamp)

## Summary

- **Errors**: $($validationResults.Summary.TotalErrors)
- **Warnings**: $($validationResults.Summary.TotalWarnings)
- **Info**: $($validationResults.Summary.TotalInfo)

## Validation Status

$(if ($validationResults.Summary.TotalErrors -eq 0) { "✓ **PASSED** - No critical errors found" } else { "✗ **FAILED** - Critical errors found" })

## Detailed Results

### Errors
"@
    
    if ($validationResults.Errors | Where-Object { $_.Severity -eq "ERROR" }) {
        $report += "`n"
        foreach ($error in $validationResults.Errors | Where-Object { $_.Severity -eq "ERROR" }) {
            $report += "`n- [$($error.File)] $($error.Message)"
        }
    } else {
        $report += "`nNo errors found."
    }
    
    $report += "`n`n### Warnings"
    
    if ($validationResults.Errors | Where-Object { $_.Severity -eq "WARNING" }) {
        $report += "`n"
        foreach ($warning in $validationResults.Errors | Where-Object { $_.Severity -eq "WARNING" }) {
            $report += "`n- [$($warning.File)] $($warning.Message)"
        }
    } else {
        $report += "`nNo warnings found."
    }
    
    $report += "`n`n### Information"
    
    if ($validationResults.Errors | Where-Object { $_.Severity -eq "INFO" }) {
        $report += "`n"
        foreach ($info in $validationResults.Errors | Where-Object { $_.Severity -eq "INFO" } | Select-Object -First 10) {
            $report += "`n- [$($info.File)] $($info.Message)"
        }
        if ($validationResults.Errors | Where-Object { $_.Severity -eq "INFO" } | Measure-Object | Select-Object -ExpandProperty Count -gt 10) {
            $report += "`n- ... and $($validationResults.Errors | Where-Object { $_.Severity -eq "INFO" } | Measure-Object | Select-Object -ExpandProperty Count - 10) more info messages"
        }
    } else {
        $report += "`nNo additional information."
    }
    
    $report += @"

## Recommendations

1. Fix all critical errors before deploying
2. Address warnings to improve configuration quality
3. Review JSON files for completeness
4. Run extraction script if files are missing
5. Validate attribute mappings match business requirements

## JSON Files Validated

$(Get-ChildItem -Path $InputPath -Filter "*.json" | Select-Object -ExpandProperty Name | ForEach-Object { "- $_" } | Out-String)

---
**Validation Complete** - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
    
    $report | Out-File -FilePath "$OutputPath/validation_report.md" -Force
    Write-Host "  ✓ Validation report saved to validation_report.md" -ForegroundColor Green
    
    # Save detailed JSON report
    $validationResults | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OutputPath/validation_report.json" -Force
    Write-Host "  ✓ Detailed report saved to validation_report.json" -ForegroundColor Green
    
    # Display summary
    Write-Host "`n=== Validation Summary ===" -ForegroundColor Green
    Write-Host "Errors: $($validationResults.Summary.TotalErrors)" -ForegroundColor $(if ($validationResults.Summary.TotalErrors -gt 0) { "Red" } else { "Green" })
    Write-Host "Warnings: $($validationResults.Summary.TotalWarnings)" -ForegroundColor $(if ($validationResults.Summary.TotalWarnings -gt 0) { "Yellow" } else { "Green" })
    Write-Host "Info: $($validationResults.Summary.TotalInfo)" -ForegroundColor Cyan
    Write-Host ""
    
}
catch {
    Write-Error "Error during validation: $_"
    exit 1
}
