# SSH Payloads

A tiny remote command without local interpolation can be one single-quoted
argument. For remote `$()`, heredocs, embedded languages, or several quoting
layers, pass a literal script as UTF-8 bytes via stdin:

```powershell
$remoteScript = @'
set -euo pipefail
cd /srv/app
printf 'user=%s\n' "$(id -un)"
'@
$scriptLf = $remoteScript -replace "`r`n", "`n"
$scriptBytes = [Text.Encoding]::UTF8.GetBytes($scriptLf)
,$scriptBytes | ssh my-host bash -s
$remoteExit = $LASTEXITCODE
if ($remoteExit -ne 0) { throw "Remote script failed: $remoteExit" }
```

The leading comma keeps the byte array as one pipeline object. This sends the
encoded bytes without text conversion or an appended platform newline.
Piping a string instead can append CRLF on Windows even after LF normalization.
`$OutputEncoding` controls text sent to native stdin; it neither removes that
newline nor controls file output. Do not use a text round trip for exact bytes.

Uploading a file is another way to preserve a script's byte contract:

```powershell
$scriptLf = $remoteScript -replace "`r`n", "`n"
Set-Content -LiteralPath $scriptPath -Value $scriptLf -Encoding utf8NoBOM -NoNewline
scp $scriptPath my-host:/tmp/script.sh
if ($LASTEXITCODE -ne 0) { throw 'Script upload failed' }
ssh my-host bash /tmp/script.sh
if ($LASTEXITCODE -ne 0) { throw 'Remote script failed' }
```

Use unique remote paths for concurrent runs and clean up within the authorized
scope. Base64 can help at text-only boundaries, but does not protect secrets.

`bash -s` consumes stdin. Programs inside it can also read and consume script
text. Upload the script or provide a separate protected input channel when a
remote program needs stdin data.

For remote searches, handle expected no-match statuses under `set -e`.
With `pipefail`, `head` can give the producer SIGPIPE. Use a consumer that
drains input or handle that pipeline's status deliberately. `sed -n '1,50p'`
limits displayed lines but still reads the full stream and does not reduce
search work.

For remote secret input, see [Sensitive data](sensitive-data.md).
