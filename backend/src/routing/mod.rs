use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex, OnceLock, RwLock}
};

use axum::{http, response::IntoResponse};
use iri_string::{
    spec::IriSpec,
    template::{
        simple_context::SimpleContext,
        UriTemplateStr,
        UriTemplateString
    },
    types::UriRelativeString
};
use regex::Regex;
use serde::de::DeserializeOwned;

use self::{
    parser::{Parsed, Part},
    render::{auth_re_string, axum7_rest, axum7_vars, original_string, path_re_string, re_names}
};

mod parser;
mod render;
mod de;

pub(crate) trait RouteTemplate: Copy {
    fn route_template(&self) -> String;
}

#[derive(Default)]
pub(crate) struct Map {
    templates: HashMap<String, String>,
    store: HashMap<String, Arc<RwLock<InnerSingle>>>
}

static THE_MAP:  OnceLock<Arc<Mutex<Map>>> = OnceLock::new();

fn the_map() -> Arc<Mutex<Map>> {
    THE_MAP.get_or_init(|| Arc::new(Mutex::new(Map::default()))).clone()
}

impl Map {
    fn named(& mut self, rt: impl RouteTemplate) -> Result<Arc<RwLock<InnerSingle>>, Error> {
        let template = rt.route_template();
        let template = self.templates.entry(template.clone()).or_insert(template);
        if self.store.contains_key(template) {
            self.store.get(template)
                .ok_or(Error::Parsing("couldn't get value for contained key".to_string()))
                .cloned()
        } else {
            let route = Arc::new(RwLock::new(InnerSingle{
                parsed: parser::parse(template) .map_err(|e| Error::Parsing(format!("{:?}", e)))?,
                ..InnerSingle::default()
            }));
            self.store.insert(template.to_string(), route);
            self.store.get(template)
                .ok_or(Error::Parsing("couldn't get value for just-inserted key".to_string()))
                .cloned()
        }
    }
}

pub(crate) fn route_config(rm: impl RouteTemplate) -> Single {
    let arcmutex = the_map();
    let mut map = arcmutex.lock().expect("route map not to be poisoned");
    let inner = map.named(rm).expect("routes to be parseable");
    Single{
        inner: inner.clone()
    }
}

pub(crate) enum FillPolicy {
    Relaxed,
    NoMissing,
    NoExtra,
    Strict
}

// We have a RwLock here because we would like to be able to cache rendering in the InnerSingle To
// do that, we'd need to be able to accept a &mut self, or else replace the innersingle with a
// cloned version where we update the values (imagine InnerSingle with OnceLocks for many of its
// methods) at some point, we might also decide that a given InnerSingle is close enough to done
// and finish its rendering, and have a FixedSingle or something. Or just start there: render out
// all the things a given route might need and cache that. For the time being, we'll render each
// time (and just get read locks), but at some point in the future there's another round of
// over-engineering to tackle
pub(crate) struct Single {
    inner: Arc<RwLock<InnerSingle>>,
}

impl Single {
    pub(crate) fn axum_route(&self) -> String {
        let inner = self.inner.read().expect("not poisoned");
        inner.axum_route()
    }

    pub(crate) fn fill(&self, vars: impl IntoIterator<Item = (String, String)>) -> Result<UriRelativeString, Error> {
        let inner = self.inner.read().expect("not poisoned");
        inner.fill(vars)
    }

    pub(crate) fn template(&self) -> Result<UriTemplateString, Error> {
        let inner = self.inner.read().expect("not poisoned");
        inner.template()
    }

    pub(crate) fn hydra_type(&self) -> String {
        let inner = self.inner.read().expect("not poisoned");
        inner.hydra_type()
    }

    pub(crate) fn prefixed(&self, prefix: &str) -> Single
    {
        let mut inner = self.inner.write().expect("not poisoned");
        Single{
            inner: Arc::new(RwLock::new(inner.prefixed(prefix)))
        }
    }
}

#[derive(Default, Clone)]
struct InnerSingle {
    parsed: Parsed,
    prefixes: HashMap<String, InnerSingle>
}


impl InnerSingle {
    fn auth_expressions(&self) -> Vec<Part> {
        match &self.parsed.auth {
            Some(parts) => parts.iter().filter(|part| {
                !matches!(part, Part::Lit(_))
            }).cloned().collect(),
            None => vec![]
        }
    }

    fn path_expressions(&self) -> Vec<Part> {
        self.parsed.path.iter().filter(|part| {
            !matches!(part, Part::Lit(_))
        }).cloned().collect()
    }

