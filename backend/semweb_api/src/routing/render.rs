use super::parser::{Expression, Op, Part, VarMod, VarSpec};

const EMPTY: &str      = "";
const PLUS: &str       = "+";
const EQUALS: &str     = "=";
const COMMA: &str      = ",";
const DOT: &str        = ".";
const SEMI: &str       = ";";
const AND: &str        = "&";
const QMARK: &str      = "?";
const SLASH: &str      = "/";
const OCTOTHORPE: &str = "#";

static QUERYTERM: &str = "?#";

impl Op {
    fn to_string(&self) -> &'static str {
        use Op::*;
        match self {
            Simple => EMPTY,
            Reserved => PLUS,
            Fragment => OCTOTHORPE,
            Label => DOT,
            Path => SLASH,
            PathParam => SEMI,
            Query => QMARK,
            QueryCont => AND,
        }
    }

    fn prefix(&self) -> &'static str {
        use Op::*;
        match self {
            Simple => EMPTY,
            Reserved => EMPTY,
            Fragment => OCTOTHORPE,
            Label => DOT,
            Path => SLASH,
            PathParam => SEMI,
            Query => QMARK,
            QueryCont => AND,
        }
    }

    fn separator(&self) -> &'static str {
        use Op::*;
        match self {
            Simple => COMMA,
            Reserved => COMMA,
            Fragment => COMMA,
            Label => DOT,
            Path => SLASH,
            PathParam => SEMI,
            Query => AND,
            QueryCont => AND,
        }
    }

    /*
    * Types with non-empty Joiner incorporate the variable name
    * i.e. for foo=bar
    * If there's a [] joiner: "bar"
    * If there's a "=" joiner "foo=bar"
    */

    fn joiner(&self) -> &'static str {
        use Op::*;
        match self {
            Simple => EMPTY,
            Reserved => EMPTY,
            Fragment => EMPTY,
            Label => EMPTY,
            Path => EMPTY,
            PathParam => EQUALS,
            Query => EQUALS,
            QueryCont => EQUALS,
        }
    }
}

pub(super) fn re_names(part: &Part) -> Vec<String> {
    match part {
        Part::Lit(_) => vec![],
        Part::Expression(exp) |
        Part::SegPathVar(exp) |
        Part::SegPathRest(exp) |
        Part::SegVar(exp) |
        Part::SegRest(exp) => exp_re_names(exp)
    }
}

pub(super) fn auth_re_string(part: &Part) -> String {
    match part {
        Part::Lit(s) => s.clone(),
        Part::Expression(exp) |
        Part::SegPathVar(exp) |
        Part::SegPathRest(exp) |
        Part::SegVar(exp) |
        Part::SegRest(exp) => exp_re(exp, EMPTY, SLASH)
    }
}

pub(super) fn path_re_string(part: &Part) -> String {
    match part {
        Part::Lit(s) => s.clone(),
        Part::Expression(exp) |
        Part::SegPathVar(exp) |
        Part::SegPathRest(exp) => exp_re(exp, SLASH, QUERYTERM),
        Part::SegVar(exp) |
        Part::SegRest(exp) => format!("/{}", exp_re(exp, SLASH, QUERYTERM))
    }
}


fn exp_re(exp: &Expression, here: &'static str, nxt: &'static str) -> String {
    let mut re = exp.operator.prefix().to_string();
    re.push_str(
        &exp.varspecs.iter()
            .map(var_re(exp.operator, here, nxt))
            .collect::<Vec<_>>()
            .join(&exp.operator.separator()));
    re
}

fn exp_re_names(exp: &Expression) -> Vec<String> {
    exp.varspecs.iter()
        .map(|varspec| {
            let var = &varspec.varname;
            match varspec.modifier {
                VarMod::Prefix(count) => format!("{var}_p{count}"),
                _ => var.clone()
            }
        }).collect()
}

fn var_re(op: Op, here: &'static str, nxt: &'static str) -> impl Fn(&VarSpec) -> String {
    move |varspec| {
        let var = &varspec.varname;
        let sep = op.separator();
        let join = op.joiner();
        match (op, varspec.modifier) {
            // Query and QueryCont would also need "varname=" but! not allowed in the path
            (Op::PathParam, VarMod::None) =>
            format!("(?<{var}>{var}{join}[^{here}{nxt}{sep}]*)"),

            (Op::PathParam, VarMod::Prefix(count)) =>
            format!("(?<{var}_p{count}>{var}{join}(?:[^{here}{nxt}%{sep}]|%[A-Fa-f0-9]{{2}}|%%){{0,{count}}})"),

            (_, VarMod::None) =>
            format!("(?<{var}>[^{here}{nxt}{sep}]*)"),

            (_, VarMod::Prefix(count)) =>
            format!("(?<{var}_p{count}>(?:[^{here}{nxt}%{sep}]|%[A-Fa-f0-9]{{2}}|%%){{0,{count}}})"),

            (_, VarMod::Explode) =>
            format!("(?<{var}>[^{nxt}]*)"),
        }
    }
}

pub(super) fn original_string(part: &Part) -> String {
    match part {
        Part::Lit(s) => s.clone(),
        Part::Expression(exp) |
        Part::SegPathVar(exp) |
        Part::SegPathRest(exp) => exp_string(exp),
        Part::SegVar(exp) |
        Part::SegRest(exp) => format!("/{}", exp_string(exp))
    }
}

fn exp_string(exp: &Expression) -> String {
    format!("{{{}{}}}",
        exp.operator.to_string(),
        exp.varspecs.iter().map(varspec_string).collect::<Vec<_>>().join(",")
    )
}

fn varspec_string(varspec: &VarSpec) -> String {
    match varspec.modifier {
        VarMod::Prefix(count) => format!("{}:{}", varspec.varname, count),
        VarMod::Explode => format!("{}*", varspec.varname),
        VarMod::None => varspec.varname.clone(),
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
pub(super) fn axum7_vars(vars: &[VarSpec]) -> String {
    format!("/:{}", vars.iter().cloned().map(|var| var.varname).collect::<Vec<_>>().join(""))
}

pub(super) fn axum7_rest(vars: &[VarSpec]) -> String {
    format!("/*{}", vars.iter().cloned().map(|var| var.varname).collect::<Vec<_>>().join(""))
}
