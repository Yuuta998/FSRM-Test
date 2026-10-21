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

Write-Host "=== Check 5: tampered RansomwareCheck template is replaced ==="
  $planted = '<?xml version="1.0" ?><Root ><Header DatabaseVersion = ''2.0'' ></Header><QuotaTemplates ></QuotaTemplates><DatascreenTemplates ><DatascreenTemplate Name = ''RansomwareCheck'' Id = ''{122F5AB4-9DF0-4F09-B89E-0F7BDC9D46CC}'' Flags = ''1'' Description = ''planted'' ><BlockedGroups ><FileGroup FileGroupId = ''{82D08F60-7319-4BE2-8621-066DB91A958E}'' Name = ''Ransomware%sFiles'' ></FileGroup></BlockedGroups><FileGroupActions ><Action Type="3" Id="{D0B80CC5-E6DD-481C-9534-19944A851A72}" ExecutablePath="C:\Windows\System32\cmd.exe" Arguments="/c echo planted" WorkingDirectory="C:\Windows\" Account="3" MonitorCommand="0" KillTimeOut="0" LogResult="1" /></FileGroupActions></DatascreenTemplate></DatascreenTemplates><FileGroups ></FileGroups></Root>'
if ($ok1 -and $fsrmAvailable) {
  # Tamper with the existing template through filescrn, the same way the script imports it.
  $tamperPath = Join-Path $env:RUNNER_TEMP 'tampered-template.xml'
  Set-Content -LiteralPath $tamperPath -Value $planted -Encoding Unicode
  & filescrn.exe template import "/file:$tamperPath" /template:RansomwareCheck /overwrite | Write-Host
  Remove-Item -LiteralPath $tamperPath -Force -ErrorAction SilentlyContinue
  $pre = @((Get-FsrmFileScreenTemplate -Name 'RansomwareCheck').Notification | Where-Object { [string]$_.Type -eq 'Command' })
  Write-Host "  tampered command=$($pre[0].Command)"
  New-Source -Text $src1
  $code = Invoke-Fsrm
  $t = Get-FsrmFileScreenTemplate -Name 'RansomwareCheck'
  $cmds = @($t.Notification | Where-Object { [string]$_.Type -eq 'Command' })
  $cmds | ForEach-Object { Write-Host "  command=$($_.Command) params=$($_.CommandParameters) level=$($_.SecurityLevel)" }
  $results['5 tampered template replaced'] = ($pre.Count -eq 1 -and $pre[0].Command -like '*cmd.exe' -and $code -eq 0 -and $cmds.Count -eq 1 -and $cmds[0].Command -like '*WindowsPowerShell\v1.0\powershell.exe' -and $cmds[0].CommandParameters -like '*ScriptToDenyPermissions.PS1*')
} else { $results['5 tampered template replaced'] = $null; Write-Host "  skipped" }

