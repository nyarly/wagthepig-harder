use axum::{
    routing::get,
    Router
};
use hyper_util::{client::legacy::connect::HttpConnector, rt::TokioExecutor};
use tower_http::trace::TraceLayer;
use tracing::Level;

mod devproxy;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_max_level(Level::TRACE)
        .init();

    let client: devproxy::Client =
        hyper_util::client::legacy::Client::<(), ()>::builder(TokioExecutor::new())
            .build(HttpConnector::new());

    let app = Router::new().route("/api", get(|| async { "Hello, World!" }))
        .fallback(devproxy::handler)
        .layer(TraceLayer::new_for_http())
        .with_state(client);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    tracing::debug!("listening on {}", listener.local_addr().unwrap());

    axum::serve(listener, app).await.unwrap();
}
