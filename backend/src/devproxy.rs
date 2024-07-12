use axum::{
    body::Body, extract::{Request, State}, http::{uri::Uri, StatusCode}, response::{IntoResponse as _, Response}
};
use hyper_util::client::legacy::connect::HttpConnector;

pub type Client = hyper_util::client::legacy::Client<HttpConnector, Body>;

pub async fn handler(State(client): State<Client>, mut req: Request) -> Result<Response, StatusCode> {
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
