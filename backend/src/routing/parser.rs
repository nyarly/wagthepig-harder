use nom::{
    branch::alt,
    bytes::complete::tag,
    character::complete::{self as character, char, one_of, satisfy},
    combinator::{all_consuming, map, map_opt, map_parser, opt, recognize, value},
    multi::{fold_many_m_n, many0, many0_count, many1, many1_count, separated_list1},
    sequence::{delimited, pair, preceded, separated_pair, tuple},
    IResult,
};


/* We're parsing a terrible hybrid of
* RFC 3986 (just paths)
* RFC 6570 (URITemplates +)
* matchit
*
(ideally with slices in the String...)
we want:
the matchit route, in alternating (lit|capture)* list
the URITemplate variables

from which we will be able to build
* A URITemplate for clients to fill
* Filled URIs (by filling variables)
* Checked Filled URIs (by requiring all variables have an assignment) [need varlist]
* Strict URIs (by further requiring that no other variables are supplied [need varlist]
* matchit routes for Axum (v0.7 or v0.8) [need path, some var structure]
* regexp to extract path variables as matchit would from a URI [idem]

lists of variables -> matchit captures?
sort, concatenate; error on collision
{?foo,bar} -> `?((foo=(?foo:[^&]*)|bar=(?bar:[^&]*))&)*`
/{;foo,bar}/ -> /:barfoo/ and `/(?barfoo:[^/]*)/`
/{foo,bar}/{barfoo} -> Err(VariableCollision)
all of the above pull 'foo' and 'bar' as variable names


{/foo,bar} -> /:foo/:bar
{/var:1,var} -> /:varp1/:var (matchit oblivious to relationship)
{/var:1,var} -> `/[^/]* /(?var:[^/]*)`  (note space for comment continuation)
  (we can't match by bytes (or even Unicode characters) because prefix counts percent-encoding)
  (IOW, if var:= %20%20something, the above would fill as /%20%20/%20%20something
/{var:1}/{var}

{/list*} -> at end-of-path: /:*list


Non-features: (or v2)
extracting variables outside of the path
if you need that,
parse the URL to get query, fragment, host
*
//
//
//
//
Not supported
/ path-rootless   ; begins with a segment
/ path-noscheme   ; begins with a non-colon segment
path-rootless = segment-nz *( "/" segment )

*/

pub(super) type NomError<'a> = nom::error::Error<&'a str>;

type NomResult<'a, T> = IResult<&'a str, T, NomError<'a>>;

#[derive(Debug, PartialEq, Default, Clone)]
pub(super) struct Parsed {
    pub(super) auth: Option<Vec<Part>>,
    pub(super) path: Vec<Part>,
    pub(super) query: Option<Vec<Part>>,
}

#[derive(Debug, PartialEq, Clone)]
pub(super) struct Expression {
    pub(super) operator: Op,
    pub(super) varspecs: Vec<VarSpec>
}

impl Expression {
    fn from_pair((optchar, varspecs): (Option<char>, Vec<VarSpec>)) -> Expression {
        Expression {
            operator: Op::from_optchar(optchar),
            varspecs
        }
    }
}


/* per RFC 6570 (for explode...)
* Types with non-empty Joiner incorporate the variable name
* i.e. for foo=bar
* If there's a [] joiner: "bar"
* If there's a "*" joiner "foo*bar"
Name      Type Prefix Separator Joiner
Simple    []   []     ","       []     (default)
Reserved  +    []     ","       []
Fragment  #    "#"    ","       []
Label     .    "."    "."       []
Path      /    "/"    "/"       []
PathParam ;    ";"    ";"       "="
Query     ?    "?"    "&"       "="
QueryCont &    "&"    "&"       "="
*/
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum Op {
    Simple,
    Reserved,
    Fragment,
    Label,
    Path,
    PathParam,
    Query,
    QueryCont,
}

