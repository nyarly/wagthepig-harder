use std::{
    collections::{HashMap, HashSet}, sync::{Arc, Mutex, OnceLock, RwLock}
};

use iri_string::{
    spec::IriSpec,
    template::{
        DynamicContext, UriTemplateStr, UriTemplateString
    }, types::IriReferenceString
};
use regex::Regex;
use render::fill_parts;
use serde::de::DeserializeOwned;
use tracing::{debug, trace};

use crate::error::Error;

use self::{
    parser::{Parsed, Part},
    render::{auth_re_string, axum7_rest, axum7_vars, original_string, path_re_string, re_names}
};

mod parser;
mod render;
mod de;
pub use de::CaptureDeserializationError;

pub trait RouteTemplate: Copy {
    fn route_template(&self) -> String;

    fn prefixed(self, at: &str) -> Entry {
        route_config(self).prefixed(at)
    }
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
    fn named(&mut self, rt: impl RouteTemplate) -> Result<Arc<RwLock<InnerSingle>>, Error> {
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

pub fn route_config(rm: impl RouteTemplate) -> Entry {
    let arcmutex = the_map();
    let mut map = arcmutex.lock().expect("route map not to be poisoned");
    let inner = map.named(rm).expect("routes to be parseable");
    Entry{
        inner: inner.clone()
    }
}

#[allow(dead_code)]
pub(crate) enum FillPolicy {
    Relaxed,
    NoMissing,
    NoExtra,
    Strict
}

use iri_string::template::context::{Visitor, Context};

pub trait Listable {
    fn list_vars(&self) -> Vec<String>;
}

#[derive(Clone)]
pub struct VarsList<L: IntoIterator<Item = (String, String)>>( pub L );

impl<L: Clone + IntoIterator<Item = (String, String)>> Listable for VarsList<L> {
    fn list_vars(&self) -> Vec<String> {
        self.0.clone().into_iter().map(|(k,_)| k.clone()).collect()
    }
}

impl<L: Clone + IntoIterator<Item = (String, String)>> Context for VarsList<L> {
    fn visit<V: Visitor>(&self, visitor: V) -> V::Result {
        let visited = visitor.var_name().as_str();
        // barf - complexity here is awful
        match self.0.clone().into_iter().find(|(k,_)| k == visited) {
            Some((_,v)) => visitor.visit_string(v),
            None => visitor.visit_undefined()
        }
    }
}

pub(crate) struct PolicyContext<C: Context + Listable> {
    provided: HashSet<String>,
    extra: HashSet<String>,
    missing: HashSet<String>,
    inner: C
}

impl<C: Context + Listable> PolicyContext<C> {
    fn new(inner: C) -> Self {
        Self{
            provided: HashSet::new(),
            extra: HashSet::new(),
            missing: HashSet::new(),
            inner
        }
    }

    fn check(&self, policy: FillPolicy) -> Result<(), Error> {
        match (policy, self.missing.is_empty(), self.extra.is_empty()) {
            (FillPolicy::Strict, false, _) |
            (FillPolicy::NoMissing, false, _) =>
                Err(Error::MissingCaptures(self.missing.iter().cloned().collect())),
            (FillPolicy::Strict, _, false) |
            (FillPolicy::NoExtra, _, false) =>
                Err(Error::ExtraCaptures(self.extra.iter().cloned().collect())),
            _ => Ok(())
        }
    }
}

impl<C: Context + Listable> DynamicContext for PolicyContext<C> {
    fn on_expansion_start(&mut self) {
        trace!("on_expansion_start");
        self.provided.clear();
        self.extra.clear();
        self.missing.clear();
        for v in self.inner.list_vars() {
            self.provided.insert(v.clone());
            self.extra.insert(v);
        }
        trace!("on_expansion_start: provided: {:?} extra: {:?} missing {:?}", self.provided, self.extra, self.missing);
    }

    fn visit_dynamic<V: Visitor>(&mut self, visitor: V) -> V::Result {
        let k = visitor.var_name().as_str();
        trace!("URI template fill: {:?}", k);
        self.extra.remove(k);
        if !self.provided.contains(k) {
            self.missing.insert(k.to_string());
        }
        trace!("URI template fill: provided: {:?} extra: {:?} missing {:?}", self.provided, self.extra, self.missing);
        self.inner.visit(visitor)
    }
}


// We have a RwLock here because we would like to be able to cache rendering in the InnerSingle To
// do that, we'd need to be able to accept a &mut self, or else replace the innersingle with a
// cloned version where we update the values (imagine InnerSingle with OnceLocks for many of its
// methods) at some point, we might also decide that a given InnerSingle is close enough to done
// and finish its rendering, and have a FixedSingle or something. Or just start there: render out
// all the things a given route might need and cache that. For the time being, we'll render each
// time (and just get read locks), but at some point in the future there's another round of
// over-engineering to tackle
pub struct Entry {
    inner: Arc<RwLock<InnerSingle>>,
}

impl Entry {
    pub fn axum_route(&self) -> String {
        let inner = self.inner.read().expect("not poisoned");
        inner.axum_route()
    }

    pub fn fill(&self, vars: impl Context + Listable) -> Result<IriReferenceString, Error> {
        let inner = self.inner.read().expect("not poisoned");
        inner.fill_uritemplate(FillPolicy::NoMissing, vars)
    }

    pub fn partial_fill(&self, vars: impl IntoIterator<Item = (String, String)> + Clone) -> Result<UriTemplateString, Error> {
        let inner = self.inner.read().expect("not poisoned");
        inner.partial_fill(VarsList(vars))
    }

    pub fn template(&self) -> Result<UriTemplateString, Error> {
        let inner = self.inner.read().expect("not poisoned");
        inner.template()
    }

    pub fn hydra_type(&self) -> String {
        let inner = self.inner.read().expect("not poisoned");
        inner.hydra_type()
    }

    pub fn extract<T: DeserializeOwned>(&self, url: &str) -> Result<T, Error> {
        let inner = self.inner.read().expect("not poisoned");
        inner.extract(url)
    }

    pub fn prefixed(&self, prefix: &str) -> Entry {
        let mut inner = self.inner.write().expect("not poisoned");
        Entry{
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

    fn hydra_type(&self) -> String {
        if self.expressions().is_empty() {
            "Link".to_string()
        } else {
            "IriTemplate".to_string()
        }
    }

    fn prefixed(&mut self, prefix: &str) -> Self {
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

    fn template(&self) -> Result<UriTemplateString, Error> {
        let string = self.template_string();
        let t = UriTemplateStr::new(&string)?;
        Ok(t.into())
    }

    fn fill_uritemplate(&self, policy: FillPolicy, vars: impl Context + Listable) -> Result<IriReferenceString, Error> {
        let mut pol = PolicyContext::new(vars);

        let templ = &self.template()?;
        let expanded = templ.expand_dynamic_to_string::<IriSpec,_>(&mut pol)?;
        debug!("expanded {}", expanded);
        pol.check(policy)?;
        debug!("checked {:?}", expanded);
        Ok(expanded.try_into().inspect_err(|e| debug!("try_into: {e:?}"))?)
    }

    // XXX stub impl
    fn partial_fill(&self, vars: impl Context + Listable + Clone) -> Result<UriTemplateString, Error> {
        let filled_string = self.parsed.auth.clone().map_or(Ok(vec![]), |a| fill_parts(&a, &vars))?.iter().map(original_string)
            .chain(fill_parts(&self.parsed.path, &vars)?.iter().map(original_string))
            .chain(self.parsed.query.clone().map_or(Ok(vec![]), |q| fill_parts(&q, &vars))?.iter().map(original_string))
            .collect::<Vec<_>>().join("");

        let t = UriTemplateStr::new(&filled_string)?;
        Ok(t.into())
    }

    fn axum_route(&self) -> String {
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
    use tracing_test::traced_test;

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
    #[traced_test]
    fn partial_fill() {
        let route = quick_route("http://example.com{/something,mysterious}/user{/user_id}");
        let mut vars = HashMap::new();
        vars.insert("something".to_string(), "S".to_string());
        vars.insert("mysterious".to_string(), "M".to_string());
        let tmpl_r = route.partial_fill(VarsList(vars));
        debug!("{:?}", tmpl_r);
        let tmpl = tmpl_r.unwrap();
        assert_eq!(
            tmpl.to_string(),
            "http://example.com/S/M/user{/user_id}".to_string()
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

    #[test]
    fn extraction() {
        let route = quick_route("http://{domain}/user/{user_id}/file{/file_id}?something={good}{&mysterious}");
        let uri = "http://example.com/user/me@nowhere.org/file/17?something=weird&mysterious=100";
        assert_eq!(
            route.extract::<(String, String, u16)>(uri).unwrap(),
            ("example.com".to_string(), "me@nowhere.org".to_string(), 17)
        );
    }

    #[test]
    fn extraction_errors() {
        let route = quick_route("http://{domain}/user/{user_id}/file{/file_id}?something={good}{&mysterious}");
        let uri = "http://example.com/user/me@nowhere.org/file?something=weird&mysterious=100";
        assert!(matches!(
            route.extract::<(String, String, u16)>(uri),
            Err(Error::NoMatch(_,_))
        ));
    }
}
