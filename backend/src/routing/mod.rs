use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex, OnceLock, RwLock}
};

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

use self::parser::{Parsed, Part, VarSpec};


mod parser;

pub(crate) trait RouteTemplate: Copy {
    fn route_template(&self) -> String;
}

#[derive(Default)]
pub(crate) struct Map {
    templates: HashMap<String, String>,
    store: HashMap<String, Arc<RwLock<InnerSingle>>>
}

static THE_MAP:  OnceLock<Mutex<Map>> = OnceLock::new();

fn the_map() -> &'static Mutex<Map> {
    THE_MAP.get_or_init(|| Mutex::new(Map::default()))
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
                // ..InnerSingle::default()
            }));
            self.store.insert(template.to_string(), route);
            self.store.get(template)
                .ok_or(Error::Parsing("couldn't get value for just-inserted key".to_string()))
                .cloned()
        }
    }
}

pub(crate) fn inner_route_config(rm: impl RouteTemplate) -> Arc<RwLock<InnerSingle>> {
    let mutex = the_map();
    let mut map = mutex.lock().expect("route map not to be poisoned");
    let inner = map.named(rm).expect("routes to be parseable");
    inner.clone()
}

pub(crate) fn route_config(rm: impl RouteTemplate) -> Single {
    Single{ inner: inner_route_config(rm) }
}

pub(crate) struct Single {
    inner: Arc<RwLock<InnerSingle>>
}

impl Single {
    pub(crate) fn axum_route(&self) -> String {
        let inner = self.inner.write().expect("not poisoned");
        inner.axum_route()
    }

    pub(crate) fn prefixed<'a>(&self, prefix: &'a str) -> InnerSingle
    {
        InnerSingle::default()
    }
}

#[derive(Default, Clone)]
struct InnerSingle {
    parsed: Parsed,
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
                Part::Expression(vars) |
                Part::SegVar(vars) |
                Part::SegRest(vars) |
                Part::SegPathVar(vars) |
                Part::SegPathRest(vars) => {
                    for var in vars {
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

    pub(crate) fn prefixed(&self, prefix: &str) -> Self {
        InnerSingle{
            ..self.clone()
        }
    }

    pub(crate) fn template(&self) -> Result<UriTemplateString, Error> {
        let t = UriTemplateStr::new("")?;
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
            Part::Expression(vars) |
            Part::SegVar(vars) |
            Part::SegPathVar(vars) => out.push_str(&axum7_vars(vars)),
            Part::SegRest(vars) |
            Part::SegPathRest(vars) => out.push_str(&axum7_rest(vars))
        }}

        out
    }
}

/*
* varchar       =  ALPHA / DIGIT / "_" / pct-encoded
* {/foo} => /:foo
* /{foo} => /:foo
* {foo,bar} => /:foobar // because which [,;.&=] delimits?
* {bar,foo} => /:barfoo
*
* {foo:3} => /:foopre3
* {foo,pre3} => ? /:foopre3
*
* {foo:3,bar} => /:foopre3bar
* {/foo,bar} => <slash-star> :foobar
*/
fn axum7_vars(vars: &[VarSpec]) -> String {
    format!("/:{}", vars.iter().map(|var| var.varname).collect::<Vec<_>>().join(""))
}

fn axum7_rest(vars: &[VarSpec]) -> String {
    format!("/*{}", vars.iter().map(|var| var.varname).collect::<Vec<_>>().join(""))
}

pub(crate) enum FillPolicy {
    Relaxed,
    NoMissing,
    NoExtra,
    Strict
}

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
            Err(Error::MissingCaptures(missing_vars))
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
}


impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        use http::status::StatusCode;
        match self {
            // might specialize these errors more going forward
            // need to consider server vs client
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
