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
