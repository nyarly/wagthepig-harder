use iri_string::{spec::IriSpec, template::UriTemplateStr};
use semweb_api_derives::{Listable,Context};

use crate::routing::Listable;

mod routing {
    pub(crate) trait Listable {
        fn list_vars(&self) -> Vec<String>;
    }
}

#[allow(dead_code)] // I just want to check that it lists the field names
#[derive(Default, Listable)]
struct AListable {
    event_id: u16,
    user_id: String
}

#[derive(Default, Context)]
struct AContext {
    event_id: u16,
    user_id: String
}

#[test]
fn smoke_listable(){
    let alist = AListable::default();
    assert_eq!(alist.list_vars(), vec!["event_id".to_string(), "user_id".to_string()]);
}

#[test]
fn smoke_context(){
    let ctx = AContext{
        event_id: 17,
        user_id: "mikey".to_string(),
    };
    let template = UriTemplateStr::new("{event_id}xxx-{user_id}").expect("new");
    assert_eq!(template.expand::<IriSpec,_>(&ctx).expect("expand").to_string(),
        "17xxx-mikey".to_string()
    )
}
