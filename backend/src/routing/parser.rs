use axum::response::IntoResponse;

/*
(ideally with slices in the String...)
we want:
the matchit route, in alternating (lit|capture)* list
the URITemplate variables

from which we will be able to build
A URITemplate for clients to fill
Filled URIs (by filling variables)
Checked Filled URIs (by requiring all variables have an assignment)
Strict URIs (by further requiring that no other variables are supplied
matchit routes for Axum (v0.7 or v0.8)
regexp to extract path variables as matchit would from a URI

lists of variables -> matchit captures?
sort, concatenate; error on collision
{?foo,bar} -> `?((foo=(?foo:[^&]*)|bar=(?bar:[^&]*))&)*`
/{;foo,bar}/ -> /:barfoo/ and `/(?barfoo:[^/]*)/`
/{foo,bar}/{barfoo} -> Err(VariableCollision)
all of the above pull 'foo' and 'bar' as variable names


{/foo,bar} -> /:foo/:bar
{/var:1,var} -> /:varp1/:var (matchit oblivious to relationship)
{/var:1,var} -> `/./(?var:[^/]*)`
/{var:1}/{var}

{/list*} -> at end-of-path: /:*list


Non-features: (or v2)
extracting variables outside of the path
if you need that,
parse the URL to get query, fragment, host
*/
struct Parsed {
    base: String
}

#[derive(thiserror::Error, Debug)]
pub enum Error {
}

impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        (hyper::StatusCode::INTERNAL_SERVER_ERROR, self.to_string()).into_response()
    }
}

/*
* (assume URITemplate ABNF) adding:
*
    route-template = [*( literals / expression ) '//' authority ] path [ '?'/'#' *(literals / expression) ]

    authority = *(authority-literals / expression )
    authority-literals = literals - "/"

    path         = *segment [tail-segment]

    segment = segment-literal / segment-variable / segment-pathvar
    tail-segment = segment-rest / segment-pathrest

    segment-literal = "/" *pchar
    segment-variable = "/{" [ "+" ] segment-variable-list "}"
    segment-pathvar = "{/" segment-variable-list "}"

    pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"

    segment-rest = "/{" [ operator ] variable-list "}"
    segment-pathrest = "{/" variable-list "}"

    operator      =  op-level2 / op-level3 / op-reserve
    op-level2     =  "+" / "#"
    op-level3     =  "." / ";" / "?" / "&" ; removing "/"
    op-reserve    =  "=" / "," / "!" / "@" / "|"

    segment-var-list =  varspec *( "," varspec )
    segment-varspec       =  varname [ prefix ]

    variable-list =  varspec *( "," varspec )
    varspec       =  varname [ modifier-level4 ]

    varname       =  varchar *( ["."] varchar )
    varchar       =  ALPHA / DIGIT / "_" / pct-encoded


    modifier-level4 =  prefix / explode

    prefix        =  ":" max-length
    max-length    =  %x31-39 0*3DIGIT   ; positive integer < 10000
    explode       =  "*"


    pct-encoded   = "%" HEXDIG HEXDIG

    unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
    reserved      = gen-delims / sub-delims
    gen-delims    = ":" / "/" / "?" / "#" / "[" / "]" / "@"
    sub-delims    = "!" / "$" / "&" / "'" / "(" / ")"
         / "*" / "+" / "," / ";" / "="

***

Not supported
                 / path-rootless   ; begins with a segment
                 / path-noscheme   ; begins with a non-colon segment
    path-rootless = segment-nz *( "/" segment )


*/
pub(super) fn parse(route_template: String) -> Result<Parsed, Error> {

    Ok(Parsed{base: route_template})
}


/* We're parsing a terrible hybrid of
* RFC 3986 (just paths)
* RFC 6570 (URITemplates +)
* matchit
*/


