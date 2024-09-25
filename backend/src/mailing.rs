use std::time::{Duration, SystemTime};

use lettre::{message::header::ContentType, transport::smtp::authentication::{Credentials, Mechanism}, AsyncSmtpTransport, AsyncTransport as _, Message, Tokio1Executor};
use semweb_api::biscuits;
use serde::{Deserialize, Serialize};
use sqlxmq::{job, CurrentJob};

use crate::db::Revocation;

pub type Transport = AsyncSmtpTransport<Tokio1Executor>;

#[derive(Clone)]
pub struct AdminEmail(pub String);

#[derive(Debug, Deserialize, Serialize)]
pub(crate) struct ResetDetails {
    pub domain: String,
    pub email: String,
}

const ONE_HOUR: u64 = 60 * 60;

#[job(channel_name = "emails")]
pub(crate) async fn request_reset(
    mut current_job: CurrentJob,
    transport: Transport,
    AdminEmail(admin): AdminEmail,
    auth: biscuits::Authentication,
) -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    let details: ResetDetails = current_job.json()?.ok_or(crate::Error::Job("no job details".to_string()))?;
    let db = current_job.pool();

    let expires = SystemTime::now() + Duration::from_secs(ONE_HOUR);
    let bundle = auth.reset_password(&details.email, expires)?;
    let _ = Revocation::add_batch(db, bundle.revocation_ids, details.email.clone(), expires).await?;

    let msg = Message::builder()
        .from(format!("Wag the Pig <noreply@{}>", details.domain).parse()?)
        .reply_to(admin.parse()?)
        .to(details.email.parse()?)
        .subject("Password Reset Request")
        .header(ContentType::TEXT_PLAIN)
        .body(String::from(format!(
            r#"
                Hey!

                A password request was made for your account. If you didn't request it, delete this message.

                Otherwise, follow this URL to reset your password:
                https://{domain}/handlePasswordReset#{token}

                Regards,
                Wag, the pig
                "#,
            domain = details.domain,
            token = bundle.token
        )))?;

    transport.send(msg).await?;

    current_job.complete().await?;
    Ok(())
}

#[derive(Debug, Deserialize, Serialize)]
pub(crate) struct RegistrationDetails {
    pub domain: String,
    pub email: String,
}

#[job(channel_name = "emails")]
pub(crate) async fn request_registration(
    mut current_job: CurrentJob,
    transport: AsyncSmtpTransport<Tokio1Executor>,
    AdminEmail(admin): AdminEmail,
    auth: biscuits::Authentication,
) -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    let details: RegistrationDetails = current_job.json()?.ok_or(crate::Error::Job("no job details".to_string()))?;
    let db = current_job.pool();

    let expires = SystemTime::now() + Duration::from_secs(ONE_HOUR);
    let bundle = auth.reset_password(&details.email, expires)?;
    let _ = Revocation::add_batch(db, bundle.revocation_ids, details.email.clone(), expires).await?;

    let msg = Message::builder()
        .from(format!("Wag the Pig <noreply@{}>", details.domain).parse()?)
        .reply_to(admin.parse()?)
        .to(details.email.parse()?)
        .subject("Password Reset Request")
        .header(ContentType::TEXT_PLAIN)
        .body(String::from(format!(
            r#"
                Hey!

                We got a request to register an account for this email address.
                If you didn't ask for this, please delete this email, with our apologies.

                Otherwise, follow this URL to finish getting set up!
                https://{domain}/handleRegistration#{token}

                Regards,
                Wag, the pig
                "#,
            token = bundle.token,
            domain = details.domain
        )))?;

    transport.send(msg).await?;

    current_job.complete().await?;
    Ok(())
}

pub(crate) fn build_transport(address: &str, port: &str, user: &str, pass: &str) -> Result<Transport, Error> {
    Ok(Transport::starttls_relay(address)?
        .port(port.parse()?)
        .credentials(Credentials::new(user.to_string(), pass.to_string()))
        .authentication(vec![Mechanism::Plain])
        .build())
}


#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("lettre error: ${0:?}")]
    SMTP(#[from] lettre::transport::smtp::Error),
    #[error("configuration error: non-numeric port: ${0:?}")]
    Config(#[from] std::num::ParseIntError)
}
