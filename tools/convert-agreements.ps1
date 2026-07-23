# Convert generated Purchase Agreements from .docx to PDF using Word's own
# exporter, so the PDF mirrors the Word document exactly — same layout, same
# fonts, real selectable text. This replaces opening each document in Word and
# doing Save As by hand.
#
# Scans every parcel folder under Hot Springs, converts any Purchase Agreement
# .docx that has no matching PDF, and leaves the PDF beside it in the same
# parcel folder.
#
#   .\tools\convert-agreements.ps1              # convert what's missing
#   .\tools\convert-agreements.ps1 -Force       # re-convert everything
#   .\tools\convert-agreements.ps1 -Parcel 452-00145
#
# Word must be installed. It runs hidden; you can keep working while it does.

param(
  [string]$Root   = "C:\Users\Elk Ceek Group\Dropbox\Arkansas\Hot Springs",
  [string]$Parcel = "",
  [switch]$Force
)

$ErrorActionPreference = 'Continue'
$wdExportFormatPDF = 17

if (-not (Test-Path $Root)) { Write-Error "Root folder not found: $Root"; exit 1 }

$searchRoot = if ($Parcel) { Join-Path $Root $Parcel } else { $Root }
if (-not (Test-Path $searchRoot)) { Write-Error "Parcel folder not found: $searchRoot"; exit 1 }

$docs = Get-ChildItem -Path $searchRoot -Recurse -Filter "*.docx" |
        Where-Object { $_.Name -like "Purchase_Agreement*" -and $_.Name -notlike "~`$*" }

if (-not $docs) { Write-Output "No Purchase Agreement .docx files found under $searchRoot"; exit 0 }

# One Word instance for the whole batch. It is recreated if a conversion kills
# it — COM occasionally drops the connection after ExportAsFixedFormat, and the
# export itself still succeeds, so a dropped instance must not abort the run.
$word = $null
function New-Word {
  $w = New-Object -ComObject Word.Application
  $w.Visible = $false
  $w.DisplayAlerts = 0
  return $w
}

$converted = 0; $skipped = 0; $failed = 0
try {
  $word = New-Word
  foreach ($d in $docs) {
    $pdfPath = [System.IO.Path]::ChangeExtension($d.FullName, ".pdf")
    if ((Test-Path $pdfPath) -and -not $Force) {
      Write-Output ("SKIP  {0}  (PDF already there)" -f $d.Directory.Name)
      $skipped++
      continue
    }
    try {
      if ($null -eq $word) { $word = New-Word }
      $doc = $word.Documents.Open($d.FullName, $false, $true)   # ReadOnly
      $doc.ExportAsFixedFormat($pdfPath, $wdExportFormatPDF)
      try { $doc.Close(0) } catch { }
    } catch {
      # The export commonly completes even when COM then disconnects — trust the
      # file on disk rather than the exception.
      try { $word.Quit() } catch { }
      $word = $null
    }
    Start-Sleep -Milliseconds 300
    if (Test-Path $pdfPath) {
      Write-Output ("OK    {0}  ->  {1:N0} KB" -f $d.Directory.Name, ((Get-Item $pdfPath).Length / 1KB))
      $converted++
    } else {
      Write-Output ("FAIL  {0}  ({1})" -f $d.Directory.Name, $d.Name)
      $failed++
    }
  }
} finally {
  if ($word) { try { $word.Quit() } catch { } }
}

Write-Output ""
Write-Output ("converted: {0}   skipped: {1}   failed: {2}" -f $converted, $skipped, $failed)
if ($failed -gt 0) { exit 1 }
