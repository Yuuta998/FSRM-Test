codex/add-email-composition-test-with-unittest
import smtplib
import socket

sender_address = ""  # Replace this with sender email address
receiver_address = ""  # Replace this with any valid email address (this is the receiver address)
account_password = ""  # Replace this with your account password

subject = "Something?"  # You can put anything in for the Subject


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
    hostname = socket.gethostname()
    smtp_server = smtplib.SMTP_SSL("smtp.gmail.com", 465)
    smtp_server.login(sender_address, account_password)
    message = compose_message(hostname)
    smtp_server.sendmail(sender_address, receiver_address, message)
    smtp_server.close()


if __name__ == "__main__":
    send_email()
import smtplib
import socket

sender_address = "" # Replace this with sender email address
 
receiver_address = "" # Replace this with any valid email address (this is the receiver address)
 
account_password = "" # Replace this with your account password

# You can put anything in for the Subject

subject = "Something?"
hostname = socket.gethostname()

body = "Server " + hostname + " has possibly been infected or being attacked by Ransomware" "\n\n""Check Event Logs for Event ID 8215. The user has been denied access to all file shares." "\n" "Once security threat has been resolved, run the following powershell command on the server " + hostname + " to unblock the user from file shares: get-smbshare | unblock-smbshareaccess -accountname $username -force"
 
# Endpoint for the SMTP Gmail server 
# IF needing to change this get the SMTP of the server attempting to use and the port.

smtp_server = smtplib.SMTP_SSL("smtp.gmail.com", 465)
 
# Login with your Gmail account using SMTP
smtp_server.login(sender_address, account_password)
 
# Let's combine the subject and the body onto a single message
message = f"Subject: {subject}\n\n{body}"
 
# We'll be sending this message in the above format (Subject:...\n\nBody)
smtp_server.sendmail(sender_address, receiver_address, message)
 
# Close our endpoint
smtp_server.close()
main
