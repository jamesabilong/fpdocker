[CmdletBinding()]
param(
    [string]$Hostname = "freshprice-local.com",
    [string]$CertificatePath = "$env:USERPROFILE\Downloads\freshprice-rootCA.crt"
)

$ErrorActionPreference = "Stop"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $arguments = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", ('"{0}"' -f $PSCommandPath)
        "-Hostname", ('"{0}"' -f $Hostname)
        "-CertificatePath", ('"{0}"' -f $CertificatePath)
    )
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Elevated local-domain setup failed with exit code $($process.ExitCode)."
    }
    exit 0
}

if ($Hostname -notmatch '^[a-zA-Z0-9.-]+$') {
    throw "Hostname contains unsupported characters: $Hostname"
}

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsLines = Get-Content -LiteralPath $hostsPath
$obsoleteHostnames = @("freshprice.test")
foreach ($obsoleteHostname in $obsoleteHostnames) {
    if ($obsoleteHostname -ne $Hostname) {
        $obsoletePattern = "^\s*127\.0\.0\.1\s+$([regex]::Escape($obsoleteHostname))\s*$"
        $hostsLines = @($hostsLines | Where-Object { $_ -notmatch $obsoletePattern })
    }
}

$hostsLines | Set-Content -LiteralPath $hostsPath
$escapedHostname = [regex]::Escape($Hostname)
$mappingPattern = "^\s*127\.0\.0\.1\s+.*(?:\s|^)$escapedHostname(?:\s|$)"

if (-not ($hostsLines | Where-Object { $_ -match $mappingPattern })) {
    Add-Content -LiteralPath $hostsPath -Value "127.0.0.1 $Hostname"
    Write-Host "Added $Hostname to the Windows hosts file."
} else {
    Write-Host "$Hostname is already present in the Windows hosts file."
}

if (Test-Path -LiteralPath $CertificatePath) {
    Import-Certificate -FilePath $CertificatePath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
    Write-Host "Trusted the FreshPrice development CA for the current user."
} else {
    Write-Warning "Certificate not found at $CertificatePath; hostname setup still completed."
}

Clear-DnsClientCache
Write-Host "Local URL: http://${Hostname}:5173"
