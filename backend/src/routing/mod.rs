use axum::{http, response::IntoResponse};
use iri_string::{
    spec::IriSpec,
    template::{context::VarName,
        simple_context::SimpleContext,
        UriTemplateStr,
        UriTemplateString
    },
    types::UriRelativeString
};


mod parser;

#[derive(Debug)]
pub(crate) struct Config{
    pub(crate) template_str: String,
    captures: Vec<String>,
    wildcard: Option<String>
}


fn template_munge(tmpl: &str) -> String {
    let mut tokens = tmpl.split(&['{','}']);
    let mut munged = "".to_string();

    while let Some(token) = tokens.next() {
        munged.push_str(token);
        if let Some(next) = tokens.next() {
            let (op, rest) = next.split_at(1);
            let (name, last) = rest.split_at(rest.len() - 1);
            match (op, last) {
                ("/", "*") => {
                    munged.push_str("/{+"); munged.push_str(name);
                }
                _ => {
                    munged.push_str("{+"); munged.push_str(next);
                }
            }
            munged.push('}');
        }
    }
    munged
}

impl Config {
    pub(crate) fn new( tmpl: &str, captures: Vec<&str>) -> Self {
        Self{
            template_str: tmpl.to_string(),
            captures: captures.into_iter().map(|c| c.to_string()).collect(),
            wildcard: None
        }
    }

    /*
    pub(crate) fn new_with_wildcard(tmpl: &str, captures: Vec<&str>, rest: &str) -> Self {
        Self{
            template_str: tmpl.to_string(),
            captures: captures.into_iter().map(|c| c.to_string()).collect(),
            wildcard: Some(rest.to_string())
        }
    }
    */

    pub(crate) fn hydra_type(&self) -> String {
        if self.captures.is_empty() && self.wildcard.is_none() {
            "Link".to_string()
        } else {
            "IriTemplate".to_string()
        }
    }

    pub(crate) fn prefixed(&self, prefix: &str) -> Self {
        let mut template_str = prefix.to_string();
        template_str.push_str(&self.template_str);
        Self{
            template_str,
            captures: self.captures.clone(),
            wildcard: self.wildcard.clone()
        }
    }

    pub(crate) fn template(&self) -> Result<UriTemplateString, Error> {
        let t = UriTemplateStr::new(&self.template_str)?;
        Ok(t.into())
    }

    /*
        .fill(vec![("event_id".to_string(), new_id.to_string())])
        .map_err(internal_error)
        .and_then(|location_uri| {
          location_uri.to_string().try_into().map_err(internal_error)
        })
    */
    pub(crate) fn fill(&self, vars: impl IntoIterator<Item = (String, String)>) -> Result<UriRelativeString, Error> {
        let mut context = SimpleContext::new();
        for (k,v) in vars {
            context.insert(k,v);
        }
        let mut missing_vars = vec![];
        for v in &self.captures {
            if context.get(VarName::new(v)?).is_none() {
                missing_vars.push(v.to_string())
            }
        }
        if let Some(v) = &self.wildcard {
            if context.get(VarName::new(v)?).is_none() {
                missing_vars.push(v.to_string())
            }
        }
        if missing_vars.is_empty() {
            Ok(UriTemplateStr::new(&self.template_str)?
                .expand::<IriSpec, _>(&context)?
                .to_string().try_into()?)
        } else {
            Err(Error::MissingCapture(missing_vars))
        }
    }

    pub(crate) fn axum_route(&self) -> String {
        let mut context = SimpleContext::new();
        for c in &self.captures {
            context.insert(c.clone(), format!(":{}", c));
        }
        if let Some(w) = &self.wildcard {
            context.insert(w.clone(), format!("*{}", w));
        }
        let route_template = template_munge(&self.template_str);
        let uri: UriRelativeString = UriTemplateStr::new(&route_template)
            .unwrap_or_else(|_| panic!("{:?} to have a validate template_str", self))
            .expand::<IriSpec, _>(&context)
            .unwrap_or_else(|_| panic!("{:?} to expand successfully", self))
            .to_string()
            .try_into().unwrap_or_else(|_| panic!("{:?} to render to a relative path", self));
        uri.path_str().to_string()
    }
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn axum_routes() {
        let rc = Config::new("/api/event/{event_id}", vec!["event_id"]);
        assert_eq!(rc.axum_route(), "/api/event/:event_id".to_string());
        // let rc = RouteConfig::new_with_wildcard("/api/something/{id}{/rest*}", vec!["id"], "rest");
        // assert_eq!(rc.axum_route(), "/api/something/:id/*rest".to_string());
    }
}

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("couldn't validate IRI: {0:?}")]
    IriValidate(#[from] iri_string::validate::Error),
    #[error("error processing IRI template: {0:?}")]
    IriTempate(#[from] iri_string::template::Error),
    #[error("creating a string for an IRI: {0:?}")]
    CreateString(#[from] iri_string::types::CreationError<std::string::String>),
    #[error("missing caputres: {0:?}")]
    MissingCapture(Vec<String>),
    #[error("cannot parse string as a header value: {0:?}")]
    InvalidHeaderValue(#[from] http::header::InvalidHeaderValue),
}


impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        use http::status::StatusCode;
        match self {
            // might specialize these errors more going forward
            // need to consider server vs client
            Error::InvalidHeaderValue(_) |
            Error::IriTempate(_) |
            Error::CreateString(_) |
            Error::MissingCapture(_) |
            Error::IriValidate(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()).into_response(),
        }
    }
}
