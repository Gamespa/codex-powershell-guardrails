# SSH and Encoding

## SSH and Unix-bound text

A tiny remote command without local interpolation can be one single-quoted
argument. For remote `$()`, heredocs, embedded languages, or several quoting
layers, pass a literal script via stdin:

```powershell
$remoteScript = @'
set -euo pipefail
cd /srv/app
printf 'user=%s\n' "$(id -un)"
'@
$previousEncoding = $OutputEncoding
try {
  $OutputEncoding = [Text.UTF8Encoding]::new($false)
  ($remoteScript -replace "`r`n", "`n") | ssh my-host bash -s
  $remoteExit = $LASTEXITCODE
} finally {
  $OutputEncoding = $previousEncoding
}
if ($remoteExit -ne 0) { throw "Remote script failed: $remoteExit" }
```

The encoding wrapper matters in Windows PowerShell 5.1 or when the native
stdin preference has been overridden. A known PowerShell 7 UTF-8 session
usually needs only LF normalization; LF alone does not guarantee UTF-8.

Uploaded file encoding is separate from native stdin encoding. Windows
PowerShell 5.1 writes a BOM with `-Encoding utf8`; PowerShell 7 does not:

```powershell
$scriptLf = $remoteScript -replace "`r`n", "`n"
[IO.File]::WriteAllText($scriptPath, $scriptLf, [Text.UTF8Encoding]::new($false))
scp $scriptPath my-host:/tmp/script.sh
if ($LASTEXITCODE -ne 0) { throw 'Script upload failed' }
ssh my-host bash /tmp/script.sh
if ($LASTEXITCODE -ne 0) { throw 'Remote script failed' }
```

Use unique remote paths for concurrent runs and clean up within the authorized
scope. Transfer exact binary bytes through a binary-safe file or explicit byte
stream. Base64 can help at text-only boundaries, but does not protect secrets.

`bash -s` consumes stdin. Programs inside it can also read and consume script
text. Upload the script or provide a separate protected input channel when a
remote program needs stdin data.

For remote searches, handle expected no-match statuses under `set -e`.
With `pipefail`, `head` can give the producer SIGPIPE. Use a consumer that
drains input or handle that pipeline's status deliberately. `sed -n '1,50p'`
limits displayed lines but still reads the full stream and does not reduce
search work.

For remote secret input, see [Sensitive data](execution-and-lifecycle.md#sensitive-data).

## Source

- [PowerShell character encoding](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding)
