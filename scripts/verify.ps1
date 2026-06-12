Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $scriptRoot 'verify-skill.ps1')
git diff --check

Write-Host 'Repository validation chain passed.'
