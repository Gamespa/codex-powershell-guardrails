# SSH and Encoding

## SSH and Unix-bound text

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

For remote secret input, see [Sensitive data](execution-and-lifecycle.md#sensitive-data).

## File encoding and redirection

Choose encoding and newlines for the consumer. Bash script files normally need
LF and UTF-8 without BOM; other text protocols can have different contracts.
Text files default to UTF-8 without BOM. Preserve a different known consumer
encoding, including ANSI/OEM or BOM requirements, when explicitly needed.

Direct native stdout redirection (`tool.exe > file`) and
native-to-native pipes preserve bytes. Inserting a text cmdlet or merging
stderr with `2>&1` loses this guarantee. Use separate stderr logs for binary
output and check the native exit code. `$OutputEncoding` and `chcp` do not
set the encoding of cmdlet-written files.

`Get-Content` without `-Raw` returns lines without their terminators. Use
`-Raw` for a complete text document and byte APIs for binary data. For PowerShell
objects, `Out-File` and `>` produce display formatting that can truncate fields;
use a serializer for machine-readable output.

When appending text, match the existing encoding. `Out-File -Append` and text
`>>` do not detect it; `Add-Content` detects a BOM but assumes UTF-8 for BOM-less
files. Establish an unknown file's encoding before rewriting or appending.

## Sources

- [PowerShell character encoding](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding)
- [Native byte redirection](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection#example-7-redirecting-binary-data-from-a-native-command)