    fn query_expressions(&self) -> Vec<Part> {
        match &self.parsed.query {
            Some(parts) => parts.iter().filter(|part| {
                !matches!(part, Part::Lit(_))
            }).cloned().collect(),
            None => vec![]
        }
    }

    fn expressions(&self) -> Vec<Part> {
        self.auth_expressions().iter()
            .chain(self.path_expressions().iter())
            .chain(self.query_expressions().iter())
            .cloned().collect()

    }

    fn vars(&self) -> HashSet<String> {
        let mut allvars: HashSet<String> = Default::default();
        for exp in self.expressions() {
            match exp {
                Part::Expression(exp) |
                Part::SegVar(exp) |
                Part::SegRest(exp) |
                Part::SegPathVar(exp) |
                Part::SegPathRest(exp) => {
                    for var in exp.varspecs {
                        allvars.insert(var.varname.to_string());
                    }
                }
                Part::Lit(_) => ()

            }
        }
        allvars
    }

    pub(crate) fn hydra_type(&self) -> String {
        if self.expressions().is_empty() {
            "Link".to_string()
        } else {
            "IriTemplate".to_string()
        }
    }

    pub(crate) fn prefixed(&mut self, prefix: &str) -> Self {
        let prefix_owned = prefix.to_owned();
        if self.prefixes.contains_key(&prefix_owned) {
            self.prefixes.get(&prefix_owned)
                .expect("couldn't get value for contained key")
                .clone()
        } else {
            let mut prefixed = InnerSingle{
                ..self.clone()
            };
            prefixed.parsed.path.insert(0, Part::Lit(prefix.to_owned()));
            self.prefixes.insert(prefix_owned.to_string(), prefixed.clone());
            prefixed
        }
    }

    fn re_str(&self) -> String {
        let mut re = self.parsed.auth.iter().flatten().map(auth_re_string)
            .chain(self.parsed.path.iter().map(path_re_string))
            .collect::<Vec<_>>().join("");
        re.push_str("[?#]?.*");
        re
    }

    fn re_names(&self) -> Vec<String> {
        self.parsed.auth.iter().flatten().map(re_names)
            .chain(self.parsed.path.iter().map(re_names))
            .flatten().collect::<Vec<_>>()
    }

    // definitely consider caching this result
    fn regex(&self) -> Result<Regex, regex::Error> {
        Regex::new(&self.re_str())
    }

    fn extract<T: DeserializeOwned>(&self, url: &str) -> Result<T, Error> {
        let caps = self.regex()?.captures(url)
            .ok_or_else(|| Error::NoMatch(self.re_str(), url.to_string()))?;
        let names = self.re_names();
        let captures = names.into_iter()
            .filter_map(|name|
                caps.name(&name)
                    .and_then(move |m| percent_decode(m.as_str())
                        .map(move |value| (Arc::from(name.as_str()), value)
                    )
                )
        ).collect::<Vec<_>>();

        T::deserialize(de::CapturesDeserializer::new(&captures))
            .map_err(Error::from)
    }

    fn template_string(&self) -> String {
        self.parsed.auth.iter().flatten().map(original_string)
        .chain(self.parsed.path.iter().map(original_string))
        .chain(self.parsed.query.iter().flatten().map(original_string))
        .collect::<Vec<_>>().join("")
    }

    pub(crate) fn template(&self) -> Result<UriTemplateString, Error> {
        let string = self.template_string();
        let t = UriTemplateStr::new(&string)?;
        Ok(t.into())
    }

    pub(crate) fn fill_uritemplate(&self, policy: FillPolicy, vars: impl IntoIterator<Item = (String, String)>) -> Result<UriRelativeString, Error> {
        let mut missing = self.vars();
        let mut extra: HashSet<String> = Default::default();
        let mut context = SimpleContext::new();

        for (k,v) in vars {
            if missing.remove(&k) {
                extra.insert(k.clone());
            }
            context.insert(k,v);
        }

        match (policy, missing.is_empty(), extra.is_empty()) {
            (FillPolicy::Strict, false, _) |
            (FillPolicy::NoMissing, false, _) =>
                Err(Error::MissingCaptures(missing.iter().cloned().collect())),
            (FillPolicy::Strict, _, false) |
            (FillPolicy::NoMissing, _, false) =>
                Err(Error::ExtraCaptures(extra.iter().cloned().collect())),
            _ => Ok(UriTemplateStr::new("")?
                .expand::<IriSpec, _>(&context)?
                .to_string().try_into()?),
        }
    }

