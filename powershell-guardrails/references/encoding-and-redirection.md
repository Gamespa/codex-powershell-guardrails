# Encoding and Redirection

For exact native stdin bytes, pipe a byte array as one object (`,$bytes`); a
string pipeline can append a platform newline. `$OutputEncoding` controls text
stdin, not that newline or file output. Avoid text round trips for binary data.

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
