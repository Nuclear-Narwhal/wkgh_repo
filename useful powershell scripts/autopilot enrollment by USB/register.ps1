# ============================================
# Autopilot Hash Registration Script
# Waits for profile assignment before reboot
# ============================================

# === CONFIG: Edit these five values ===
$TenantId    = "TENANT ID HERE"
$AppId       = "APP ID HERE"
$AppSecret   = "APP SECRET HERE"
$GroupTag    = "GROUP TAG HERE"
$ProfileName = "PROFILE NAME HERE"
# =======================================

# Suppress prompts globally
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
$env:POWERSHELL_TELEMETRY_OPTOUT = 1

$PSDefaultParameterValues = @{
    'Install-Module:Force'           = $true
    'Install-Module:Confirm'         = $false
    'Install-Module:AllowClobber'    = $true
    'Install-Script:Force'           = $true
    'Install-Script:Confirm'         = $false
    'Install-PackageProvider:Force'  = $true
    'Install-PackageProvider:Confirm'= $false
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogFile = "C:\Autopilot\register.log"
Start-Transcript -Path $LogFile -Append | Out-Null

Write-Host "================================" -ForegroundColor Cyan
Write-Host " Autopilot Registration" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

$success = $false

try {
    Write-Host "`n[1/5] Preparing PowerShell environment..." -ForegroundColor Yellow
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    Write-Host "[2/5] Installing Get-WindowsAutopilotInfo..." -ForegroundColor Yellow
    Install-Script -Name Get-WindowsAutopilotInfo -Force -Confirm:$false | Out-Null

    Write-Host "[3/5] Uploading hardware hash to tenant..." -ForegroundColor Yellow
    Get-WindowsAutopilotInfo -Online `
        -TenantId $TenantId `
        -AppId $AppId `
        -AppSecret $AppSecret `
        -GroupTag $GroupTag

    $serial = (Get-WmiObject -Class Win32_BIOS).SerialNumber.Trim()
    Write-Host "Device serial: $serial" -ForegroundColor Green

    # Get Graph token
    $tokenBody = @{
        client_id     = $AppId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $AppSecret
        grant_type    = "client_credentials"
    }
    $tokenResponse = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method Post `
        -Body $tokenBody `
        -ContentType "application/x-www-form-urlencoded"
    $headers = @{ Authorization = "Bearer $($tokenResponse.access_token)" }

    Write-Host "`n[4/5] Looking up deployment profile '$ProfileName'..." -ForegroundColor Yellow
    $profileResult = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$filter=displayName eq '$ProfileName'" `
        -Headers $headers -Method Get -ErrorAction Stop

    if (-not $profileResult.value -or $profileResult.value.Count -eq 0) {
        throw "Deployment profile '$ProfileName' not found. Check the name in config."
    }
    $profileId = $profileResult.value[0].id
    Write-Host "  Profile found (ID: $profileId)" -ForegroundColor Green

    Write-Host "`n[5/5] Waiting for device to appear in profile's assigned devices..." -ForegroundColor Yellow
    Write-Host "(This can take up to 15 minutes)" -ForegroundColor Gray

    # Poll assignedDevices (max 15 min, 15s intervals)
    $maxAttempts = 60
    $attempt = 0
    $assignmentReady = $false

    while ($attempt -lt $maxAttempts -and -not $assignmentReady) {
        $attempt++
        Write-Host "  Attempt $attempt/$maxAttempts - checking assigned devices..." -ForegroundColor Gray

        try {
            $url = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$profileId/assignedDevices"
            $assigned = @()
            do {
                $result = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
                $assigned += $result.value
                $url = $result.'@odata.nextLink'
            } while ($url)

            $match = $assigned | Where-Object { $_.serialNumber.Trim() -eq $serial }

            if ($match) {
                $assignmentReady = $true
                Write-Host "  Device is in assigned devices!" -ForegroundColor Green
                Write-Host "    Serial:           $($match.serialNumber)"
                Write-Host "    Manufacturer:     $($match.manufacturer)"
                Write-Host "    Model:            $($match.model)"
                Write-Host "    Group Tag:        $(if ($match.groupTag) { $match.groupTag } else { '(none)' })"
                Write-Host "    Assignment Status: $($match.deploymentProfileAssignmentStatus)"
                Write-Host "    Profile:          $ProfileName"
                break
            }
            else {
                Write-Host "    Not in assigned devices yet ($($assigned.Count) device(s) in profile)." -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "    Query error (will retry): $_" -ForegroundColor Gray
        }

        Start-Sleep -Seconds 15
    }

    if ($assignmentReady) {
        $success = $true
        Write-Host "`n=============================================" -ForegroundColor Green
        Write-Host "  REGISTRATION + ASSIGNMENT SUCCESSFUL" -ForegroundColor Green
        Write-Host "=============================================" -ForegroundColor Green
        Write-Host "Waiting 60 seconds before reboot..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
    }
    else {
        Write-Host "`n=============================================" -ForegroundColor Yellow
        Write-Host "  REGISTERED BUT NOT IN ASSIGNED DEVICES" -ForegroundColor Yellow
        Write-Host "=============================================" -ForegroundColor Yellow
        Write-Host "Device did not appear in '$ProfileName' within 15 minutes."
        Write-Host "Check that the group tag matches the profile's dynamic group rule."
        Write-Host "DO NOT proceed to OOBE without manual verification."
    }
}
catch {
    Write-Host "`n=============================================" -ForegroundColor Red
    Write-Host "  ERROR DURING REGISTRATION" -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
}
finally {
    $AppSecret = $null
    $tokenResponse = $null
    $headers = $null
    $tokenBody = $null
    Stop-Transcript | Out-Null
}

if ($success) {
    Write-Host ""
    for ($i = 10; $i -gt 0; $i--) {
        Write-Host "`r  Running sysprep in $i second(s)...  " -NoNewline -ForegroundColor Cyan
        Start-Sleep -Seconds 1
    }
    Write-Host ""
    Start-Process -WindowStyle Hidden cmd.exe -ArgumentList '/c del /F /Q "C:\Autopilot\register.ps1" && del /F /Q "C:\Autopilot\register.log" && rmdir /S /Q "C:\Autopilot" && C:\Windows\System32\Sysprep\sysprep.exe /oobe /reboot /quiet'
    exit 0
} else {
    Write-Host "`nPress any key to clean up and shut down (NOT reboot)..." -ForegroundColor Yellow
    [Console]::ReadKey($true) | Out-Null
    Start-Process -WindowStyle Hidden cmd.exe -ArgumentList '/c del /F /Q "C:\Autopilot\register.ps1" && del /F /Q "C:\Autopilot\register.log" && rmdir /S /Q "C:\Autopilot" && shutdown /s /t 0'
    exit 1
}
