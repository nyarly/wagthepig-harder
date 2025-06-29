module Hypermedia exposing
    ( Method(..)
    , Uri
    , Headers
    , Body
    , Status
    , Response
    , Kind
    , Affordance
    , OperationSelector(..)
    , affordanceListDecoder
    , selectAffordance
    , link
    , browse
    , browseFrom
    , chain
    , chainFrom
    , decodeBody
    , TemplateVars
    , fill
    , fillIn
    , get
    , post
    , put
    , delete
    , Error
    , decodeMaybe
    , encodeMaybe
    , emptyBody
    , emptyResponse
    -- re-exports so that consumers don't always have to bring in Http
    )

{-| Definitations to support RESTful Hydra JSON-LD interfaces.

Key to the Hypermedia style is the ability to attach "affordances" to a resource -
in essence to be able to put links and forms and buttons in the respresentation of
a resources that let the user know what kinds of things they can do with it.
In JSON-LD with Hydra (and Schema.org Actions), affordances are attached to
Resources via an operation(s) property.


# REST primitives

@docs Method
@docs Uri
@docs Headers
@docs Body
@docs Status
@docs Response


# Affordance Based Browsing


## Affordances

An affordance is essentially a URI/Method pair -
it's what let's you know that there's an interface you can interact with.
We also sometimes mark them with a JSON-LD @type attribute,
which gives some information about what to expect from the interface.

@docs Kind
@docs Affordance
@docs OperationSelector
@docs affordanceListDecoder
@docs selectAffordance
@docs link


## Browsing

@docs browse
@docs browseFrom
@docs chain
@docs chainFrom
@docs decodeBody


## URI Templates

Because not every Resource can be known an enumerated ahead of time,
some Affordances present a URI template.
The classic case is being able to
search for arbitrary terms with a "?q=term" URL parameter.

@docs TemplateVars
@docs fill
@docs fillIn


## Simple requests

Rarely, you may want to make a quick GET or PUT.

@docs get
@docs post
@docs put
@docs delete


# Conveniences and Utilities

Types re-exported from this module so that consumers can avoid importing Http directly

@docs Error
@docs decodeMaybe
@docs encodeMaybe
@docs emptyBody
@docs emptyResponse

-}

-- Not sure about these anymore

import Dict exposing (Dict)
import Http exposing (Resolver)
import Json.Decode as D exposing (Decoder, decodeString)
import Json.Decode.Pipeline as DP
import Json.Encode as E
import Task exposing (Task, andThen)
import Url.Interpolate


{-| convienence for generating empty HTTP bodies
-}
emptyBody : Http.Body
emptyBody =
    Http.emptyBody


{-| convenience for accepting empty HTTP bodies in a response
-}
emptyResponse : Response -> Result String ()
emptyResponse rx =
    if rx.status >= 200 && rx.status < 300 then
        Ok ()

    else
        Err rx.body


{-| convenience re-export of Http.Error
-}
type alias Error =
    Http.Error



-- HTTP


{-| An Affordance is the intersection of method, URI and JSON-LD @type
-}
type alias Affordance =
    { method : Method
    , uri : Uri
    , kind : Maybe Kind -- JSON-LD @type
    }


{-| convenience to wrap a Method/Uri pair in an Affordance
-}
link : Method -> Uri -> Affordance
link method uri =
    Affordance method uri Nothing


{-| HTTP request method. Currently only the basic 4 HTTP methods are represented.
-}
type Method
    = GET
    | POST
    | DELETE
    | PUT


{-| The binding of a Method and a Kind
-}
type alias Operation =
    { method : Method
    , kind : Maybe Kind
    }


methodName : Method -> String
methodName method =
    case method of
        GET ->
            "GET"

        POST ->
            "POST"

        DELETE ->
            "DELETE"

        PUT ->
            "PUT"


