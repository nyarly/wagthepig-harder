module LinkFollowing exposing
    ( chain
    , chainFrom
    , decodeBody
    , get
    , post
    , put
    , delete
    )

{-| Functions to support following links.
These are somewhat clunkier than their `ResourceUpdate` equivalents,
and may be deprecated based on usage.

If you do find them more useful that the `ResourceUpdate` functions,
please let us know. Otherwise, consider them at hazard for being removed in 2.0.


## Browsing

@docs chain
@docs chainFrom
@docs decodeBody


## Simple requests

Rarely, you may want to make a quick GET or PUT.

@docs get
@docs post
@docs put
@docs delete

-}

import Http
import Hypermedia as HM exposing (Affordance, Method(..), Response, link)
import Json.Decode as D exposing (Decoder)
import LocalUtilities exposing (browseFrom, follow)
import Task


type alias AffordanceExtractor =
    ResponseToResult Affordance


type alias ResponseToResult a =
    Response -> Result String a


type alias BodyToRes x a =
    String -> Result x a


type alias ResToMsg x a msg =
    Result x a -> msg


{-| Pass a list of linkExtractors to nose, along with the handling for the final link.
It's start browsing at `/api` and go from there.

    HM.chain
        [ HM.browse [ "events" ] (HM.ByType "ViewAction") ]
        [ Auth.header creds ]
        Http.emptyBody
        modelRes
        handleGetResult

-}
chain : List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> ResToMsg Http.Error a msg -> Cmd msg
chain =
    chainFrom (HM.link GET "/api")


{-| Like `chain` but allows you to start from an arbitrary point
-}
chainFrom : Affordance -> List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> ResToMsg Http.Error a msg -> Cmd msg
chainFrom start extractors headers body makeRes toMsg =
    let
        plan =
            browseFrom start extractors headers body makeRes
    in
    Task.attempt toMsg plan


{-| convenience to decode the body of a HTTP response
-}
decodeBody : D.Decoder resource -> { a | body : String } -> Result String resource
decodeBody decoder res =
    res.body
        |> D.decodeString decoder
        |> Result.mapError D.errorToString


request : Method -> String -> List Http.Header -> Http.Body -> BodyToRes String a -> ResToMsg Http.Error a msg -> Cmd msg
request method url headers body makeRes toMsg =
    Task.attempt toMsg
        (follow headers body (\r -> makeRes r.body) (link method url))


jsonRequest : Method -> String -> List Http.Header -> Http.Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
jsonRequest method url headers body decoder toMsg =
    let
        toRes =
            \b -> Result.mapError D.errorToString (D.decodeString decoder b)
    in
    request method url headers body toRes toMsg


{-| convenience for a quick JSON GET request
-}
get : String -> List Http.Header -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
get url headers decoder toMsg =
    jsonRequest GET url headers Http.emptyBody decoder toMsg


{-| convenience for a quick JSON PUT request
-}
put : String -> List Http.Header -> Http.Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
put url headers body decoder toMsg =
    jsonRequest PUT url headers body decoder toMsg


{-| convenience for a quick JSON POST request
-}
post : String -> List Http.Header -> Http.Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
post url headers body decoder toMsg =
    jsonRequest POST url headers body decoder toMsg


{-| convenience for a quick JSON DELETE request
-}
delete : String -> List Http.Header -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
delete url headers decoder toMsg =
    jsonRequest DELETE url headers Http.emptyBody decoder toMsg