/*
RFC 3986
Extract from Appendix A.  Collected ABNF for URI

   absolute-URI  = scheme ":" hier-part [ "?" query ]

   URI-reference = URI / relative-ref

   URI           = scheme ":" hier-part [ "?" query ] [ "#" fragment ]

   relative-ref  = relative-part [ "?" query ] [ "#" fragment ]

   hier-part     = "//" authority path-abempty
                 / path-absolute
                 / path-rootless
                 / path-empty


   relative-part = "//" authority path-abempty
                 / path-absolute
                 / path-noscheme
                 / path-empty

   scheme        = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )

   authority = DONTCARE

   path          = path-abempty    ; begins with "/" or is empty
                 / path-absolute   ; begins with "/" but not "//"
                 / path-noscheme   ; begins with a non-colon segment
                 / path-rootless   ; begins with a segment
                 / path-empty      ; zero characters

   path-abempty  = *( "/" segment )
   path-absolute = "/" [ segment-nz *( "/" segment ) ]
   path-noscheme = segment-nz-nc *( "/" segment )
   path-rootless = segment-nz *( "/" segment )
   path-empty    = 0<pchar>

   segment       = *pchar
   segment-nz    = 1*pchar
   segment-nz-nc = 1*( unreserved / pct-encoded / sub-delims / "@" )
                 ; non-zero-length segment without any colon ":"

   pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"

   query         = DONTCARE

   fragment      = DONTCARE

   pct-encoded   = "%" HEXDIG HEXDIG

   unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
   reserved      = gen-delims / sub-delims
   gen-delims    = ":" / "/" / "?" / "#" / "[" / "]" / "@"
   sub-delims    = "!" / "$" / "&" / "'" / "(" / ")"
                 / "*" / "+" / "," / ";" / "="
*
*/

/*
RFC 6570
     URI-Template  = *( literals / expression )
     literals      =  %x21 / %x23-24 / %x26 / %x28-3B / %x3D / %x3F-5B
                   /  %x5D / %x5F / %x61-7A / %x7E / ucschar / iprivate
                   /  pct-encoded
                        ; any Unicode character except: CTL, SP,
                        ;  DQUOTE, "'", "%" (aside from pct-encoded),
                        ;  "<", ">", "\", "^", "`", "{", "|", "}"
     expression    =  "{" [ operator ] variable-list "}"
     operator      =  op-level2 / op-level3 / op-reserve
     op-level2     =  "+" / "#"
     op-level3     =  "." / "/" / ";" / "?" / "&"
     op-reserve    =  "=" / "," / "!" / "@" / "|"

     variable-list =  varspec *( "," varspec )
     varspec       =  varname [ modifier-level4 ]
     varname       =  varchar *( ["."] varchar )
     varchar       =  ALPHA / DIGIT / "_" / pct-encoded


     modifier-level4 =  prefix / explode

     prefix        =  ":" max-length
     max-length    =  %x31-39 0*3DIGIT   ; positive integer < 10000

     explode       =  "*"

     ALPHA          =  %x41-5A / %x61-7A   ; A-Z / a-z
     DIGIT          =  %x30-39             ; 0-9
     HEXDIG         =  DIGIT / "A" / "B" / "C" / "D" / "E" / "F"
                       ; case-insensitive

     pct-encoded    =  "%" HEXDIG HEXDIG
     unreserved     =  ALPHA / DIGIT / "-" / "." / "_" / "~"
     reserved       =  gen-delims / sub-delims
     gen-delims     =  ":" / "/" / "?" / "#" / "[" / "]" / "@"
     sub-delims     =  "!" / "$" / "&" / "'" / "(" / ")"
                    /  "*" / "+" / "," / ";" / "="

     ucschar        =  %xA0-D7FF / %xF900-FDCF / %xFDF0-FFEF
                    /  %x10000-1FFFD / %x20000-2FFFD / %x30000-3FFFD
                    /  %x40000-4FFFD / %x50000-5FFFD / %x60000-6FFFD
                    /  %x70000-7FFFD / %x80000-8FFFD / %x90000-9FFFD
                    /  %xA0000-AFFFD / %xB0000-BFFFD / %xC0000-CFFFD
                    /  %xD0000-DFFFD / %xE1000-EFFFD

     iprivate       =  %xE000-F8FF / %xF0000-FFFFD / %x100000-10FFFD


*/