{-| A Universal Resource Identifier (as opposed to a Locator which is guaranteed to be de-referenceable.
-}
type alias Uri =
    String


{-| JSON-LD @type attributes
-}
type alias Kind =
    String


{-| An HTTP status code, as an Int
-}
type alias Status =
    Int


{-| HTTP request/response headers
-}
type alias Headers =
    Dict String String


{-| The body of an HTTP request or response
-}
type alias Body =
    String


{-| An HTTP response, status, headers and body
-}
type alias Response =
    { status : Status
    , headers : Headers
    , body : Body
    }


type alias AffordanceExtractor =
    ResponseToResult Affordance


type alias ResponseToResult a =
    Response -> Result String a


type alias BodyToRes x a =
    String -> Result x a


type alias RzToRes x a =
    Http.Response String -> Result x a


type alias ResToMsg x a msg =
    Result x a -> msg


{-| Pass a list of linkExtractors to nose, along with the handling for the final link

    HM.chain creds
        [ HM.browse [ "events" ] (HM.ByType "ViewAction")
        ]
        Http.emptyBody
        modelRes
        handleGetResult

-}
chain : List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> ResToMsg Http.Error a msg -> Cmd msg
chain =
    chainFrom (link GET "/api")


{-| Like `chain` but allows you to start from an arbitrary point
-}
chainFrom : Affordance -> List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> ResToMsg Http.Error a msg -> Cmd msg
chainFrom start extractors headers body makeRes toMsg =
    let
        plan =
            browseFrom start extractors headers body makeRes
    in
    Task.attempt toMsg plan


{-| Given a start point and a list of AffordanceExtractors,
this function will fetch the first resource, and then follow links as directed,
finally performing whatever action the makeRes function describes.

    browseFrom start extractors headers body makeRes =

-}
browseFrom : Affordance -> List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> Task Http.Error a
browseFrom start extractors headers body makeRes =
    let
        nextHop ex task =
            task |> andThen (follow headers Http.emptyBody ex)
    in
    List.foldl nextHop (Task.succeed start) extractors
        |> andThen (follow headers body makeRes)


{-| Make a generic request, with method, URI, headers and body defined
-}
request : Method -> String -> List Http.Header -> Http.Body -> BodyToRes String a -> ResToMsg Http.Error a msg -> Cmd msg
request method url headers body makeRes toMsg =
    Task.attempt toMsg
        (follow headers body (\r -> makeRes r.body) (link method url))


{-| follow one "hop" of a browse chain
-}
follow : List Http.Header -> Http.Body -> ResponseToResult a -> Affordance -> Task Http.Error a
follow headers body makeRes aff =
    Http.task
        (Debug.log "hop"
            { method = methodName aff.method
            , url = aff.uri
            , body = body
            , timeout = Nothing
            , resolver = baseResolver makeRes
            , headers = headers
            }
        )


{-| The most basic HATEOS browsing function - given a list of String to find an object in a response,
and the OperationSelector to pick an Operation, returns a function to extract an affordance.

    browse at sel response =

-}
browse : List String -> OperationSelector -> AffordanceExtractor
browse at sel response =
    decodeString (D.at at affordanceListDecoder) response.body
        |> Result.mapError D.errorToString
        |> Result.andThen
            (\l ->
                selectAffordance sel l
                    |> Result.fromMaybe ("no matching affordance: " ++ selToString sel)
            )


{-| Utility function for decoding optional fields into Maybes
-}
decodeMaybe : String -> D.Decoder a -> D.Decoder (Maybe a -> b) -> D.Decoder b
decodeMaybe name dec =
    DP.optional name (D.map Just dec) Nothing


{-| Utility function for encoding Maybes into optional fields
-}
encodeMaybe : (a -> E.Value) -> Maybe a -> E.Value
encodeMaybe enc ma =
    case ma of
        Just a ->
            enc a

        Nothing ->
            E.null


{-| Finally, some operations use a URI template as their @id, e.g. a search operation might have
a query parameter. Provide the variables for that template via the "vars"
You can use fillIn to provide those where needed; the signature is appropriate for `|>`
e.g.

    HM.browse [] (ByType "FindAction") |> HM.fillIn (Dict.fromList [("event\_id", id)][("event_id", id)])

-}
fillIn : TemplateVars -> AffordanceExtractor -> AffordanceExtractor
fillIn vars affex =
    \r ->
        affex r
            |> Result.map (\aff -> { aff | uri = Debug.log "fillIn" (Url.Interpolate.interpolate (Debug.log "aff.uri" aff.uri) (Debug.log "fill vars" vars)) })


{-| fill is appropriate for using at the head of a `chainFrom`, where the first request has to be constructed.
-}
fill : TemplateVars -> Affordance -> Affordance
fill vars aff =
    { aff | uri = Url.Interpolate.interpolate aff.uri vars }


{-| convenience to decode the body of a HTTP response
-}
decodeBody : D.Decoder resource -> { a | body : String } -> Result String resource
decodeBody decoder res =
    res.body
        |> D.decodeString decoder
        |> Result.mapError D.errorToString


linkByName : String -> AffordanceExtractor
linkByName =
    doByName GET


doByName : Method -> String -> AffordanceExtractor
doByName method name response =
    decodeString (D.dict D.value) response.body
        |> Result.mapError D.errorToString
        |> Result.andThen
            (\links ->
                case Dict.get name links of
                    Just lv ->
                        D.decodeValue D.string lv
                            |> Result.mapError D.errorToString
                            |> Result.map (\l -> link method l)

                    Nothing ->
                        Err (String.concat [ "No ", name, " link!" ])
            )


{-| Represents _how_ an operation is to be selected from a resource. Prefer `ByType`
-}
type OperationSelector
    = ByIndex Int
    | ByMethod Method
    | ByType String


selToString : OperationSelector -> String
selToString sel =
    case sel of
        ByIndex n ->
            "index: " ++ String.fromInt n

        ByMethod m ->
            "method: " ++ methodName m

        ByType t ->
            "type: " ++ t


{-| Variables to be used filling in a URITemplate. Closely related to HTML form parameters for the GET action type.
-}
type alias TemplateVars =
    Dict String String


{-| Choose an Affordance from a list using an OperationSelector
-}
selectAffordance : OperationSelector -> List Affordance -> Maybe Affordance
selectAffordance sel affordances =
    (case sel of
        ByIndex idx ->
            List.drop idx affordances

        ByMethod m ->
            List.filter (\aff -> aff.method == m) affordances

        ByType k ->
            List.filter (\aff -> Maybe.map (\is -> k == is) aff.kind |> Maybe.withDefault False) affordances
    )
        |> List.head


{-| Convenience decoders for extracting Affordances from API responses
-}
affordanceListDecoder : Decoder (List Affordance)
affordanceListDecoder =
    D.map2 unrollOperations
        (D.field "type" D.string
            |> D.andThen affordanceRef
        )
        (D.field "operation" (D.list operationDecoder))


affordanceRef : String -> Decoder String
affordanceRef kind =
    case kind of
        "Link" ->
            D.field "id" D.string

        "Resource" ->
            D.field "id" D.string

        "IriTemplate" ->
            D.field "template" D.string

        _ ->
            D.fail ("Trying to decode a resource, but its type was " ++ kind)


unrollOperations : String -> List Operation -> List Affordance
unrollOperations url ops =
    List.map (\op -> Affordance op.method url op.kind) ops


operationDecoder : Decoder Operation
operationDecoder =
    D.map2 Operation
        (D.field "method" methodDecoder)
        (D.maybe (D.field "type" D.string))


methodDecoder : Decoder Method
methodDecoder =
    D.string
        |> D.andThen
            (\m ->
                case m of
                    "GET" ->
                        D.succeed GET

                    "POST" ->
                        D.succeed POST

                    "DELETE" ->
                        D.succeed DELETE

                    "PUT" ->
                        D.succeed PUT

                    _ ->
                        D.fail <| String.concat [ "trying to decode ", m, " as an HTTP method" ]
            )


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


baseRzToRes : ResponseToResult a -> RzToRes Http.Error a
baseRzToRes extractValue =
    \response ->
        case Debug.log "response" response of
            Http.BadUrl_ url ->
                Err (Http.BadUrl url)

            Http.Timeout_ ->
                Err Http.Timeout

            Http.NetworkError_ ->
                Err Http.NetworkError

            -- Http.BadStatus means that we cannot extract knowledge from non-2xx responses
            -- Or we could build a Response and pass it to extractValue in both cases;
            -- would need to review existing uses
            Http.BadStatus_ metadata _ ->
                Err (Http.BadStatus metadata.statusCode)

            Http.GoodStatus_ metadata body ->
                Result.mapError Http.BadBody (Debug.log "extractValue" (extractValue (Response metadata.statusCode metadata.headers body)))


baseResolver : ResponseToResult value -> Resolver Http.Error value
baseResolver extractValue =
    Http.stringResolver <| baseRzToRes extractValue
