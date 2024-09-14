use axum::http;
use iri_string::template::{Context, UriTemplateString};
use serde::{Deserialize, Serialize};
pub use iri_string::types::IriReferenceString;

use crate::{error::Error, routing::{self, Listable}};

#[derive(Serialize, Clone)]
#[serde(tag="type")]
pub struct IriTemplate {
    pub id: IriReferenceString,
    // pub r#type: String,
    pub template: UriTemplateString,
    pub operation: Vec<Operation>
}


#[derive(Default, Serialize, Clone)]
pub struct Operation {
    pub method: Method,
    pub r#type: ActionType,
}

#[derive(Default, Clone)]
pub struct Method(http::Method);

impl From<http::Method> for Method {
    fn from(value: http::Method) -> Self {
        Self(value)
    }
}

impl Serialize for Method {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error>
    {
        serializer.serialize_str(self.0.as_str())
    }
}


#[derive(Default, Serialize, Deserialize, Clone)]
pub enum ActionType {
    #[default]
    #[serde(rename = "ViewAction")]
    View,
    #[serde(rename = "CreateAction")]
    Create,
    #[serde(rename = "UpdateAction")]
    Update,
    #[serde(rename = "FindAction")]
    Find,
    #[serde(rename = "AddAction")]
    Add,
    #[serde(rename = "LoginAction")]
    // this is not a schema.org Action type
    Login
}

/// op is used to create a most-common operation for each action type
pub fn op(action: ActionType) -> Operation {
    use ActionType::*;
    use axum::http::Method;
    match action {
        View => Operation {
            method: Method::GET.into(),
            r#type: action
        },
        Create => Operation{
            method: Method::PUT.into(),
            r#type: action
        },
        Update => Operation{
            method: Method::PUT.into(),
            r#type: action
        },
        Find => Operation{
            method: Method::GET.into(),
            r#type: action
        },
        Add => Operation{
            method: Method::POST.into(),
            r#type: action
        },
        Login => Operation{
            method: Method::POST.into(),
            r#type: action
        }
    }
}

const RESOURCE: &str = "Resource";

#[derive(Serialize, Clone)]
pub struct ResourceType(&'static str);

impl Default for ResourceType {
    fn default() -> Self {
        Self(RESOURCE)
    }
}

#[derive(Serialize, Clone)]
pub struct ResourceFields<L: Serialize + Clone> {
    pub id: IriReferenceString,
    pub r#type: ResourceType,
    pub operation: Vec<Operation>,
    pub find_me: IriTemplate,
    pub nick: L
}

impl<L: Serialize + Clone + Listable + Context> ResourceFields<L> {
    pub fn new(route: &routing::Entry, nick: L, api_name: &str, operation: Vec<Operation>) -> Result<Self, Error> {
        let id = route.fill(nick.clone())?.into();
        let template = route.template()?;

        Ok(Self{
            id,
            nick,
            operation,
            r#type: Default::default(),
            find_me: IriTemplate {
                template,
                id: api_name.try_into()?,
                operation: vec![ op(ActionType::Find) ]
            },
        })
    }
}
