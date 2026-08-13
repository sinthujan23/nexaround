import asyncio
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from app.core.config import settings


def _send_smtp_sync(to_email: str, subject: str, html_body: str) -> bool:
    """Synchronous SMTP worker executed in threadpool to prevent blocking async loop."""
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = settings.EMAILS_FROM_EMAIL
    msg["To"] = to_email
    msg.attach(MIMEText(html_body, "html"))

    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=5) as server:
        server.starttls()
        if settings.SMTP_USER and settings.SMTP_PASSWORD:
            server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
        server.sendmail(settings.EMAILS_FROM_EMAIL, [to_email], msg.as_string())
    return True


async def send_otp_email(to_email: str, otp_code: str) -> bool:
    """Send 6-digit OTP verification code via SMTP or log to console in dev mode."""
    subject = f"Your NexAround Verification Code: {otp_code}"
    
    html_body = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; }}
        .card {{ max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 12px; padding: 30px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }}
        .logo {{ color: #00897B; font-size: 24px; font-weight: bold; text-align: center; margin-bottom: 20px; }}
        .otp-box {{ background: #E0F2F1; border-radius: 8px; font-size: 32px; font-weight: bold; color: #004D40; text-align: center; letter-spacing: 6px; padding: 16px; margin: 24px 0; }}
        .footer {{ font-size: 12px; color: #78909C; text-align: center; margin-top: 20px; }}
      </style>
    </head>
    <body>
      <div class="card">
        <div class="logo">nexaround</div>
        <h2>Verify Your Email Address</h2>
        <p>Thank you for signing up for NexAround! Please use the following 6-digit verification code to complete your registration:</p>
        <div class="otp-box">{otp_code}</div>
        <p>This code will expire in <strong>10 minutes</strong>. If you did not request this code, please ignore this email.</p>
        <div class="footer">&copy; NexAround POI & Discovery Platform</div>
      </div>
    </body>
    </html>
    """

    print("=" * 80)
    print(f"📧 [OTP DISPATCH] To: {to_email} | OTP Code: {otp_code}")
    print("=" * 80)

    if not settings.SMTP_HOST or not settings.SMTP_USER:
        print(f"ℹ️ [DEV SIMULATOR] SMTP credentials not set. Mobile OTP code for {to_email} is: {otp_code}")
        return True

    try:
        await asyncio.to_thread(_send_smtp_sync, to_email, subject, html_body)
        print(f"✅ OTP email sent successfully via SMTP to {to_email}")
        return True
    except Exception as e:
        print(f"❌ Failed to send OTP email via SMTP to {to_email}: {e}")
        print(f"🔑 [DEV FALLBACK] OTP code for {to_email} is: {otp_code}")
        return False

