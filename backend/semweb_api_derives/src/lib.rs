use proc_macro::TokenStream as StdTokenStream;
use proc_macro2::{Ident, TokenStream, TokenTree};
use quote::quote;

/*
Given:
#[derive(Listable)]
struct MyLocationType {
    event_id: u16,
    user_id: String
}

we want to produce:

impl crate::routing::Listable for MyLocationType {
    fn list_vars(&self) -> Vec<String> {
        vec!["event_id".to_string(), "user_id".to_string()]
    }
}

XXX consider helper attrs to customize inclusion etc
*/

#[proc_macro_derive(Listable)]
pub fn listable_derive(annotated_item: StdTokenStream) -> StdTokenStream {
    let (struct_name, vars, _) = parse(annotated_item);

    let expanded = quote! {
        impl ::mattak::routing::Listable for #struct_name {
            fn list_vars(&self) -> Vec<String> {
                vec![#(stringify!(#vars).to_string()),*]
            }
        }
    };

    // to enable debug_output:
    // cargo test --config "build.rustflags = '--cfg=debug_output'"
    #[cfg(debug_output)]
    eprintln!("{}", expanded);
    expanded.into()
}

/*
Given:
#[derive(Context)]
struct MyLocationType {
    event_id: u16,
    user_id: String
}

Then:
impl ::iri_string::template::context::Context for MyLocationType {
    fn visit<V: iri_string::template::context::Visitor>(&self, visitor: V) -> V::Result {
        match visitor.var_name().as_str() {
            "event_id" => visitor.visit_string(self.event_id),
            "user_id" => visitor.visit_string(self.user_id),
            _ => visitor.visit_undefined()
        }
    }
}

XXX consider helper attrs to customize visit type
*/

#[proc_macro_derive(Context)]
pub fn context_derive(item: StdTokenStream) -> StdTokenStream {
    let (struct_name, vars, _) = parse(item);

    let expanded = quote! {
        impl ::iri_string::template::context::Context for #struct_name {
            fn visit<V: ::iri_string::template::context::Visitor>(&self, visitor: V) -> V::Result {
                match visitor.var_name().as_str() {
                    #( stringify!(#vars) => visitor.visit_string(self.#vars.clone()), )*
                    _ => visitor.visit_undefined()
                }
            }
        }
    };

    #[cfg(debug_output)]
    eprintln!("{}", expanded);
    expanded.into()
}

#[proc_macro_derive(Extract)]
pub fn extract_derive(item: StdTokenStream) -> StdTokenStream {
    let (struct_name, vars, var_types) = parse(item);

    let expanded = quote! {
        impl<'de> ::serde::Deserialize<'de> for #struct_name {
            fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
            where D: ::serde::Deserializer<'de> {
                let ( #( #vars ),* ) = <( #( #var_types ),* ) as ::serde::Deserialize>::deserialize(deserializer)?;
                Ok(Self{ #( #vars ),* })
            }
        }
    };

    #[cfg(debug_output)]
    eprintln!("{}", expanded);
    expanded.into()
}

fn parse(input: StdTokenStream) -> (Ident, Vec<Ident>, Vec<TokenTree>) {
    let proc2_item = TokenStream::from(input);
    #[cfg(debug_output)]
    eprintln!("INPUT: {:?}\n\n", proc2_item);
    let mut tok_iter = proc2_item.into_iter().peekable();
    while tok_iter.next_if(|tok| match tok {
        TokenTree::Ident(s) => s != "struct",
        _ => true
    }).is_some() {};

    let qstruct = match tok_iter.next() {
        Some(TokenTree::Ident(s)) => s,
        _ => panic!("cannot derive Listable without a struct"),
    };
    #[cfg(debug_output)]
    eprintln!("{:?}", qstruct);
    if qstruct != "struct" {
        panic!("can only derive Listable on a struct (not an enum or onion)");
    }
    let struct_name = match tok_iter.next() {
        Some(TokenTree::Ident(s)) => s,
        _ => panic!("don't know what to do with a non-ident in this position"),
    };
    let body = match tok_iter.next() {
        Some(TokenTree::Group(g)) => g,
        _ => panic!("now I'm expecting a group"),
    };
    let mut body_iter = body.stream().into_iter().peekable();
    let mut vars = vec![];
    let mut var_types = vec![];
    while let Some(tok) = body_iter.next() {
        match (tok, body_iter.peek()) {
            (TokenTree::Ident(var), Some(TokenTree::Punct(punct))) if punct.as_char() == ':' => {
                vars.push(var);
                body_iter.next(); // consume the ':'
                var_types.push(body_iter.next().expect("a single ident type after :")) // naive assumption
            },
            _ => ()
        }
    }

    #[cfg(debug_output)]
    eprintln!("STRUCT: {:?}", struct_name);
    #[cfg(debug_output)]
    eprintln!("VARS: {:?}", vars);

    (struct_name, vars, var_types)
}