impl Op {
    fn from_optchar(ch: Option<char>) -> Op {
        use Op::*;
        match ch {
            None => Simple,
            Some('+') => Reserved,
            Some('#') => Fragment,
            Some('.') => Label,
            Some('/') => Path,
            Some(';') => PathParam,
            Some('?') => Query,
            Some('&') => QueryCont,
            _ => panic!("parsed {:?} as expression operator", ch)
        }
    }
}

#[derive(Debug, PartialEq, Clone)]
pub(super) enum Part {
    Lit(String),
    Expression(Expression),
    SegVar(Expression),
    SegPathVar(Expression),
    SegRest(Expression),
    SegPathRest(Expression),
}

impl Default for Part {
    fn default() -> Self {
        Part::Lit("".to_string())
    }
}

impl Part {
    fn to_lit(s: &str) -> Self {
        Part::Lit(s.to_owned())
    }
}


#[derive(Debug, PartialEq, Clone)]
pub(super) struct VarSpec{
    pub(super) varname: String,
    pub(super) modifier: VarMod
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum VarMod {
    Prefix(u16),
    Explode,
    None
}


pub(super) fn parse(base: &str) -> Result<Parsed, nom::Err<NomError<'_>>> {
    let (_, (auth, path, query)) = route_template(base)?;
    Ok(Parsed{auth, path, query})
}

// route-template = [authority-part] path [query_part]
#[allow(clippy::type_complexity)]
fn route_template(i: &str) -> NomResult<(Option<Vec<Part>>, Vec<Part>, Option<Vec<Part>>)> {
    all_consuming(tuple((
        opt(authority_part),
        path,
        opt(query_part)
    )))(i)
}
//
//
// XXX consider adding alternative of auth-lit? (auth-exp auth-lit)?
// XXX iow: 0 or 1 expressions if there are no //.
// authority-part = *( authority-literals / expression ) '//' authority
fn authority_part(i: &str) -> NomResult<Vec<Part>> {
    map(
        separated_pair(
            many0(alt((authority_literals, expression))),
            tag("//"),
            authority
        ),
        |(mut pre, mut authority)| {
            pre.push(Part::to_lit("//"));
            pre.append(&mut authority);
            pre
        }
    )(i)
}

// path         = 1*segment [tail-segment]
fn path(i: &str) -> NomResult<Vec<Part>> {
    alt((
        map(
            pair(many1(segment),opt(tail_segment)),
            |(mut segs, maybe_tail)| match maybe_tail {
                Some(seg) => {segs.push(seg); segs}
                None => segs
            }
        ),
        value(vec![Part::to_lit("/")], tag("/"))
    ))(i)
}

// query_part =  '?'/'#' *(authority-literals / expression)
fn query_part(i: &str) -> NomResult<Vec<Part>> {
    many1(alt((authority_literals, authority_expression)))(i)
}

// authority = *(authority-literals / authority-expression )
fn authority(i: &str) -> NomResult<Vec<Part>> {
    many0(alt((authority_literals, authority_expression)))(i)
}

// segment = segment-literal / segment-variable / segment-pathvar
fn segment(i: &str) -> NomResult<Part> {
    alt((segment_variable, segment_pathvar, segment_literal))(i)
}

// tail-segment = segment-rest / segment-pathrest
fn tail_segment(i: &str) -> NomResult<Part> {
    alt((segment_rest, segment_pathrest))(i)
}

// segment-literal = "/" *pchar
fn segment_literal(i: &str) -> NomResult<Part> {
    map(
        recognize(preceded(char('/'), many1_count(pchar))), // test "/" path
        Part::to_lit
    )(i)
}

