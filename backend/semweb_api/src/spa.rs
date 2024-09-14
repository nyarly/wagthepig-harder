use std::{error::Error as StdError, path};

use notify::Watcher;
use tower_http::services::{ServeDir, ServeFile};
use tower_livereload::LiveReloadLayer;
use hyper_util::client::legacy::connect::HttpConnector;
use axum::{
    Router,
    body::Body, extract::{Request, State}, http::{uri::Uri, StatusCode}, response::{IntoResponse as _, Response}
};

use tracing::debug;

/// provides a simple livereload server, both for the BE and for static files in the filesystem
#[allow(clippy::type_complexity)]
pub fn livereload<S: Clone + Send + Sync + 'static>(router: Router<S>, frontend_path: String) -> Result<(Router<S>, Box<dyn Watcher>),Box<dyn StdError>> {
    let livereload = LiveReloadLayer::new();
    let reloader = livereload.reloader();

    let app = router
        .nest_service("/",
            ServeDir::new(path::Path::new(&frontend_path))
                .fallback(ServeFile::new(format!("{}/html/index.html", frontend_path)))
        )
        .layer(livereload);

    let mut watcher = notify::recommended_watcher(move |ev| {
        debug!("livereload: file change detected: {:?}", ev);
        reloader.reload()
    })?;
    watcher.watch(path::Path::new(&frontend_path), notify::RecursiveMode::Recursive)?;

    debug!("Finished setting up livereload {:?}", watcher);
    Ok((app, Box::new(watcher)))
}

pub type Client = hyper_util::client::legacy::Client<HttpConnector, Body>;

/// provides a localhost proxy for SPA work with a separate dev server
#[allow(dead_code)]
pub async fn devproxy(State(client): State<Client>, mut req: Request) -> Result<Response, StatusCode> {
    let path = req.uri().path();
    let path_query = req
        .uri()
        .path_and_query()
        .map(|v| v.as_str())
        .unwrap_or(path);

    let uri = format!("http://localhost:8000{}", path_query);

    *req.uri_mut() = Uri::try_from(uri).unwrap();

    Ok(client
        .request(req)
        .await
        .map_err(|_| StatusCode::BAD_REQUEST)?
        .into_response())
}
