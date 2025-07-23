module Hypermedia exposing
    ( Method(..)
    , methodName
    , Uri
    , Headers
    , Body
    , Status
    , Response
    , ResponseToResult
    , Affordance
    , AffordanceExtractor
    , Kind
    , link
    , browse
    , OperationSelector(..)
    , selectAffordance
    , affordanceListDecoder
    , TemplateVars
    , fill
    , fillIn
    , Error
    , decodeMaybe
    , encodeMaybe
    , emptyBody
    , emptyResponse
    )

{-| Definitations to support RESTful Hydra JSON-LD interfaces.

Key to the Hypermedia style is the ability to attach "affordances" to a resource -
in essence to be able to put links and forms and buttons in the respresentation of
a resources that let the user know what kinds of things they can do with it.
In JSON-LD with Hydra (and Schema.org Actions), affordances are attached to
Resources via an operation(s) property.


# REST primitives

@docs Method
@docs methodName
@docs Uri
@docs Headers
@docs Body
@docs Status
@docs Response
@docs ResponseToResult


# Affordance Based Browsing


## Affordances

An affordance is essentially a URI/Method pair -
it's what let's you know that there's an interface you can interact with.
We also sometimes mark them with a JSON-LD @type attribute,
which gives some information about what to expect from the interface.

@docs Affordance
@docs AffordanceExtractor
@docs Kind
@docs link
@docs browse
@docs OperationSelector
@docs selectAffordance
@docs affordanceListDecoder


## URI Templates

Because not every Resource can be known an enumerated ahead of time,
some Affordances present a URI template.
The classic case is being able to
search for arbitrary terms with a "?q=term" URL parameter.

@docs TemplateVars
@docs fill
@docs fillIn


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
import Http
import Json.Decode as D exposing (Decoder, decodeString)
import Json.Decode.Pipeline as DP
import Json.Encode as E
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


{-| Return a String version of a Method
-}
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


{-| JSON-LD Hydra Operation @type attributes, like "ViewAction", "FindAction" or "UpdateAction."
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


{-| Extracts an Affordance from a response
-}
type alias AffordanceExtractor =
    ResponseToResult Affordance


{-| Converts an HTTP response into a Result
-}
type alias ResponseToResult a =
    Response -> Result String a


{-| The most basic HATEOS browsing function:
given a `List String` that serves as a path into an object in a response,
and the OperationSelector to pick an Operation,
returns a function to extract an affordance.

Use this function, together with `fill`and `fillIn` to
construct a "browse plan": a list of AffordanceExtractors that
functions like `LinkFollowing.chain` or `ResourceUpdate.update` require

    -- browse at sel response =
    [ HM.browse [ "events" ] (ByType "ViewAction")
    , HM.browse [ "eventById" ] (ByType "FindAction") |> HM.fillIn vars
    ]

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
            |> Result.map (\aff -> { aff | uri = Url.Interpolate.interpolate aff.uri vars })


{-| fill is appropriate for using at the head of a `chainFrom`, where the first request has to be constructed.
-}
fill : TemplateVars -> Affordance -> Affordance
fill vars aff =
    { aff | uri = Url.Interpolate.interpolate aff.uri vars }


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

    D.map (HM.selectAffordance (ByType "FindAction")) HM.affordanceListDecoder

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
