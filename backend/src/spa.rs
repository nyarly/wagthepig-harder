use std::{error::Error as StdError, path};

use axum::Router;
use notify::Watcher;
use tower_http::services::{ServeDir, ServeFile};
use tower_livereload::LiveReloadLayer;

pub fn livereload<S: Clone + Send + Sync + 'static>(router: Router<S>, frontend_path: String) -> Result<Router<S>,Box<dyn StdError>> {
    let livereload = LiveReloadLayer::new();
    let reloader = livereload.reloader();

    let app = router
        .nest_service("/",
            ServeDir::new(path::Path::new(&frontend_path))
                .fallback(ServeFile::new(format!("{}/html/index.html", frontend_path)))
        )
        .layer(livereload);

    let mut watcher = notify::recommended_watcher(move |_| reloader.reload())?;
    watcher.watch(path::Path::new(&frontend_path), notify::RecursiveMode::Recursive)?;

    Ok(app)
}
