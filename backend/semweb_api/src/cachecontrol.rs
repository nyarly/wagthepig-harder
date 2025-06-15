use std::task::{Context, Poll};

use chrono::{TimeDelta, Utc};
use hyper::{header, Method};
use tower::{Layer, Service};
use axum::{
    extract::Request, http::HeaderValue, response::Response
};
use futures_util::future::BoxFuture;


#[derive(Clone)]
pub struct CacheControlLayer {
    after: i64
}

impl CacheControlLayer {
    pub fn new(after: i64) -> Self {
        Self{after}
    }
}

impl<S> Layer<S> for CacheControlLayer {
    type Service = CacheControlMiddleware<S>;

    fn layer(&self, inner: S) -> Self::Service {
        CacheControlMiddleware{
            after: self.after,
            inner,
        }
    }
}

#[derive(Clone)]
pub struct CacheControlMiddleware<S> {
    inner: S,
    after: i64
}

impl<S> Service<Request> for CacheControlMiddleware<S>
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
        match request.method() {
            &Method::GET => {
                let future = self.inner.call(request);
                let after = self.after;
                Box::pin(async move {
                    let mut response: Response = future.await?;
                    let headers = response.headers_mut();
                    headers.entry(header::EXPIRES).or_insert_with(|| {
                        let expires = Utc::now().checked_add_signed(TimeDelta::seconds(after));
                        expires.and_then(|at| {
                            HeaderValue::from_bytes(format!("{}", at.format("%a, %d %b %Y %H:%M:%S GMT")).as_bytes()).ok()
                        }).expect("time math to work")
                    });
                    headers.entry(header::CACHE_CONTROL).or_insert_with(|| {
                        HeaderValue::from_bytes(format!("max-age={after}").as_bytes()).expect("byte formatting")
                    });
                    Ok(response)
                })
            }
            _ => {
                let future = self.inner.call(request);
                Box::pin(async move {
                    let response: Response = future.await?;
                    Ok(response)
                })
            }
        }
    }
}
