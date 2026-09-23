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


async def send_password_reset_email(to_email: str, otp_code: str) -> bool:
    """Send 6-digit password reset OTP code via SMTP or log to console in dev mode."""
    subject = f"Your NexAround Password Reset Code: {otp_code}"
    
    html_body = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; }}
        .card {{ max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 12px; padding: 30px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }}
        .logo {{ color: #00897B; font-size: 24px; font-weight: bold; text-align: center; margin-bottom: 20px; }}
        .otp-box {{ background: #FFF3E0; border-radius: 8px; font-size: 32px; font-weight: bold; color: #E65100; text-align: center; letter-spacing: 6px; padding: 16px; margin: 24px 0; }}
        .footer {{ font-size: 12px; color: #78909C; text-align: center; margin-top: 20px; }}
      </style>
    </head>
    <body>
      <div class="card">
        <div class="logo">nexaround</div>
        <h2>Reset Your Password</h2>
        <p>You requested to reset your password. Use the 6-digit verification code below to set a new password:</p>
        <div class="otp-box">{otp_code}</div>
        <p>This code will expire in <strong>10 minutes</strong>. If you did not request a password reset, please secure your account immediately.</p>
        <div class="footer">&copy; NexAround POI & Discovery Platform</div>
      </div>
    </body>
    </html>
    """

    print("=" * 80)
    print(f"📧 [PASSWORD RESET DISPATCH] To: {to_email} | Reset OTP Code: {otp_code}")
    print("=" * 80)

    if not settings.SMTP_HOST or not settings.SMTP_USER:
        print(f"ℹ️ [DEV SIMULATOR] SMTP credentials not set. Password Reset OTP code for {to_email} is: {otp_code}")
        return True

    try:
        await asyncio.to_thread(_send_smtp_sync, to_email, subject, html_body)
        print(f"✅ Password reset OTP email sent successfully via SMTP to {to_email}")
        return True
    except Exception as e:
        print(f"❌ Failed to send Password Reset OTP email via SMTP to {to_email}: {e}")
        print(f"🔑 [DEV FALLBACK] Reset OTP code for {to_email} is: {otp_code}")
        return False



async def send_vendor_invite_email(
    to_email: str, vendor_name: str, link: str, is_reset: bool = False,
) -> bool:
    """Send a partner-portal invite or password-reset link.

    A link rather than a code: the vendor is on a laptop at a desk, not a phone,
    and the invite is the first thing they ever see of the portal.

    The console print is not debug noise left behind - it is how the link is
    obtained before SMTP is verified for this template, and it mirrors what
    `send_otp_email` and `send_password_reset_email` already do.
    """
    what = "Reset your NexAround Partner password" if is_reset else "Your NexAround Partner account"
    intro = (
        "You asked to reset the password for your NexAround Partner account."
        if is_reset else
        f"NexAround has created a partner account for <strong>{vendor_name}</strong>. "
        "Set a password to sign in and manage your listing."
    )
    expiry = "1 hour" if is_reset else "3 days"

    html_body = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; }}
        .card {{ max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 12px; padding: 30px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }}
        .logo {{ color: #00897B; font-size: 24px; font-weight: bold; text-align: center; margin-bottom: 20px; }}
        .cta {{ text-align: center; margin: 28px 0; }}
        .cta a {{ background: #007A7C; color: #ffffff; text-decoration: none; font-weight: bold; border-radius: 8px; padding: 14px 28px; display: inline-block; }}
        .alt {{ font-size: 12px; color: #78909C; word-break: break-all; }}
        .footer {{ font-size: 12px; color: #78909C; text-align: center; margin-top: 20px; }}
      </style>
    </head>
    <body>
      <div class="card">
        <div class="logo">nexaround</div>
        <h2>{what}</h2>
        <p>{intro}</p>
        <div class="cta"><a href="{link}">Set your password</a></div>
        <p>This link expires in <strong>{expiry}</strong> and can be used once.
        If you were not expecting it, you can ignore this email.</p>
        <p class="alt">If the button does not work, paste this into your browser:<br>{link}</p>
        <div class="footer">&copy; NexAround POI &amp; Discovery Platform</div>
      </div>
    </body>
    </html>
    """

    print("=" * 80)
    print(f"📧 [PARTNER {'RESET' if is_reset else 'INVITE'}] To: {to_email} | Link: {link}")
    print("=" * 80)

    if not settings.SMTP_HOST or not settings.SMTP_USER:
        print(f"ℹ️ [DEV SIMULATOR] SMTP not set. Partner link for {to_email} is: {link}")
        return True

    try:
        await asyncio.to_thread(_send_smtp_sync, to_email, what, html_body)
        print(f"✅ Partner link email sent successfully via SMTP to {to_email}")
        return True
    except Exception as e:
        print(f"❌ Failed to send partner link email via SMTP to {to_email}: {e}")
        print(f"🔑 [DEV FALLBACK] Partner link for {to_email} is: {link}")
        return False


async def send_vendor_enquiry_email(
    to_email: str,
    *,
    vendor_name: str,
    package_title: str,
    contact_name: str,
    contact_phone: str,
    contact_email: str = "",
    preferred_date: str = "",
    party_size: str = "",
    message: str = "",
) -> bool:
    """Notify a vendor that a traveller enquired about one of their packages."""
    subject = f"New NexAround enquiry: {package_title}"

    def _row(label: str, value: str) -> str:
        if not value:
            return ""
        return (
            f'<tr><td style="padding:6px 12px 6px 0;color:#78909C;">{label}</td>'
            f'<td style="padding:6px 0;color:#263238;"><strong>{value}</strong></td></tr>'
        )

    html_body = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; }}
        .card {{ max-width: 540px; margin: 0 auto; background: #ffffff; border-radius: 12px; padding: 30px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }}
        .logo {{ color: #00897B; font-size: 24px; font-weight: bold; text-align: center; margin-bottom: 20px; }}
        .package {{ background: #E0F2F1; border-radius: 8px; padding: 14px 16px; margin: 20px 0; color: #004D40; font-size: 18px; font-weight: bold; }}
        .message {{ background: #FAFAFA; border-left: 3px solid #00897B; padding: 12px 16px; margin: 16px 0; color: #37474F; }}
        .footer {{ font-size: 12px; color: #78909C; text-align: center; margin-top: 24px; }}
      </style>
    </head>
    <body>
      <div class="card">
        <div class="logo">nexaround</div>
        <h2>New enquiry for {vendor_name}</h2>
        <p>A traveller has asked about one of your experiences:</p>
        <div class="package">{package_title}</div>
        <table style="width:100%;border-collapse:collapse;font-size:14px;">
          {_row("Name", contact_name)}
          {_row("Phone", contact_phone)}
          {_row("Email", contact_email)}
          {_row("Preferred date", preferred_date)}
          {_row("Party size", party_size)}
        </table>
        {f'<div class="message">{message}</div>' if message else ''}
        <p style="color:#546E7A;font-size:14px;">Please contact them directly to confirm availability and pricing.</p>
        <div class="footer">&copy; NexAround POI &amp; Discovery Platform</div>
      </div>
    </body>
    </html>
    """

    print("=" * 80)
    print(f"📧 [ENQUIRY DISPATCH] To: {to_email} | {vendor_name} | {package_title}")
    print("=" * 80)

    if not settings.SMTP_HOST or not settings.SMTP_USER:
        print(f"ℹ️ [DEV SIMULATOR] SMTP not configured. Enquiry for {vendor_name} not emailed.")
        return True

    try:
        await asyncio.to_thread(_send_smtp_sync, to_email, subject, html_body)
        print(f"✅ Enquiry email sent successfully via SMTP to {to_email}")
        return True
    except Exception as e:
        print(f"❌ Failed to send enquiry email via SMTP to {to_email}: {e}")
        return False
