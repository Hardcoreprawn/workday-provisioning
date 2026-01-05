<#
.SYNOPSIS
    Master orchestration script - Runs all analysis steps in sequence.
    
.DESCRIPTION
    Executes the complete Workday provisioning analysis workflow:
    1. Extracts all Workday objects from Entra
    2. Generates comprehensive documentation
    3. Validates all configurations
    4. Analyzes provisioning flows
    
.EXAMPLE
    .\RUN-ALL.ps1
#>

$ErrorActionPreference = "Stop"

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir = Join-Path $scriptDir "output"
$docsDir = Join-Path $scriptDir "docs"

Write-Host @"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║        WORKDAY PROVISIONING ANALYSIS SUITE - MASTER RUN       ║
║                                                                ║
║  This script will execute the complete analysis workflow:     ║
║  1. Extract all Workday objects from Entra                    ║
║  2. Generate comprehensive documentation                      ║
║  3. Validate all configurations                               ║
║  4. Analyze provisioning flows                                ║
║                                                                ║
║  Output will be saved to:                                     ║
║  • output/    - Extracted JSON files                          ║
║  • docs/      - Generated documentation                       ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Create directories if they don't exist
@($outputDir, $docsDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

$steps = @(
    @{
        Name = "Extract Workday Objects from Entra"
        Script = "Get-WorkdayEntraObjects.ps1"
        Args = @("-OutputPath", "`"$outputDir`"")
        Number = 1
    },
    @{
        Name = "Generate Documentation"
        Script = "Document-ProvisioningFlows.ps1"
        Args = @("-InputPath", "`"$outputDir`"", "-OutputPath", "`"$docsDir`"")
        Number = 2
    },
    @{
        Name = "Validate Configurations"
        Script = "Validate-ProvisioningConfigs.ps1"
        Args = @("-InputPath", "`"$outputDir`"", "-OutputPath", "`"$outputDir`"")
        Number = 3
    },
    @{
        Name = "Analyze Provisioning Flows"
        Script = "Analyze-ProvisioningFlows.ps1"
        Args = @("-InputPath", "`"$outputDir`"", "-OutputPath", "`"$docsDir`"")
        Number = 4
    }
)

$successCount = 0
$failureCount = 0
$startTime = Get-Date

foreach ($step in $steps) {
    Write-Host "`n" -ForegroundColor Gray
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "STEP $($step.Number) of $($steps.Count): $($step.Name)" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
    
    $scriptPath = Join-Path $scriptDir "scripts" $step.Script
    
    if (-not (Test-Path $scriptPath)) {
        Write-Host "✗ ERROR: Script not found: $scriptPath" -ForegroundColor Red
        $failureCount++
        continue
    }
    
    try {
        Write-Host "Executing: $($step.Script)" -ForegroundColor Yellow
        Write-Host "Parameters: $($step.Args -join ' ')" -ForegroundColor Gray
        Write-Host ""
        
        # Execute the script
        $stepStartTime = Get-Date
        & $scriptPath @($step.Args | Where-Object { $_ })
        $stepDuration = (Get-Date) - $stepStartTime
        
        Write-Host ""
        Write-Host "✓ STEP $($step.Number) COMPLETED" -ForegroundColor Green
        Write-Host "  Duration: $($stepDuration.TotalSeconds) seconds" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host ""
        Write-Host "✗ STEP $($step.Number) FAILED" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        $failureCount++
        
        Write-Host ""
        Write-Host "Would you like to continue with remaining steps? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        
        if ($response -notmatch '^[Yy]') {
            break
        }
    }
}

# Summary report
$totalDuration = (Get-Date) - $startTime

Write-Host @"

╔════════════════════════════════════════════════════════════════╗
║                      EXECUTION SUMMARY                         ║
╚════════════════════════════════════════════════════════════════╝

Total Steps: $($steps.Count)
Successful: $successCount ✓
Failed: $failureCount $(if ($failureCount -gt 0) { '✗' } else { '' })
Total Duration: $($totalDuration.TotalSeconds) seconds

"@ -ForegroundColor Cyan

if ($failureCount -eq 0) {
    Write-Host "✓ ALL STEPS COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "1. Review the documentation in: $docsDir" -ForegroundColor Yellow
    Write-Host "2. Check validation report: $outputDir\validation_report.md" -ForegroundColor Yellow
    Write-Host "3. View extracted configurations: $outputDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Start with: $docsDir\INDEX.md" -ForegroundColor Green
} else {
    Write-Host "⚠ SOME STEPS FAILED - Review errors above" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Output Directory: $outputDir" -ForegroundColor Gray
Write-Host "Docs Directory: $docsDir" -ForegroundColor Gray
Write-Host ""
