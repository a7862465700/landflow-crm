# Create Outlook drafts with signed-ready Purchase Agreements attached, batched.
#
# Creates DRAFTS only -- nothing is ever sent. Open each one in Outlook, check
# the attachments, and press Send yourself.
#
#   .\tools\create-send-drafts.ps1 -ParcelList .\pending.txt
#   .\tools\create-send-drafts.ps1 -ParcelList .\pending.txt -BatchSize 10
#   .\tools\create-send-drafts.ps1 -Parcels 452-00145-000,60708
#
# ParcelList is a text file with one parcel number per line. For each parcel it
# finds that parcel's folder under Hot Springs and attaches the Purchase
# Agreement PDF found there. Returned signed copies ("S ..." files) are ignored.
#
# Prints the batch composition at the end so the send dates can be recorded
# against exactly the parcels that went out.

param(
  [string]   $ParcelList = "",
  [string[]] $Parcels    = @(),
  [int]      $BatchSize  = 10,
  [string]   $Root       = "C:\Users\Elk Ceek Group\Dropbox\Arkansas\Hot Springs",
  [string]   $From       = "ra@elkcreekusa.com",
  [string]   $To         = "terraequityml@gmail.com",
  [string]   $SubjectFmt = "Purchase Agreements for Signature - {0} Parcels ({1} of {2})"
)

$ErrorActionPreference = 'Continue'

if ($ParcelList) {
  if (-not (Test-Path $ParcelList)) { Write-Error "Parcel list not found: $ParcelList"; exit 1 }
  $Parcels = Get-Content $ParcelList | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
if (-not $Parcels -or $Parcels.Count -eq 0) { Write-Error "No parcels given. Use -ParcelList or -Parcels."; exit 1 }
if (-not (Test-Path $Root)) { Write-Error "Root folder not found: $Root"; exit 1 }

# Dropbox uses the short parcel form (452-00145) while the CRM carries the full
# one (452-00145-000). Normalise a trailing -000 so both resolve to one folder.
function Normalize([string]$s) { return ($s -replace '-0+$', '').Trim() }

$dirs = Get-ChildItem -Path $Root -Directory
function Find-ParcelDir([string]$parcel) {
  $t = Normalize $parcel
  foreach ($d in $dirs) { if ((Normalize $d.Name) -eq $t -or $d.Name.Trim() -eq $parcel.Trim()) { return $d } }
  return $null
}

# Resolve each parcel to its agreement PDF before opening Outlook, so a missing
# file is reported up front rather than leaving half-built drafts behind.
$resolved = @(); $problems = @()
foreach ($p in $Parcels) {
  $dir = Find-ParcelDir $p
  if (-not $dir) { $problems += "$p : no folder under Hot Springs"; continue }
  $pdf = Get-ChildItem -Path $dir.FullName -Filter "*.pdf" |
         Where-Object { $_.Name -like "Purchase_Agreement*" -and $_.Name -notmatch '^S[\s_-]' } |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $pdf) { $problems += "$p : no Purchase Agreement PDF in $($dir.Name)"; continue }
  $resolved += [pscustomobject]@{ Parcel = $p; Folder = $dir.Name; Path = $pdf.FullName; Size = $pdf.Length }
}

if ($problems.Count -gt 0) {
  Write-Output "Could not resolve $($problems.Count) parcel(s):"
  $problems | ForEach-Object { Write-Output "  $_" }
  Write-Output ""
}
if ($resolved.Count -eq 0) { Write-Error "Nothing to attach."; exit 1 }

$batches = @()
for ($i = 0; $i -lt $resolved.Count; $i += $BatchSize) {
  $batches += ,@($resolved[$i..([Math]::Min($i + $BatchSize - 1, $resolved.Count - 1))])
}
Write-Output "$($resolved.Count) agreement(s) -> $($batches.Count) draft(s) of up to $BatchSize"
Write-Output ""

$outlook = New-Object -ComObject Outlook.Application
# Index access rather than foreach: PowerShell's enumerator over this COM
# collection does not reliably yield the account objects, which silently left
# SendUsingAccount unset.
$sendAccount = $null
$accounts = $outlook.Session.Accounts
for ($i = 1; $i -le $accounts.Count; $i++) {
  $a = $accounts.Item($i)
  if ($a.SmtpAddress -and $a.SmtpAddress.Trim().ToLower() -eq $From.Trim().ToLower()) { $sendAccount = $a; break }
}
if ($sendAccount) {
  Write-Output "Sending account: $($sendAccount.SmtpAddress)"
} else {
  Write-Output "WARNING: no Outlook account matching $From - drafts will use the default account."
  Write-Output "         Accounts available:"
  for ($i = 1; $i -le $accounts.Count; $i++) { Write-Output "           $($accounts.Item($i).SmtpAddress)" }
}

$batchNo = 0
foreach ($batch in $batches) {
  $batchNo++
  $mail = $outlook.CreateItem(0)   # olMailItem
  if ($sendAccount) { $mail.SendUsingAccount = $sendAccount }
  $mail.To = $To
  $mail.Subject = ($SubjectFmt -f $batch.Count, $batchNo, $batches.Count)

  $list = ($batch | ForEach-Object { $_.Parcel }) -join "`r`n"
  $mail.Body = @"
Michael,

Attached are $($batch.Count) Purchase Agreements for signature, covering the parcels below.

$list

Please sign and return copies by email, with the originals to follow.

Thanks,
Richard
"@

  foreach ($item in $batch) { $mail.Attachments.Add($item.Path) | Out-Null }
  $mail.Save()   # DRAFT ONLY - never .Send()

  $kb = [Math]::Round((($batch | Measure-Object -Property Size -Sum).Sum) / 1KB)
  Write-Output ("Draft {0} of {1}: {2} attachments, {3:N0} KB" -f $batchNo, $batches.Count, $batch.Count, $kb)
  $batch | ForEach-Object { Write-Output ("    {0}  <-  {1}" -f $_.Parcel, (Split-Path $_.Path -Leaf)) }
  Write-Output ""
}

Write-Output "Saved to Drafts. Nothing has been sent."
Write-Output ""
Write-Output "BATCH_MAP (parcel,batch)"
$batchNo = 0
foreach ($batch in $batches) { $batchNo++; $batch | ForEach-Object { Write-Output ("{0},{1}" -f $_.Parcel, $batchNo) } }