// literals      =  %x21 / %x23-24 / %x26 / %x28-3B / %x3D / %x3F-5B
// /  %x5D / %x5F / %x61-7A / %x7E / ucschar / iprivate
// /  pct-encoded
// authority-literals = literals - "/"
fn authority_literals(i: &str) -> NomResult<Part> {
    map(
        recognize(many1_count(
            alt((satisfy(|ch| matches!(ch,
                '\u{21}' | '\u{23}'..='\u{24}' | '\u{26}' |
                '\u{28}'..='\u{2e}' | '\u{30}'..='\u{3B}' | // not \u{2f} = '/'
                '\u{3D}' | '\u{3F}'..='\u{5B}' | '\u{5D}' | '\u{5F}' | '\u{61}'..='\u{7A}' | '\u{7E}')),
                ucschar, iprivate, pct_encoded))
        )),
        Part::to_lit
    )(i)
}


// segment-variable = "/{" [ "+" ] segment-variable-list "}"
fn segment_variable(i: &str) -> NomResult<Part> {
    map( map(
        delimited(tag("/{"), pair(opt(char('+')), segment_var_list), tag("}")),
        Expression::from_pair
    ), Part::SegVar)(i)
}

// segment-pathvar = "{/" segment-variable-list "}"
fn segment_pathvar(i: &str) -> NomResult<Part> {
    map( map(
        delimited(tag("{"), pair(opt(char('/')), segment_var_list), tag("}")),
        Expression::from_pair
    ), Part::SegPathVar)(i)
}

// segment-rest = "/{" [ operator ] variable-list "}"
fn segment_rest(i: &str) -> NomResult<Part> {
    map( map(
        delimited(tag("/{"), pair(opt(tail_operator), variable_list), tag("}")),
        Expression::from_pair
    ), Part::SegRest)(i)
}

// segment-pathrest = "{/" variable-list "}"
fn segment_pathrest(i: &str) -> NomResult<Part> {
    map(map(
        delimited(tag("{"), pair(opt(char('/')), variable_list), tag("}")),
        Expression::from_pair
    ), Part::SegPathRest)(i)
}

// segment-var-list =  varspec *( "," varspec )
fn segment_var_list(i: &str) -> NomResult<Vec<VarSpec>> {
    separated_list1(char(','), segment_varspec)(i)
}

// segment-varspec       =  varname [ prefix ]
fn segment_varspec(i: &str) -> NomResult<VarSpec> {
    map(
        pair(
            varname,
            map(
                opt( mod_prefix,),
                |maybe| maybe.unwrap_or(VarMod::None)
            )),
        |(varname, modifier)| VarSpec{ varname: varname.to_owned(), modifier }
    )(i)
}

//expression    =  "{" [ operator ] variable-list "}"
fn expression(i: &str) -> NomResult<Part> {
    map(map(
        delimited(tag("{"), pair(opt(operator), variable_list), tag("}")),
        Expression::from_pair
    ), Part::Expression)(i)
}

// authority-expresion = expression - "/"
fn authority_expression(i: &str) -> NomResult<Part> {
    map(map(
        delimited(tag("{"), pair(opt(authority_operator), variable_list), tag("}")),
        Expression::from_pair
    ), Part::Expression)(i)
}

// variable-list =  varspec *( "," varspec )
fn variable_list(i: &str) -> NomResult<Vec<VarSpec>> {
    separated_list1(char(','), varspec)(i)
}

// varspec       =  varname [ modifier-level4 ]
// modifier-level4 =  prefix / explode
fn varspec(i: &str) -> NomResult<VarSpec> {
    map(
        pair(
            varname,
            map(
                opt(alt((
                    mod_prefix,
                    mod_explode
                ))),
                |maybe| maybe.unwrap_or(VarMod::None)
            )),
        |(varname, modifier)| VarSpec{ varname: varname.to_owned(), modifier }
    )(i)
}

// varname       =  varchar *( ["."] varchar )
fn varname(i: &str) -> NomResult<&str> {
    recognize(pair(many1_count(varchar), many0_count(alt((varchar, char('.'))))))(i)
}

