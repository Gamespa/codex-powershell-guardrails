# Compatibility shim; new maintenance code imports lib/trace.psm1 directly.
Import-Module (Join-Path $PSScriptRoot 'lib/trace.psm1')
