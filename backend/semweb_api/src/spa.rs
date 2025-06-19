use std::{error::Error as StdError, path};

use notify::Watcher;
use tower_http::services::{ServeDir, ServeFile};
use tower_livereload::LiveReloadLayer;
use tower_serve_static as embed;
use hyper_util::client::legacy::connect::HttpConnector;
use axum::{
    body::Body, extract::{Request, State}, http::{uri::{PathAndQuery, Uri}, StatusCode}, middleware::{self, Next}, response::{IntoResponse as _, Response}, Router
};
use include_dir::Dir;

use tracing::debug;

/// provides an embedded assets server
/// Create this like so:
/// ```
/// static ASSETS_DIR: Dir<'static> = include_dir!("$CARGO_MANIFEST_DIR/frontend");
/// embedded(router, &ASSETS_DIR);
/// ```

pub fn embedded<S: Clone + Send + Sync + 'static>(router: Router<S>, frontend_dir: &'static Dir<'static>) -> Result<Router<S>,Box<dyn StdError>> {
    let app = router
    .nest_service("/",
            embed::ServeDir::new(frontend_dir)
            //    .not_found_service(embed::ServeFile::new(format!("{}/html/index.html", frontend_path)))
        ).layer(middleware::from_fn(embedded_not_found));

    Ok(app)
}

async fn embedded_not_found(request: Request, next: Next) -> Response {
    let mut index_parts = request.uri().clone().into_parts();
    let response = next.clone().run(request).await;

    match response.status() {
        StatusCode::NOT_FOUND => {
            index_parts.path_and_query = Some(PathAndQuery::from_static("/html/index.html"));
            let index_uri = Uri::from_parts(index_parts).unwrap();
            let index_request = Request::builder()
                .uri(index_uri)
                .body(Body::empty())
                .expect("simple request to work");
            next.run(index_request).await
        },
        _ => response
    }
}


/// provides a simple file server, both for the BE and for static files in the filesystem
pub fn fileserver<S: Clone + Send + Sync + 'static>(router: Router<S>, frontend_path: &String) -> Result<Router<S>,Box<dyn StdError>> {

    let app = router
        .nest_service("/",
            ServeDir::new(path::Path::new(frontend_path))
                .not_found_service(ServeFile::new(format!("{}/html/index.html", frontend_path)))
        );

    Ok(app)
}

/// provides a simple livereload server, both for the BE and for static files in the filesystem
#[allow(clippy::type_complexity)]
pub fn livereload<S: Clone + Send + Sync + 'static>(router: Router<S>, frontend_path: &String) -> Result<(Router<S>, Box<dyn Watcher>),Box<dyn StdError>> {
    let livereload = LiveReloadLayer::new();
    let reloader = livereload.reloader();

    let app = fileserver(router, frontend_path)?
        .layer(livereload);

    let mut watcher = notify::recommended_watcher(move |ev| {
        debug!("livereload: file change detected: {:?}", ev);
        reloader.reload()
    })?;
    watcher.watch(path::Path::new(frontend_path), notify::RecursiveMode::Recursive)?;

    debug!("Finished setting up livereload {:?}", watcher);
    Ok((app, Box::new(watcher)))
}

/// provides a livereload server, both for the BE and for static files in the filesystem
/// Note that this leaks a notify::Watcher, on the assumption that you want to let that run for the
/// lifetime of the app anyway. This way, we can have type parity with e.g. fileserver
pub fn leaked_livereload<S: Clone + Send + Sync + 'static>(router: Router<S>, frontend_path: &String) -> Result<Router<S>,Box<dyn StdError>> {
    let (app, watcher) = livereload(router, frontend_path)?;
    Box::leak(watcher);
    Ok(app)
}

pub type Client = hyper_util::client::legacy::Client<HttpConnector, Body>;

/// provides a localhost proxy for SPA work with a separate dev server
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