// prefix        =  ":" max-length
// max-length    =  %x31-39 0*3DIGIT   ; positive integer < 10000
fn mod_prefix(i: &str) -> NomResult<VarMod> {
    preceded(
        char(':'),
        map(
            map_parser(
                recognize(pair(one_of("123456789"), fold_many_m_n(0, 3, digit, || 0, |_,_| 0))),
                character::u16
            ),
            VarMod::Prefix
        )
    )(i)
}

// explode       =  "*"
fn mod_explode(i: &str) -> NomResult<VarMod> {
    value(VarMod::Explode, char('*'))(i)
}

// operator      =  op-level2 / op-level3 / op-reserve
// op-level2     =  "+" / "#"
// op-level3     =  "." / ";" / "?" / "&" / "/"
// op-reserve    =  "=" / "," / "!" / "@" / "|"
fn operator(i: &str) -> NomResult<char> {
    one_of("+.;&=,!@|/#?")(i)
}

// tail_operator = operator - ?#/, used in "rest" path matches
//
fn tail_operator(i: &str) -> NomResult<char> {
    one_of("+.;&=,!@|")(i)
}

// authority_operator = operator - /, used in the "authority" part
//
fn authority_operator(i: &str) -> NomResult<char> {
    one_of("+.;&=,!@|#?")(i)
}

// pchar = unreserved / pct-encoded / sub-delims / ":" / "@"
fn pchar(i: &str) -> NomResult<char> {
    alt((unreserved, pct_encoded, sub_delims, one_of(":@")))(i)
}

//
// unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
fn unreserved(i: &str) -> NomResult<char> {
    alt((alphanumeric, one_of("-._~")))(i)
}
// sub-delims    = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
fn sub_delims(i: &str) -> NomResult<char> {
    one_of("!$&'()*+,;=")(i)
}

// varchar       =  ALPHA / DIGIT / "_" / pct-encoded
fn varchar(i: &str) -> NomResult<char> {
    alt((alpha, digit, char('_'), pct_encoded))(i)
}

fn alphanumeric( i: &str) -> NomResult<char> {
    alt((alpha, digit))(i)
}

fn alpha(i: &str) -> NomResult<char> {
    one_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")(i)
}

fn digit(i: &str) -> NomResult<char> {
    one_of("0123456789")(i)
}

fn hexdig(i: &str) -> NomResult<char> {
    one_of("0123456789ABCDEFabcdef")(i)
}

//pct-encoded   = "%" HEXDIG HEXDIG
fn pct_encoded(i: &str) -> NomResult<char> {
    preceded(
        char('%'),
        map_opt(
            map_parser(
                recognize(pair(hexdig, hexdig)),
                hex_u32
            ),
            core::char::from_u32
        )
    )(i)
}

// reformatted for comparison
// ucschar        =
//           %xA0-D7FF     /             %xF900-FDCF
// /         %xFDF0-FFEF   /           %x10000-1FFFD
// /         %x20000-2FFFD /           %x30000-3FFFD
// /         %x40000-4FFFD /           %x50000-5FFFD
// /         %x60000-6FFFD /           %x70000-7FFFD
// /         %x80000-8FFFD /           %x90000-9FFFD
// /         %xA0000-AFFFD /           %xB0000-BFFFD
// /         %xC0000-CFFFD /           %xD0000-DFFFD
// /         %xE1000-EFFFD
fn ucschar(i: &str) -> NomResult<char> {
    satisfy(|ch| matches!(ch,
             '\u{A0}'..='\u{D7FF}' | '\u{F900}'..='\u{FDCF}'
        |  '\u{FDF0}'..='\u{FFEF}' |'\u{10000}'..='\u{1FFFD}'
        |'\u{20000}'..='\u{2FFFD}' |'\u{30000}'..='\u{3FFFD}'
        |'\u{40000}'..='\u{4FFFD}' |'\u{50000}'..='\u{5FFFD}'
        |'\u{60000}'..='\u{6FFFD}' |'\u{70000}'..='\u{7FFFD}'
        |'\u{80000}'..='\u{8FFFD}' |'\u{90000}'..='\u{9FFFD}'
        |'\u{A0000}'..='\u{AFFFD}' |'\u{B0000}'..='\u{BFFFD}'
        |'\u{C0000}'..='\u{CFFFD}' |'\u{D0000}'..='\u{DFFFD}'
        |'\u{E1000}'..='\u{EFFFD}'
    ))(i)
}

