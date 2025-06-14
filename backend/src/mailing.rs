use std::time::{Duration, SystemTime};

use indoc::formatdoc;
use lettre::{
    message::header::ContentType,
    transport::smtp::{authentication::{Credentials, Mechanism}, client::{Certificate, Tls, TlsParameters}},
    AsyncSmtpTransport,
    AsyncTransport as _, Message,
    Tokio1Executor
};
use semweb_api::biscuits;
use serde::{Deserialize, Serialize};
use sqlx::{Pool, Postgres};
use sqlxmq::{job, CurrentJob, JobRegistry, JobRunnerHandle};
use tracing::debug;

use crate::db::Revocation;

pub type Transport = AsyncSmtpTransport<Tokio1Executor>;

#[derive(Clone)]
pub struct AdminEmail(pub String);

#[derive(Clone)]
pub struct CanonDomain(pub String);


#[derive(Debug, Deserialize, Serialize)]
pub(crate) struct ResetDetails {
    pub email: String,
}

const ONE_HOUR: Duration = Duration::from_secs(60 * 60);
const ONE_DAY: Duration = Duration::from_secs(60 * 60 * 24);

pub(crate) async fn queue_listener(
    pool: Pool<Postgres>,
    admin: String,
    canon_domain: String,
    transport: Transport,
    auth: biscuits::Authentication
) -> Result<JobRunnerHandle, sqlx::Error> {
    let mut registry = JobRegistry::new(&[cleanup_revocations, request_reset, request_registration]);
    // Here is where you can configure the registry
    // registry.set_error_handler(...)

    registry.set_context(AdminEmail(admin));
    registry.set_context(CanonDomain(canon_domain));
    registry.set_context(transport);
    registry.set_context(auth);

    let runner = registry
        .runner(&pool)
        .set_concurrency(1, 20)
        .run()
    .await?;

    // The job runner will continue listening and running
    // jobs until `runner` is dropped.
    Ok(runner)
}

#[job(channel_name = "cleanup")]
pub(crate) async fn cleanup_revocations( current_job: CurrentJob ) -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    let db = current_job.pool();
    let too_old = SystemTime::now() - ONE_DAY;
    Revocation::cleanup(db, too_old).await?;
    Ok(())
}

#[job(channel_name = "emails")]
pub(crate) async fn request_reset(
    mut current_job: CurrentJob,
    transport: Transport,
    CanonDomain(domain): CanonDomain,
    AdminEmail(admin): AdminEmail,
    auth: biscuits::Authentication,
) -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    let details: ResetDetails = current_job.json()?.ok_or(crate::Error::Job("no job details".to_string()))?;
    let db = current_job.pool();

    let expires = SystemTime::now() + ONE_HOUR;
    let bundle = auth.reset_password(&details.email, expires)?;
    let _ = Revocation::add_batch(db, bundle.revocation_ids, details.email.clone(), expires).await?;

    let noreply_domain = domain.split(":").next().unwrap_or("example.com");

    let msg = Message::builder()
        .from(format!("Wag the Pig <noreply@{noreply_domain}>").parse()?)
        .reply_to(admin.parse()?)
        .to(details.email.parse()?)
        .subject("Password Reset Request")
        .header(ContentType::TEXT_PLAIN)
        .body(formatdoc!(r#"
                Hey!

                A password request was made for your account. If you didn't request it, delete this message.

                Otherwise, follow this URL to reset your password:
                https://{domain}/handle_password_reset/{email}#{token}

                Regards,
                Wag, the pig
                "#,
            token = bundle.token,
            email = details.email
        ))?;

    transport.send(msg).await?;

    current_job.complete().await?;
    Ok(())
}

#[derive(Debug, Deserialize, Serialize)]
pub(crate) struct RegistrationDetails {
    pub email: String,
}

fn log_err<T, E: core::fmt::Debug + Into<Box<dyn std::error::Error + Send + Sync + 'static>>>(msg: &str, r: Result<T, E>) -> Result<T, E> {
    if let Err(ref e) = r {
        debug!("{}: {:?}", msg, e)
    }
    r
}

#[job(channel_name = "emails")]
pub(crate) async fn request_registration(
    mut current_job: CurrentJob,
    transport: AsyncSmtpTransport<Tokio1Executor>,
    CanonDomain(domain): CanonDomain,
    AdminEmail(admin): AdminEmail,
    auth: biscuits::Authentication,
) -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    let details: RegistrationDetails = current_job.json()?.ok_or(crate::Error::Job("no job details".to_string()))?;
    let db = current_job.pool();

    let expires = SystemTime::now() + ONE_HOUR;
    let bundle = log_err("bundle token", auth.reset_password(&details.email, expires))?;
    let _ = Revocation::add_batch(db, bundle.revocation_ids, details.email.clone(), expires).await?;

    let noreply_domain = domain.split(":").next().unwrap_or("example.com");

    debug!("Building registration message for {:?} from {:?}", details, admin);
    let msg = log_err("build message", Message::builder()
        .from(log_err("noreply email", format!("Wag the Pig <noreply@{noreply_domain}>").parse())?)
        .reply_to(log_err("admin email", admin.parse())?)
        .to(log_err("user email", details.email.parse())?)
        .subject("Account Registration")
        .header(ContentType::TEXT_PLAIN)
        .body(formatdoc!(r#"
                Hey!

                We got a request to register an account for this email address.
                If you didn't ask for this, please delete this email, with our apologies.

                Otherwise, follow this URL to finish getting set up!
                https://{domain}/handle_registration/{email}#{token}

                Regards,
                Wag, the pig
                "#,
            token = bundle.token,
            email = details.email
        )))?;

    debug!("Sending message");
    transport.send(msg).await?;

    debug!("Marking job complete");
    current_job.complete().await?;
    Ok(())
}

#[test]
fn test_mail_parsing() {
    let domain = "localhost";
    let reply: lettre::message::Mailbox = format!("Wag the Pig <noreply@{}>", domain).parse().expect("clean parse");
    println!("{:?}", reply);
}

pub(crate) fn build_transport(address: &str, port: &str, user: &str, pass: &str, cert: Option<String>) -> Result<Transport, Error> {
    debug!("Configuring SMTP transport: {address:?}:{port:?} user:{user:?} cert: {cert:?}");
    let xport_builder =Transport::starttls_relay(address)?
        .port(port.parse()?)
        .credentials(Credentials::new(user.to_string(), pass.to_string()))
        .authentication(vec![Mechanism::Plain]);
    let xport_builder = if let Some(path) = cert {
        let data = std::fs::read(path)?;
        let pem = Certificate::from_pem(&data)?;
        let tlsparams = TlsParameters::builder(address.to_string())
            .add_root_certificate(pem)
            .build()?;
        xport_builder.tls(Tls::Required(tlsparams))
    } else {
        xport_builder
    };
    Ok(xport_builder.build())
}


#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("lettre error: ${0:?}")]
    Smtp(#[from] lettre::transport::smtp::Error),
    #[error("configuration error: non-numeric port: ${0:?}")]
    Config(#[from] std::num::ParseIntError),
    #[error("io error loading file: ${0:?}")]
    IO(#[from] std::io::Error),
}
