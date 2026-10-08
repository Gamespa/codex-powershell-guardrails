$stdinProbe = Write-Fixture 'read-stdin.ps1' @'
$stream = [Console]::OpenStandardInput()
$buffer = [IO.MemoryStream]::new()
$stream.CopyTo($buffer)
[Convert]::ToBase64String($buffer.ToArray())
'@
$unicodeText = 'printf "' + [char]0x4F60 + [char]0x597D + '"' + "`r`n"
$normalizedText = $unicodeText -replace "`r`n", "`n"
$previousEncoding = $OutputEncoding
try {
  $OutputEncoding = [Text.UTF8Encoding]::new($false)
  $encodedInput = $normalizedText | & $childShell -NoLogo -NoProfile -NonInteractive -File $stdinProbe
  $stdinExit = $LASTEXITCODE
} finally {
  $OutputEncoding = $previousEncoding
}
$stdinBytes = [Convert]::FromBase64String($encodedInput)
$expectedTextInput = [Text.Encoding]::UTF8.GetBytes($normalizedText + [Environment]::NewLine)
Assert-Behavior ($stdinExit -eq 0 -and [Convert]::ToBase64String($stdinBytes) -ceq [Convert]::ToBase64String($expectedTextInput)) 'Native text stdin newline contract changed.'
$exactBytes = [Text.Encoding]::UTF8.GetBytes($normalizedText)
$encodedBytes = ,$exactBytes | & $childShell -NoLogo -NoProfile -NonInteractive -File $stdinProbe
$byteInputExit = $LASTEXITCODE
Assert-Behavior ($byteInputExit -eq 0 -and $encodedBytes -ceq [Convert]::ToBase64String($exactBytes)) 'Exact UTF-8 stdin bytes or LF changed.'
$utf8Path = Join-Path $fixtureRoot 'unix-script.sh'
Set-Content -LiteralPath $utf8Path -Value $normalizedText -Encoding utf8NoBOM -NoNewline
$fileBytes = [IO.File]::ReadAllBytes($utf8Path)
Assert-Behavior ($fileBytes[0] -ne 0xEF -and [Text.Encoding]::UTF8.GetString($fileBytes) -ceq $normalizedText) 'Unix file encoding or LF changed.'

$binaryProbe = Write-Fixture 'write-bytes.ps1' @'
$bytes = [byte[]]@(0, 255, 13, 10, 128, 65)
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
'@
$binaryPath = Join-Path $fixtureRoot 'native-output.bin'
& $childShell -NoLogo -NoProfile -NonInteractive -File $binaryProbe > $binaryPath
$binaryExit = $LASTEXITCODE
Assert-Behavior ($binaryExit -eq 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($binaryPath)) -ceq [Convert]::ToBase64String([byte[]]@(0, 255, 13, 10, 128, 65))) 'Native stdout redirection changed binary bytes.'
$pipedBinary = & $childShell -NoLogo -NoProfile -NonInteractive -File $binaryProbe | & $childShell -NoLogo -NoProfile -NonInteractive -File $stdinProbe
$binaryPipeExit = $LASTEXITCODE
Assert-Behavior ($binaryPipeExit -eq 0 -and $pipedBinary -ceq [Convert]::ToBase64String([byte[]]@(0, 255, 13, 10, 128, 65))) 'Native-to-native pipe changed binary bytes.'

$literalPath = Write-Fixture 'report[1].txt' 'literal-file'
Assert-Behavior ((Get-Content -LiteralPath $literalPath -Raw) -ceq 'literal-file') 'Literal bracket path did not identify the exact file.'
Assert-Behavior ((Test-Path -LiteralPath $literalPath) -or (Test-Path -LiteralPath (Join-Path $fixtureRoot 'missing.txt'))) 'Grouped cmdlet logical expression failed.'
foreach ($resultCount in @(0, 1, 2)) {
  $items = @(for ($itemIndex = 0; $itemIndex -lt $resultCount; $itemIndex++) {
    [pscustomobject]@{ Nested = [pscustomobject]@{ Child = [pscustomobject]@{ Value = $itemIndex } } }
  })
  $serialized = ConvertTo-Json -InputObject $items -Depth 4 -Compress
  $roundTrip = ConvertFrom-Json -InputObject $serialized -NoEnumerate
  Assert-Behavior ($roundTrip -is [array] -and $roundTrip.Count -eq $resultCount) "JSON array shape changed for $resultCount results."
  if ($resultCount -gt 0) {
    Assert-Behavior ($roundTrip[0].Nested.Child.Value -eq 0) 'Nested JSON data was lost.'
  }
}
$appendPath = Join-Path $fixtureRoot 'utf16-log.txt'
Set-Content -LiteralPath $appendPath -Value $unicodeText -Encoding unicode -NoNewline
Add-Content -LiteralPath $appendPath -Value $unicodeText -Encoding unicode -NoNewline
Assert-Behavior ((Get-Content -LiteralPath $appendPath -Raw -Encoding unicode) -ceq ($unicodeText + $unicodeText)) 'Appending with the existing encoding corrupted text.'