// iprivate       =  %xE000-F8FF / %xF0000-FFFFD / %x100000-10FFFD
fn iprivate(i: &str) -> NomResult<char> {
    satisfy(|ch| matches!(ch,
        '\u{E000}'..='\u{F8FF}' | '\u{F0000}'..='\u{FFFFD}' | '\u{100000}'..='\u{10FFFD}'
    ))(i)
}



use nomnumber::hex_u32;
// lifted from nom-future
mod nomnumber {
    use std::ops::{RangeFrom, RangeTo};

    use nom::{error::{ErrorKind, ParseError}, AsBytes, AsChar, IResult, InputLength, InputTakeAtPosition, Slice};


    #[inline]
    pub(super) fn hex_u32<I, E: ParseError<I>>(input: I) -> IResult<I, u32, E>
where
        I: InputTakeAtPosition,
        I: Slice<RangeFrom<usize>> + Slice<RangeTo<usize>>,
        <I as InputTakeAtPosition>::Item: AsChar,
        I: AsBytes,
        I: InputLength,
    {
        let e: ErrorKind = ErrorKind::IsA;
        let (i, o) = input.split_at_position1_complete(
            |c| {
                let c = c.as_char();
                !"0123456789abcdefABCDEF".contains(c)
            },
            e,
        )?;

        // Do not parse more than 8 characters for a u32
        let (parsed, remaining) = if o.input_len() <= 8 {
            (o, i)
        } else {
            (input.slice(..8), input.slice(8..))
        };

        let res = parsed
            .as_bytes()
            .iter()
            .rev()
            .enumerate()
            .map(|(k, &v)| {
                let digit = v as char;
                digit.to_digit(16).unwrap_or(0) << (k * 4)
            })
            .sum();

        Ok((remaining, res))
    }

}


#[cfg(test)]
mod test {
    use nom::error::ErrorKind;

    use super::*;

