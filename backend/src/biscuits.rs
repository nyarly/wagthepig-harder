use axum::extract::FromRef;
use axum::{extract, RequestExt};
use axum_extra::extract as extra_extract;
use axum::response::IntoResponse;

use biscuit_auth::{format::schema::AuthorizerSnapshot, macros::{authorizer, biscuit, fact}};
use biscuit_auth::{error, Authorizer, AuthorizerLimits, Biscuit, KeyPair, PrivateKey};

use axum::{
    response::Response,
    extract::Request,
};
use futures::future::ok;
use futures::{ready, Future, FutureExt};
use futures_util::future::BoxFuture;
use hyper::StatusCode;
use pin_project_lite::pin_project;
use tower::{Service, Layer};
use tracing::debug;
use std::collections::HashMap;

use std::fs::File;
use std::io::{Read, Write};
use std::net::SocketAddr;
use std::path::Path;
use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::{Duration, SystemTime};

/// A convenience method for building a authentication token
/// The result is a biscuit_auth::Biscuit.to_base64()
pub fn authority(auth: &Authentication, userid: String, ttl: u64, maybe_addr: Option<SocketAddr>) -> Result<String, Error> {
    let now = SystemTime::now();
    let expires = now + Duration::from_secs(ttl);
    let mut builder = biscuit!(r#"
        user({userid});
        issued_at({now});
        check if time($time), $time < {expires};
        "#);
    if let Some(addr) = maybe_addr {
        let addr_str = addr.ip().to_string();
        builder.add_fact(fact!("client_ip({addr_str})"))?;
    }
    Ok(builder.build(&auth.keypair())?.to_base64()?)
}

async fn find_facts(header: String, root: PrivateKey, mut request: Request) -> Result<Request, Error> {
    let token = request.headers().get(header.clone())
        .map(|val| Biscuit::from_base64(val.as_bytes(), root.public())).transpose()?;

    let version = request.version();
    let version_str = format!("{:?}", version);

    let method = request.method().clone();
    let method_str = method.as_str();

    let uri = request.uri().clone();
    let uri_path = uri.path();

    let maybe_uri_scheme = uri.scheme_str();
    let maybe_uri_port = uri.port_u16();
    let maybe_path_and_query = uri.path_and_query();

    let extract::Host(host) = request.extract_parts().await?;

    let matched_path = request.extract_parts::<extract::MatchedPath>().await?;
    let full_route = matched_path.as_str();

    let nested_path = request.extract_parts::<extract::NestedPath>().await?;
    let nested_at = nested_path.as_str();

    let maybe_route = full_route.strip_prefix(nested_at);

    let mut auth = authorizer!( r#"
        version({version_str});
        host({host});
        method({method_str});
        full_route({full_route});
        nested_at({nested_at});
        path({uri_path});
        "#);

    if let Some(route) = maybe_route {
        auth.add_fact(fact!("route({route})"))?;
    }

    if let Some(uri_scheme) = maybe_uri_scheme {
        auth.add_fact(fact!("uri_scheme({uri_scheme})"))?;
    }

    if let Some(uri_port) = maybe_uri_port {
        let uri_port = uri_port as i64;
        auth.add_fact(fact!("uri_port({uri_port})"))?;
    }

    if let Some(path_and_query) = maybe_path_and_query {
        let full_path_str = path_and_query.as_str();
        auth.add_fact(fact!("full_path({full_path_str})"))?;
    }

    let maybe_connection_info = request.extract_parts::<Option<extract::ConnectInfo<SocketAddr>>>().await.expect("infallible to mean infallible");
    if let Some(extract::ConnectInfo(addr)) = maybe_connection_info {
        let ip = addr.ip().to_string();
        auth.add_fact(fact!("client_ip({ip})"))?;
    }

    let path_params = request.extract_parts::<extract::RawPathParams>().await?;
    for (key, value) in &path_params {
        auth.add_fact(fact!("path_param({key}, {value})"))?;
    }

    let extra_extract::Query(query_params): extra_extract::Query<HashMap<String, String>> = request.extract_parts().await?;
    for (key, value) in query_params {
        auth.add_fact(fact!("query_param({key}, {value})"))?;
    }

    let ctx = AuthContext{ authority: token, authorizer: auth };
    request.extensions_mut().insert(ctx);
    Ok(request)
}

fn check_authentication(policy_snapshot: AuthorizerSnapshot, request: Request) -> Result<Request, Error> {
    let ctx = request.extensions().get::<AuthContext>().ok_or(Error::MissingContext)?.clone();
    let token = match ctx.authority {
        Some(token) => token,
        None => return Err(Error::NoToken),
    };
    let mut az = ctx.authorizer;
    let policy = Authorizer::from_snapshot(policy_snapshot)?;
    az.merge(policy);
    az.set_time();
    az.add_token(&token)?;
    az.set_limits(AuthorizerLimits{
        max_time: Duration::from_millis(20),
        ..Default::default()
    });
    debug!("Authorizing against: \n{}", az.dump_code());
    match az.authorize() {
        Ok(idx) => {
            // XXX conditional compile?
            debug!("Authorized by: \n{}", match az.save()?.policies.get(idx){
                Some(pol) => format!("{}", pol),
                None => "<cannot find authorizing policy!>".to_string()
            });
            Ok(request)
        },
        Err(err) => {
            debug!("Authorization rejected: {}", err);
            Err(Error::AuthorizationFailed)
        }
    }
}

#[derive(Clone)]
pub struct AuthContext {
    authority: Option<Biscuit>,
    authorizer: Authorizer
}

#[derive(Clone, FromRef)]
pub struct Authentication {
    private_key: PrivateKey
}

impl Authentication {
    pub fn new<P: AsRef<Path> + Clone>(persist_path: P) -> Result<Self, Box<dyn std::error::Error>> {
        let private_key = match File::open(persist_path.clone()) {
            Ok(mut f) => {
                let mut k = String::new();
                f.read_to_string(&mut k)?;
                PrivateKey::from_bytes_hex(&k)?
            },
            Err(err) if err.kind() == io::ErrorKind::NotFound => {
                let kp = KeyPair::new();
                let data = kp.private().to_bytes_hex();
                let mut f = File::create_new(persist_path)?;
                f.write_all(data.as_bytes())?;
                kp.private()
            },
            Err(e) => Err(e)?
        };
        Ok(Self{private_key})
    }

    fn keypair(&self) -> KeyPair {
        KeyPair::from(&(self.private_key))
    }
}

/*
struct AuthenticationExtractor(Authentication);

#[async_trait]
impl<S> extract::FromRequestParts<S> for AuthenticationExtractor
where
    // keep `S` generic but require that it can produce a `MyLibraryState`
    // this means users will have to implement `FromRef<UserState> for MyLibraryState`
    Authentication: FromRef<S>,
    S: Send + Sync,
{
    type Rejection = Infallible;

    async fn from_request_parts(_parts: &mut request::Parts, state: &S) -> Result<Self, Self::Rejection> {
        let state = Authentication::from_ref(state);
        Ok(Self(state))
    }
}
*/


#[derive(Clone)]
pub struct AuthenticationSetup {
    pub root: Authentication,
    pub header: String,
}

impl AuthenticationSetup {
    pub fn new<S: Into<String>>(root: Authentication, header: S) -> Self {
        Self{ root, header: header.into() }
    }
}

impl<S> Layer<S> for AuthenticationSetup {
    type Service = SetupMiddleware<S>;

    fn layer(&self, inner: S) -> Self::Service {
        SetupMiddleware {
            inner,
            root: self.root.clone(),
            header: self.header.clone()
        }
    }
}

pub trait IntoPolicySnapshot {
    fn into_snapshot(self) -> AuthorizerSnapshot;
}

impl IntoPolicySnapshot for String {
    fn into_snapshot(self) -> AuthorizerSnapshot {
        let mut az = Authorizer::new();
        az.add_code(self).expect("policy must parse");
        az.snapshot().expect("authorizor to snapshot from string")
    }
}

impl IntoPolicySnapshot for Authorizer {
    fn into_snapshot(self) -> AuthorizerSnapshot {
        self.snapshot().expect("authorizor to snapshot")
    }
}

impl IntoPolicySnapshot for AuthorizerSnapshot {
    fn into_snapshot(self) -> AuthorizerSnapshot {
        self
    }
}

#[derive(Clone)]
pub struct AuthenticationCheck {
    pub policy: AuthorizerSnapshot,
}

impl AuthenticationCheck {
    pub fn new<P: IntoPolicySnapshot>(policy: P) -> Self {
        Self{ policy: policy.into_snapshot() }
    }
}

impl<S> Layer<S> for AuthenticationCheck {
    type Service = CheckMiddleware<S>;

    fn layer(&self, inner: S) -> Self::Service {
        CheckMiddleware {
            inner,
            policy: self.policy.clone()
        }
    }
}

#[derive(Clone)]
pub struct SetupMiddleware<S> {
    inner: S,
    root: Authentication,
    header: String,
}

impl<S> Service<Request> for SetupMiddleware<S>
where
    S: Service<Request, Response = Response> + Send + Clone + 'static,
    S::Future: Send + 'static,
    S::Error: Send
{
    type Response = S::Response;
    type Error = S::Error;
    // `BoxFuture` is a type alias for `Pin<Box<dyn Future + Send + 'a>>`
    type Future = SetupFuture<BoxFuture<'static, Result<Request, Error>>, S>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request) -> Self::Future {
        let future = find_facts(self.header.clone(), self.root.private_key.clone(), request);

        SetupFuture::new(future.boxed(), self.inner.clone())
    }
}

#[derive(Clone)]
pub struct CheckMiddleware<S> {
    inner: S,
    policy: AuthorizerSnapshot,
}

impl<S> Service<Request> for CheckMiddleware<S>
where
    S: Service<Request, Response = Response> + Send + Clone + 'static,
    S::Future: Send + 'static,
    S::Error: Send
{
    type Response = S::Response;
    type Error = S::Error;
    // `BoxFuture` is a type alias for `Pin<Box<dyn Future + Send + 'a>>`
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request) -> Self::Future {
        match check_authentication(self.policy.clone(), request) {
            Ok(req) =>  {
                let future = self.inner.call(req);
                Box::pin(async move {
                    let response: Response = future.await?;
                    Ok(response)
                })
            },
            Err(e) => {
                let future = ok(e.into_response());
                Box::pin(async move {
                    let response: Response = future.await?;
                    Ok(response)
                })
            }
        }
    }
}

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("issue building token: {0:?}")]
    Token(#[from] biscuit_auth::error::Token),
    #[error("routing match error")]
    MatchedPath(#[from] extract::rejection::MatchedPathRejection),
    #[error("nested path error")]
    NestedPath(#[from] extract::rejection::NestedPathRejection),
    #[error("extension error")]
    Extension(#[from] extract::rejection::ExtensionRejection),
    #[error("extracting path params")]
    PathParams(#[from] extract::rejection::RawPathParamsRejection),
    #[error("extracting host")]
    Host(#[from] extract::rejection::HostRejection),
    #[error("extracting query params")]
    Query(#[from] extra_extract::QueryRejection),
    #[error("no authentication context found")]
    MissingContext,
    #[error("no authentication credential token found")]
    NoToken,
    #[error("authorization failed")]
    AuthorizationFailed,
}

impl IntoResponse for Error {
    fn into_response(self) -> Response {
        match self {
            Error::Token(err) => {
                match err {
                    error::Token::ConversionError(_) => (StatusCode::BAD_REQUEST, "couldn't convert token").into_response(),
                    error::Token::Base64(_) => (StatusCode::BAD_REQUEST, "invalid token encoding").into_response(),
                    error::Token::Format(_) => (StatusCode::BAD_REQUEST, "invalid token format").into_response(),
                    _ => (StatusCode::INTERNAL_SERVER_ERROR, "internal authentication error").into_response()
                }
            }
            Error::MatchedPath(mpe) => mpe.into_response(),
            Error::NestedPath(e) => e.into_response(),
            Error::Extension(ee) => ee.into_response(),
            Error::PathParams(e) => e.into_response(),
            Error::Host(e) => e.into_response(),
            Error::Query(e) => e.into_response(),
            Error::MissingContext => (StatusCode::INTERNAL_SERVER_ERROR, "missing authorization context").into_response(), // 500
            Error::NoToken => (StatusCode::UNAUTHORIZED, "/api/authentication").into_response(),
            Error::AuthorizationFailed => (StatusCode::FORBIDDEN, "insufficient access").into_response(),
        }
    }
}

pin_project! {
    #[derive(Debug)]
    pub struct SetupFuture<F, S>
    where
        F: Future,
        S: Service<Request>,
    {
        #[pin]
        state: State<F, S::Future>,

        // Inner service
        service: S,
    }
}

pin_project! {
    #[project = StateProj]
    #[derive(Debug)]
    enum State<F, G> {
        /// Waiting for the find future
        Extracting {
            #[pin]
            extraction: F
        },
        /// Waiting for the response future
        WaitResponse {
            #[pin]
            response: G
        },
    }
}

impl<F, S> SetupFuture<F, S>
where
    F: Future,
    S: Service<Request>,
{
    pub(crate) fn new(extraction: F, service: S) -> Self {
        Self {
            state: State::Extracting { extraction },
            service,
        }
    }
}

impl<F, S> Future for SetupFuture<F, S>
where
    F: Future<Output = Result<Request, Error>>,
    S: Service<Request, Response = Response> + Send + 'static,
{
    type Output = Result<Response, S::Error>;

    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let mut this = self.project();

        loop {
            match this.state.as_mut().project() {
                StateProj::Extracting { mut extraction } => {
                    match ready!(extraction.as_mut().poll(cx)) {
                        Ok(request) => {
                            let response = this.service.call(request);
                            this.state.set(State::WaitResponse { response });
                        }
                        Err(e) => return Poll::Ready(Ok(e.into_response()))
                    }

                }
                StateProj::WaitResponse { response } => {
                    return response.poll(cx).map_err(Into::into);
                }
            }
        }
    }
}
