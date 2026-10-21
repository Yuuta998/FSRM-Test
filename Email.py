import os
import smtplib
import socket

sender_address = ""  # Replace this with sender email address
receiver_address = ""  # Replace this with any valid email address (this is the receiver address)

subject = "Something?"  # You can put anything in for the Subject


def require_smtp_password() -> str:
    """Return the SMTP password from FSRM_SMTP_PASSWORD.

    The password is not stored in this file. Fail clearly when it is unset.
    """
    password = os.environ.get("FSRM_SMTP_PASSWORD")
    if password is None or not password.strip():
        raise RuntimeError(
            "FSRM_SMTP_PASSWORD is not set. Set this environment variable to the "
            "SMTP account password before sending email."
        )
    return password


def compose_message(hostname: str, subject_line: str = subject) -> str:
    """Return the full email message for the given hostname."""
    body = (
        "Server "
        + hostname
        + " has possibly been infected or being attacked by Ransomware"
        "\n\n"
        "Check Event Logs for Event ID 8215. The user has been denied access to all file shares."
        "\n"
        "Once security threat has been resolved, run the following powershell command on the server "
        + hostname
        + " to unblock the user from file shares: get-smbshare | unblock-smbshareaccess -accountname $username -force"
    )
    return f"Subject: {subject_line}\n\n{body}"


def send_email() -> None:
    """Send the composed message via Gmail SMTP."""
    password = require_smtp_password()
    hostname = socket.gethostname()
    smtp_server = smtplib.SMTP_SSL("smtp.gmail.com", 465)
    smtp_server.login(sender_address, password)
    message = compose_message(hostname)
    smtp_server.sendmail(sender_address, receiver_address, message)
    smtp_server.close()


if __name__ == "__main__":
    send_email()