Write-Host "=== Check 6: passive / wrong-template file screen is fixed ==="
$screenDisk = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.DeviceID -ne 'C:' }) | Select-Object -First 1
if ($ok1 -and $fsrmAvailable -and $screenDisk) {
  $sp = "$($screenDisk.DeviceID)\"
  if (-not (Get-FsrmFileScreenTemplate -Name 'CiOtherTemplate' -ErrorAction SilentlyContinue)) {
    New-FsrmFileScreenTemplate -Name 'CiOtherTemplate' -IncludeGroup @('Ransomware Files') | Out-Null
  }
  Reset-FsrmFileScreen -Path $sp -Template 'CiOtherTemplate' -Confirm:$false
  Set-FsrmFileScreen -Path $sp -Active:$false
  $pre = Get-FsrmFileScreen -Path $sp; Write-Host "  before template=$($pre.Template) active=$($pre.Active)"
  New-Source -Text $src1
  $code = Invoke-Fsrm
  $fs = Get-FsrmFileScreen -Path $sp; Write-Host "  after template=$($fs.Template) active=$($fs.Active) groups=$(@($fs.IncludeGroup) -join ',')"
  $results['6 passive/wrong screen fixed'] = ($code -eq 0 -and $fs.Template -eq 'RansomwareCheck' -and $fs.Active -eq $true -and (@($fs.IncludeGroup) -join ',') -eq 'Ransomware Files')
  if ($results['6 passive/wrong screen fixed']) {
    $plantReady = $false
    try {
      $actions = @((Get-FsrmFileScreen -Path $sp).Notification | ForEach-Object { $_.Clone() })
      if (@($actions | Where-Object { [string]$_.Type -eq 'Command' }).Count -lt 1) {
        $actions = @((Get-FsrmFileScreenTemplate -Name 'RansomwareCheck').Notification | ForEach-Object { $_.Clone() })
      }
      $sawPlantedCommand = $false
      foreach ($action in $actions) {
        if ([string]$action.Type -eq 'Command') {
          $action.Command = "$env:SystemRoot\System32\cmd.exe"
          $action.CommandParameters = '/c echo planted'
          $action.WorkingDirectory = "$env:SystemRoot\System32"
          $sawPlantedCommand = $true
        }
      }
      Set-FsrmFileScreen -Path $sp -Active -IncludeGroup 'Ransomware Files' -Notification $actions -ErrorAction Stop
      $prePlant = Get-FsrmFileScreen -Path $sp
      $preCmds = @($prePlant.Notification | Where-Object { [string]$_.Type -eq 'Command' })
      $preCommand = if ($preCmds.Count -ge 1) { [string]$preCmds[0].Command } else { '' }
      Write-Host "  planted template=$($prePlant.Template) active=$($prePlant.Active) groups=$(@($prePlant.IncludeGroup) -join ',') command=$preCommand"
      $plantReady = $sawPlantedCommand -and ($prePlant.Template -eq 'RansomwareCheck') -and ($prePlant.Active -eq $true) -and ((@($prePlant.IncludeGroup) -join ',') -eq 'Ransomware Files') -and ($preCmds.Count -eq 1) -and ($preCommand -like '*\cmd.exe')
    } catch {
      Write-Host "  could not plant screen command: $($_.Exception.Message)"
    }
    New-Source -Text $src1
    $codePlant = Invoke-Fsrm
    $fsPlant = Get-FsrmFileScreen -Path $sp
    $postCmds = @($fsPlant.Notification | Where-Object { [string]$_.Type -eq 'Command' })
    $postCmd = if ($postCmds.Count -ge 1) { $postCmds[0] } else { $null }
    $postCommand = [string]$postCmd.Command
    $postArgs = ([string]$postCmd.CommandParameters).Trim().Trim('"')
    $postWd = ([string]$postCmd.WorkingDirectory).TrimEnd('\')
    $postLevel = [string]$postCmd.SecurityLevel
    Write-Host "  cleared code=$codePlant command=$postCommand params=$postArgs wd=$postWd level=$postLevel matches=$($fsPlant.MatchesTemplate)"
    $cleared = $plantReady -and ($codePlant -eq 0) -and ($postCmds.Count -eq 1) -and ($postCommand -eq 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe') -and ($postArgs -eq 'C:\Scripts\ScriptToDenyPermissions.PS1') -and ($postWd -eq 'C:\Windows\System32\WindowsPowerShell\v1.0') -and ($postLevel -eq 'LocalSystem') -and ($fsPlant.Template -eq 'RansomwareCheck') -and ($fsPlant.Active -eq $true) -and ((@($fsPlant.IncludeGroup) -join ',') -eq 'Ransomware Files')
    if ($fsPlant.PSObject.Properties.Name -contains 'MatchesTemplate') { $cleared = $cleared -and ($fsPlant.MatchesTemplate -eq $true) }
    $results['6 planted screen command cleared'] = [bool]$cleared
  } else {
    $results['6 planted screen command cleared'] = $null
    Write-Host "  planted command check skipped"
  }
} else {
  $results['6 passive/wrong screen fixed'] = $null
  $results['6 planted screen command cleared'] = $null
  Write-Host "  skipped: no non-C fixed disk or earlier failure"
}

Write-Host "=== Check 7: pre-existing ExcludePattern is cleared ==="
if ($ok1 -and $fsrmAvailable) {
  Set-FsrmFileGroup -Name 'Ransomware Files' -ExcludePattern @('*.locky')
  New-Source -Text $src1
  $code = Invoke-Fsrm
  $g = Get-FsrmFileGroup -Name 'Ransomware Files'
  Write-Host "  ExcludePattern count=$(@($g.ExcludePattern).Count)"
  $results['7 ExcludePattern cleared'] = ($code -eq 0 -and @($g.ExcludePattern | Where-Object { $_ }).Count -eq 0)
} else { $results['7 ExcludePattern cleared'] = $null; Write-Host "  skipped" }

Write-Host "=== Check 8: pre-created C:\Users\Public\FSRMTemplate.xml is not used ==="
if ($ok1 -and $fsrmAvailable) {
  $pub = 'C:\Users\Public\FSRMTemplate.xml'
  Set-Content -LiteralPath $pub -Value $planted -Encoding Unicode
  $hp = Hash $pub
  New-Source -Text $src1
  $code = Invoke-Fsrm
  $t = Get-FsrmFileScreenTemplate -Name 'RansomwareCheck'
  $cmds = @($t.Notification | Where-Object { [string]$_.Type -eq 'Command' })
  $untouched = (Test-Path -LiteralPath $pub) -and ((Hash $pub) -eq $hp)
  $leftover = @(Get-ChildItem -LiteralPath C:\scripts -Filter 'FSRMTemplate*.xml' -Force -ErrorAction SilentlyContinue).Count
  Write-Host "  publicUntouched=$untouched leftoverTemplateXml=$leftover command=$($cmds[0].Command)"
  $results['8 planted Public XML ignored'] = ($code -eq 0 -and $untouched -and $leftover -eq 0 -and $cmds.Count -eq 1 -and $cmds[0].Command -like '*powershell.exe')
  Remove-Item -LiteralPath $pub -Force -ErrorAction SilentlyContinue
} else { $results['8 planted Public XML ignored'] = $null; Write-Host "  skipped" }

Write-Host "=== Check 9: failed installer exit code throws ==="
$ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
foreach ($n in @('Assert-NativeCommandSucceeded','Invoke-PythonInstaller')) {
  $fn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $n }, $true)
  . ([scriptblock]::Create($fn.Extent.Text))
}
$threwOnFail = $false
try { Invoke-PythonInstaller -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/c','exit 1603') -CommandName 'fake installer' } catch { $threwOnFail = $true; Write-Host "  threw: $($_.Exception.Message)" }
$okOnZero = $true
try { Invoke-PythonInstaller -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/c','exit 0') -CommandName 'fake installer' } catch { $okOnZero = $false; Write-Host "  unexpected throw: $($_.Exception.Message)" }
$okOnReboot = $false
$warnedOnReboot = $false
try {
  $rebootOutput = @(Invoke-PythonInstaller -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/c','exit 3010') -CommandName 'fake installer' 3>&1)
  $okOnReboot = $true
  $warnedOnReboot = [bool]((@($rebootOutput) | ForEach-Object { "$_" }) -join "`n" -match 'reboot required')
  Write-Host "  3010 output: $(@($rebootOutput) -join ' | ')"
} catch {
  Write-Host "  unexpected throw on 3010: $($_.Exception.Message)"
}
$results['9 failed installer exit code throws'] = ($threwOnFail -and $okOnZero -and $okOnReboot -and $warnedOnReboot)

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