    pub(crate) fn fill(&self, vars: impl IntoIterator<Item = (String, String)>) -> Result<UriRelativeString, Error> {
        self.fill_uritemplate(FillPolicy::NoMissing, vars)
    }

    pub(crate) fn axum_route(&self) -> String {
        let mut out = "".to_string();

        for part in &self.parsed.path { match part {
            Part::Lit(l) => out.push_str(l),
            Part::Expression(exp) |
            Part::SegVar(exp) |
            Part::SegPathVar(exp) => out.push_str(&axum7_vars(&exp.varspecs)),
            Part::SegRest(exp) |
            Part::SegPathRest(exp) => out.push_str(&axum7_rest(&exp.varspecs))
        }}

        out
    }
}

fn percent_decode<S: AsRef<str>>(s: S) -> Option<Arc<str>> {
    percent_encoding::percent_decode(s.as_ref().as_bytes())
        .decode_utf8()
        .ok()  //consider: Result?
        .map(|decoded| decoded.as_ref().into())
}

#[cfg(test)]
mod test {
    use super::*;

    fn quick_route(input: &str) -> InnerSingle {
        InnerSingle{
            parsed: parser::parse(input).unwrap(),
            ..Default::default()
        }
    }

    #[test]
    fn round_trip() {
        let input = "http://example.com/user/{user_id}{?something,mysterious}";

        let route = quick_route(input);

        assert_eq!(
            route.template_string(),
            input.to_string()
        )
    }

    #[test]
    fn prefixing() {
        let mut route = quick_route("http://example.com/user/{user_id}{?something,mysterious}");
        let prefixed = route.prefixed("/api");
        assert_eq!(
            prefixed.template_string(),
             "http://example.com/api/user/{user_id}{?something,mysterious}".to_string()
            //                  ^^^^
        )
    }

    #[test]
    fn axum_routes() {
        let rc = quick_route("/api/event/{event_id}");
        assert_eq!(rc.axum_route(), "/api/event/:event_id".to_string());
    }
    /*
    * Considerations for regexp:
    * if lits include //, we can sensibly match variables in auth part;
    * otherwise, we have to match '[^/]* //[^/]*' for the authority
    */
    #[test]
    fn regex() {
        let route = quick_route("http://{domain}/user/{user_id}/file{/file_id}?something={good}{&mysterious}");
        assert_eq!(
            route.re_str(),
            "http://(?<domain>[^/,]*)/user/(?<user_id>[^/?#,]*)/file/(?<file_id>[^/?#/]*)[?#]?.*"
        );
    }

    /*
    #[test]
    fn extraction() {
        let route = quick_route("http://{domain}/user/{user_id}/file{/file_id}?something={good}{&mysterious}");
        let uri = "http://example.com/user/me@nowhere.org/file/17?something=weird&mysterious=100";
        assert_eq!(route.extract(uri), ("me@nowhere.org", 17));
    }
    */
}

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("trouble parsing: {0:?}")]
    Parsing(String),
    #[error("couldn't validate IRI: {0:?}")]
    IriValidate(#[from] iri_string::validate::Error),
    #[error("error processing IRI template: {0:?}")]
    IriTempate(#[from] iri_string::template::Error),
    #[error("creating a string for an IRI: {0:?}")]
    CreateString(#[from] iri_string::types::CreationError<std::string::String>),
    #[error("missing captures: {0:?}")]
    MissingCaptures(Vec<String>),
    #[error("extra captures: {0:?}")]
    ExtraCaptures(Vec<String>),
    #[error("cannot parse string as a header value: {0:?}")]
    InvalidHeaderValue(#[from] http::header::InvalidHeaderValue),
    #[error("regex parse: {0:?}")]
    RegexParse(#[from] regex::Error),
    #[error("no match: {0:?} vs {1:?}")]
    NoMatch(String, String),
    #[error("capture deserialization: {0:?}")]
    Deserialization(#[from] de::CaptureDeserializationError),
}


impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        use http::status::StatusCode;
        match self {
            // might specialize these errors more going forward
            // need to consider server vs client
            Error::Deserialization(_) |
            Error::NoMatch(_,_) |
            Error::RegexParse(_) |
            Error::Parsing(_) |
            Error::InvalidHeaderValue(_) |
            Error::IriTempate(_) |
            Error::CreateString(_) |
            Error::ExtraCaptures(_) |
            Error::MissingCaptures(_) |
            Error::IriValidate(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()).into_response(),
        }
    }
}