    #[test]
    fn test_parse() {
        let input = "http://example.com/user/{user_id}{?something,mysterious}";
        assert_eq!(parse(input), Ok(Parsed{
            auth: Some(vec![
                Part::Lit("http:".to_string()),
                Part::Lit("//".to_string()),
                Part::Lit("example.com".to_string())
            ]),
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegVar(Expression{
                    operator: Op::Simple,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
                    ]})
            ],
            query: Some(vec![
                Part::Expression(Expression{
                    operator: Op::Query,
                    varspecs: vec![
                        VarSpec { varname: "something".to_string(), modifier: VarMod::None },
                        VarSpec { varname: "mysterious".to_string(), modifier: VarMod::None }
                    ]})
            ]),
        }));
        let input = "/user/{user_id}{?something,mysterious}";
        assert_eq!(parse(input), Ok(Parsed{
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegVar(Expression{
                    operator: Op::Simple,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
                    ]})
            ],
            query: Some(vec![
                Part::Expression(Expression{
                    operator: Op::Query,
                    varspecs: vec![
                        VarSpec { varname: "something".to_string(), modifier: VarMod::None },
                        VarSpec { varname: "mysterious".to_string(), modifier: VarMod::None }
                    ]})
            ]),
           ..Parsed::default()
        }));
        assert_eq!(parse("/user/{user_id}?something=good{&mysterious}"), Ok(Parsed{
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegVar(Expression{
                    operator: Op::Simple,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
                    ]})
            ],
            query: Some(vec![
                Part::Lit("?something=good".to_string()),
                Part::Expression(Expression{
                    operator: Op::QueryCont,
                    varspecs: vec![
                        VarSpec { varname: "mysterious".to_string(), modifier: VarMod::None }
                    ]})
            ]),
           ..Parsed::default()
        }));
        let input = "/user/{user_id,user_name}";
        assert_eq!(parse(input), Ok(Parsed{
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegVar(Expression{
                    operator: Op::Simple,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::None},
                        VarSpec{varname: "user_name".to_string(), modifier: VarMod::None}
                    ]})
            ],
           ..Parsed::default()
        }));
        let input = "/user{/user_id,user_name}";
        assert_eq!(parse(input), Ok(Parsed{
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegPathVar(Expression{
                    operator: Op::Path,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::None},
                        VarSpec{varname: "user_name".to_string(), modifier: VarMod::None}
                    ]})
            ],
           ..Parsed::default()
        }));
        let input = "/user{/user_id}";
        assert_eq!(parse(input), Ok(Parsed{
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegPathVar(Expression{
                    operator: Op::Path,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
                    ]})
            ],
           ..Parsed::default()
        }));
        let input = "/user/{user_id*}";
        assert_eq!(parse(input), Ok(Parsed{
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegRest(Expression{
                    operator: Op::Simple,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::Explode}
                    ]})
            ],
           ..Parsed::default()
        }));
        let input = "/user{/user_id*}";
        assert_eq!(parse(input), Ok(Parsed{
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegPathRest(Expression{
                    operator: Op::Path,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::Explode}
                    ]})
            ],
           ..Parsed::default()
        }));
        let input = "/user/{user_id}";
        assert_eq!(parse(input), Ok(Parsed{
            path: vec![
                Part::Lit("/user".to_string()),
                Part::SegVar(Expression{
                    operator: Op::Simple,
                    varspecs: vec![
                        VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
                    ]})
            ],
           ..Parsed::default()
        }));
        let input = "/";
        assert_eq!(parse(input), Ok(Parsed{
            path: vec![
                Part::Lit("/".to_string()),
            ],
           ..Parsed::default()
        }));
    }

    #[test]
    fn test_path() {
        assert_eq!(
            path("/user/{user_id}"),
            Ok(("", vec![
                Part::Lit("/user".to_string()),
                Part::SegVar(Expression{
                    operator: Op::Simple,
                    varspecs: vec![
                    VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
                ]})
            ]))
        )
    }

    #[test]
    fn test_segment() {
        assert_eq!(
            segment("/user"),
            Ok(("",
                Part::Lit("/user".to_string()),
            ))
        );
        assert_eq!(
            segment("/{user_id}"),
            Ok(("", Part::SegVar(Expression{
                operator: Op::Simple,
                varspecs: vec![
                VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
            ]})))
        )
    }

    #[test]
    fn test_segment_variable() {
        assert_eq!(segment_variable("/{user_id}"),
            Ok(("", Part::SegVar(Expression{
                operator: Op::Simple,
                varspecs: vec![
                    VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
                ]})
            ))
        )
    }

    #[test]
    fn test_segment_varspec() {
        assert_eq!(segment_varspec("user_id"),
            Ok(("",
                VarSpec{varname: "user_id".to_string(), modifier: VarMod::None}
            ))
        )
    }

    #[test]
    fn test_prefix() {
        assert_eq!(Ok(("", VarMod::Prefix(17))), mod_prefix(":17"));
        assert_eq!(Ok(("", VarMod::Prefix(1))), mod_prefix(":1"))
    }

    #[test]
    fn test_pct_encoded() {
        assert_eq!(
            pct_encoded("%30*"),
            Ok(("*", '0'))
        );
        assert_eq!(
            pct_encoded("%41g"),
            Ok(("g", 'A'))
        );
        assert_eq!(
            pct_encoded("41"),
            Err(nom::Err::Error(nom::error::Error { input: "41", code: ErrorKind::Char }))
        );
        assert_eq!(
            pct_encoded("%4"),
            Err(nom::Err::Error(nom::error::Error { input: "", code: ErrorKind::OneOf }))
        );
    }
}
