[cmdletbinding()]
param(
    [string]$VersionFilter = "*",
    [string]$OSFilter = "*",
    [string]$ImageBuilderCustomArgs,
    [switch]$CleanupDocker,
    [switch]$ExcludePathFilter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CleanupDocker()
{
    if ($CleanupDocker) {
        # Windows base images are large, preserve them to avoid the overhead of pulling each time.
        docker images |
            Where-Object {
                -Not ($_.StartsWith("mcr.microsoft.com/windows")`
                -Or $_.StartsWith("REPOSITORY ")) } |
            ForEach-Object { $_.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[2] } |
            Select-Object -Unique |
            ForEach-Object { docker rmi -f $_ }
    }
}

function ExecuteWithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command
    )

    $attempt = 0
    $maxRetries = 5
    $waitFactor = 6
    while ($attempt -lt $maxRetries) {
        try {
            Invoke-Expression -Command "$Command"
            break
        }
        catch {
            Write-Warning "$_"
        }

        $attempt++
        if ($attempt -ne $maxRetries) {
            $waitTime = $attempt * $waitFactor
            Write-Host "Retry ${attempt}/${maxRetries} failed, retrying in $waitTime seconds..."
            Start-Sleep -Seconds ($waitTime)
            Remove-Item -Path "$imageBuilderFolder" -Recurse -Force -ErrorAction Continue
        }
        else {
            throw "Retry ${attempt}/${maxRetries} failed, no more retries left."
        }
    }
}

function Get-ImageBuilder() {
    $imageBuilderImageName = 'microsoft/dotnet-buildtools-prereqs:image-builder-nanoserver-20180227141513'
    $imageBuilderContainerName = "ImageBuilder-$(Get-Date -Format yyyyMMddhhmmss)"
    New-Item -Path "$imageBuilderFolder" -ItemType Directory -Force | Out-Null
    ExecuteWithRetry -Command "docker pull $imageBuilderImageName"
    Invoke-Expression "docker create --name $imageBuilderContainerName $imageBuilderImageName"
    # Copying the 'image-builder' folder and not just the content due to https://github.com/moby/moby/issues/34638
    Invoke-Expression "docker cp ${imageBuilderContainerName}:/image-builder $imageBuilderFolder"
    Invoke-Expression "docker rmi -f $imageBuilderImageName"
}

Invoke-CleanupDocker
$imageBuilderFolder = [System.IO.Path]::Combine("$PSScriptRoot", ".Microsoft.DotNet.ImageBuilder")
$imageBuilderExe = [System.IO.Path]::Combine("$imageBuilderFolder", "image-builder", "Microsoft.DotNet.ImageBuilder.exe")
if (-not (Test-Path -Path "$imageBuilderExe" -PathType Leaf)) {
    Get-ImageBuilder
}

$buildFilter = ""
if (-not $ExcludePathFilter) {
    $buildFilter = "--path $VersionFilter/*/$OSFilter"
}

$imageBuilderArgs = "build $buildFilter --var VersionFilter=$VersionFilter --var OSFilter=$OSFilter"
if (-not [string]::IsNullOrWhiteSpace($ImageBuilderCustomArgs)) {
    $imageBuilderArgs += " $ImageBuilderCustomArgs"
}

try {
    Write-host "Executing '$imageBuilderExe $imageBuilderArgs'"
    Invoke-Expression "$imageBuilderExe $imageBuilderArgs"
    if ($LastExitCode -ne 0) {
        throw "Failed executing $imageBuilderExe $imageBuilderArgs"
    }
}
finally {
    Invoke-CleanupDocker
}
