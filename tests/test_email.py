import os
import unittest
from unittest.mock import patch
import Email


class TestComposeMessage(unittest.TestCase):
    @patch('Email.socket.gethostname')
    def test_compose_message_with_mocked_hostname(self, mock_gethostname):
        mock_gethostname.return_value = 'myserver'
        expected_body = (
            'Server myserver has possibly been infected or being attacked by Ransomware\n\n'
            'Check Event Logs for Event ID 8215. The user has been denied access to all file shares.\n'
            'Once security threat has been resolved, run the following powershell command on the server '
            'myserver to unblock the user from file shares: get-smbshare | unblock-smbshareaccess -accountname $username -force'
        )
        expected_message = f'Subject: Something?\n\n{expected_body}'
        message = Email.compose_message(Email.socket.gethostname())
        self.assertEqual(message, expected_message)

    def test_send_email_fails_when_smtp_password_missing(self):
        env = os.environ.copy()
        env.pop('FSRM_SMTP_PASSWORD', None)
        with patch.dict(os.environ, env, clear=True):
            with self.assertRaises(RuntimeError) as caught:
                Email.send_email()
        self.assertIn('FSRM_SMTP_PASSWORD', str(caught.exception))

    def test_send_email_fails_when_smtp_password_blank(self):
        with patch.dict(os.environ, {'FSRM_SMTP_PASSWORD': '   '}, clear=True):
            with self.assertRaises(RuntimeError) as caught:
                Email.send_email()
        self.assertIn('FSRM_SMTP_PASSWORD', str(caught.exception))


if __name__ == '__main__':
    unittest.main()
