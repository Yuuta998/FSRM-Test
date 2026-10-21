# FSRM Test

File Server Resource Manager ransomware file-screen setup and alert email.

## SMTP password

`Email.py` does not store an SMTP password. Set `FSRM_SMTP_PASSWORD` to the SMTP account password before sending mail. If that variable is missing or blank, `Email.py` stops and reports that `FSRM_SMTP_PASSWORD` is not set.

```powershell
$env:FSRM_SMTP_PASSWORD = "<smtp-account-password>"
python C:\scripts\Email.py
```

Do not commit the password or write it into `Email.py`.

## Required mail settings

`FSRM Script.ps1` requires the SMTP server and the from/to addresses. Example values are not embedded in the script.

```powershell
& '.\FSRM Script.ps1' -SMTPServer smtp.example.com -EmailTo alerts@example.com -EmailFrom fsrm@example.com
```

## Python install

The script installs Python 3.12 instead of end-of-life Python 3.7.6. It uses `winget` (`Python.Python.3.12`) when `winget` is available. Otherwise it downloads the official Python 3.12.10 Windows x64 installer from python.org — the latest 3.12.x release published with a Windows installer — into a new private directory, checks its SHA256 with `Get-FileHash`, and removes that directory after the installer finishes. The install stops if the hash does not match `67B5635E80EA51072B87941312D00EC8927C4DB9BA18938F7AD2D27B328B95FB`.

Open a new shell, or refresh PATH in the current one, before using `python`. The shell that ran the script does not see the updated PATH.

## Running the script again

Before each run, restore a trusted `Email.py` to `C:\FSRM\Email.py`. The script checks that file before it changes FSRM or `C:\scripts`. The file must be a regular file, not a junction or symlink. Its owner must be Administrators or SYSTEM, its access list must grant access only to Administrators and SYSTEM, and it must have a single link. An empty file is rejected.

From an elevated command prompt, restrict the file to Administrators and SYSTEM:

```powershell
icacls C:\FSRM\Email.py /inheritance:r
icacls C:\FSRM\Email.py /grant *S-1-5-32-544:F *S-1-5-18:F
icacls C:\FSRM\Email.py /setowner *S-1-5-32-544
```

A successful run removes `C:\FSRM\Email.py`. If that file is missing or is not trusted, the script stops without changing FSRM or `C:\scripts`. Restore a trusted `Email.py` to `C:\FSRM\` and run the script again.

## Leftover template XML

Setup writes a temporary `C:\scripts\FSRMTemplate-*.xml` while it imports the file screen template, then deletes that file. If setup is interrupted before the delete, the XML stays in `C:\scripts`. The next run refuses the directory, because the only files allowed there are `Email.py` and `ScriptToDenyPermissions.PS1`.

Confirm that no setup is running. From an elevated prompt, delete the leftover file, then run the script again:

```powershell
Get-ChildItem -LiteralPath C:\scripts -Filter 'FSRMTemplate-*.xml' -Force | Remove-Item -Force
```
