param([Parameter(Mandatory)][string]$ShellExe)
$ErrorActionPreference = 'Continue'
$repo = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo 'FSRM Script.ps1'
$admin = 'S-1-5-32-544'; $system = 'S-1-5-18'
$results = [ordered]@{}
& $ShellExe -NoProfile -Command '$PSVersionTable.PSVersion.ToString(); $PSVersionTable.PSEdition' | Write-Host

function Invoke-Fsrm {
  $out = & $ShellExe -NoProfile -ExecutionPolicy Bypass -File $script -SMTPServer smtp.example.invalid -EmailTo to@example.invalid -EmailFrom from@example.invalid 2>&1
  $code = $LASTEXITCODE
  $out | ForEach-Object { Write-Host "  | $_" }
  Write-Host "  exit code: $code"
  return $code
}
function Get-State {
  $grp = $null
  try { $grp = Get-FsrmFileGroup -Name 'Ransomware Files' -ErrorAction Stop } catch {}
  [pscustomobject]@{ ScriptsExists = Test-Path -LiteralPath 'C:\scripts'; FileGroup = [bool]$grp }
}
function New-Source([string]$Text, [switch]$Untrusted) {
  New-Item -ItemType Directory -Force C:\FSRM | Out-Null
  Remove-Item C:\FSRM\Email.py -Force -ErrorAction SilentlyContinue
  Set-Content -LiteralPath C:\FSRM\Email.py -Value $Text -Encoding ascii
  icacls C:\FSRM\Email.py /setowner "*$admin" | Out-Null
  if ($Untrusted) {
    icacls C:\FSRM\Email.py /inheritance:r /grant:r "*$admin`:F" "*$system`:F" "*S-1-5-32-545:M" | Out-Null
  } else {
    icacls C:\FSRM\Email.py /inheritance:r /grant:r "*$admin`:F" "*$system`:F" | Out-Null
  }
  icacls C:\FSRM\Email.py | Write-Host
}
function Test-AdminOnlyAcl([string]$Path) {
  $acl = Get-Acl -LiteralPath $Path
  $sids = @($acl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value }) | Sort-Object -Unique
  $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
  Write-Host "  ACL $Path owner=$owner protected=$($acl.AreAccessRulesProtected) sids=$($sids -join ',')"
  return ($acl.AreAccessRulesProtected -and ($owner -in @($admin,$system)) -and (@($sids | Where-Object { $_ -notin @($admin,$system) }).Count -eq 0) -and $sids.Count -gt 0)
}
function Hash([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

$fsrmAvailable = [bool](Get-Command Get-FsrmFileGroup -ErrorAction SilentlyContinue)
Write-Host "FSRM cmdlets available: $fsrmAvailable"

Write-Host "=== Check 2a: missing C:\FSRM\Email.py ==="
Remove-Item C:\FSRM\Email.py -Force -ErrorAction SilentlyContinue
$before = Get-State
$code = Invoke-Fsrm
$after = Get-State
Write-Host "  before=$($before|ConvertTo-Json -Compress) after=$($after|ConvertTo-Json -Compress)"
$results['2a missing Email.py stops, nothing changed'] = ($code -ne 0 -and -not $after.ScriptsExists -and ($after.FileGroup -eq $before.FileGroup))

Write-Host "=== Check 2b: untrusted (Users:Modify) C:\FSRM\Email.py ==="
New-Source -Text "# untrusted" -Untrusted
$before = Get-State
$code = Invoke-Fsrm
$after = Get-State
Write-Host "  before=$($before|ConvertTo-Json -Compress) after=$($after|ConvertTo-Json -Compress)"
$results['2b untrusted Email.py stops, nothing changed'] = ($code -ne 0 -and -not $after.ScriptsExists -and ($after.FileGroup -eq $before.FileGroup) -and (Test-Path C:\FSRM\Email.py))

Write-Host "=== Check 1: trusted admin-only C:\FSRM\Email.py installs ==="
$src1 = Get-Content -Raw (Join-Path $repo 'Email.py')
New-Source -Text $src1
$h1 = Hash C:\FSRM\Email.py
$code = Invoke-Fsrm
$ok1 = ($code -eq 0 -and (Test-Path C:\scripts\Email.py) -and ((Hash C:\scripts\Email.py) -eq $h1) -and -not (Test-Path C:\FSRM\Email.py))
Write-Host "  installed=$(Test-Path C:\scripts\Email.py) sourceRemoved=$(-not (Test-Path C:\FSRM\Email.py))"
$results['1 trusted Email.py installs'] = $ok1

Write-Host "=== Check 3: C:\scripts Administrators/SYSTEM-only ACLs ==="
if (Test-Path C:\scripts) {
  $c3 = Test-AdminOnlyAcl C:\scripts
  foreach ($f in Get-ChildItem -LiteralPath C:\scripts -Force) { $c3 = (Test-AdminOnlyAcl $f.FullName) -and $c3 }
  $results['3 C:\scripts admin/SYSTEM-only ACLs'] = $c3
} else { $results['3 C:\scripts admin/SYSTEM-only ACLs'] = $false; Write-Host "  C:\scripts missing" }

Write-Host "=== Check 4: re-run replaces both files ==="
if ($ok1) {
  $denyBefore = (Get-Item C:\scripts\ScriptToDenyPermissions.PS1).CreationTimeUtc.Ticks
  Start-Sleep -Seconds 2
  New-Source -Text ($src1 + "`r`n# rerun marker")
  $h2 = Hash C:\FSRM\Email.py
  $code = Invoke-Fsrm
  $denyAfter = (Get-Item C:\scripts\ScriptToDenyPermissions.PS1 -ErrorAction SilentlyContinue).CreationTimeUtc.Ticks
  $emailNew = (Test-Path C:\scripts\Email.py) -and ((Hash C:\scripts\Email.py) -eq $h2)
  Write-Host "  emailReplaced=$emailNew denyReplaced=$($denyAfter -ne $denyBefore)"
  $results['4 re-run replaces both files'] = ($code -eq 0 -and $emailNew -and $denyAfter -ne $denyBefore)
  if (Test-Path C:\scripts) { foreach ($f in Get-ChildItem -LiteralPath C:\scripts -Force) { [void](Test-AdminOnlyAcl $f.FullName) } }
} else { $results['4 re-run replaces both files'] = $null; Write-Host "  skipped: check 1 failed" }

Write-Host "=== Bonus: python tests/test_email.py ==="
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + $env:Path
Push-Location $repo; $env:PYTHONPATH = $repo
python -m unittest discover -s tests -v 2>&1 | Write-Host
$results['bonus tests/test_email.py (unittest)'] = ($LASTEXITCODE -eq 0)
Pop-Location

Write-Host "=== SUMMARY ($ShellExe) ==="
$fail = $false
foreach ($k in $results.Keys) { $v = $results[$k]; $s = if ($v -eq $true) {'PASS'} elseif ($null -eq $v) {'SKIP'} else {'FAIL'; $fail=$true}; Write-Host "RESULT | $s | $k" }
if ($fail) { exit 1 }
