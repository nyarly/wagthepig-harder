module Hypermedia exposing
    ( Affordance
    , Body
    , Error
    , Headers
    , Kind
    , Method(..)
    , OperationSelector(..)
    , Response
    , Status
    , TemplateVars
    , Uri
    , affordanceListDecoder
    , browse
    , browseFrom
    , chain
    , chainFrom
    , decodeBody
    , decodeMaybe
    , delete
    , doByName
    , emptyBody
    , emptyResponse
    , encodeMaybe
    , fill
    , fillIn
    , get
    , link
    , -- re-exports so that consumers don't always have to bring in Http
      linkByName
    , post
    , put
    , selectAffordance
    )

-- Not sure about these anymore

import Auth
import Dict exposing (Dict)
import Http exposing (Resolver)
import Json.Decode as D exposing (Decoder, decodeString)
import Json.Decode.Pipeline as DP
import Json.Encode as E
import Task exposing (Task, andThen)
import Url.Interpolate


emptyBody : Http.Body
emptyBody =
    Http.emptyBody


emptyResponse : Response -> Result String ()
emptyResponse rx =
    if rx.status >= 200 && rx.status < 300 then
        Ok ()

    else
        Err rx.body


type alias Error =
    Http.Error



-- HTTP


type alias Affordance =
    { method : Method
    , uri : Uri
    , kind : Maybe Kind -- JSON-LD @type
    }


link : Method -> Uri -> Affordance
link method uri =
    Affordance method uri Nothing


type Method
    = GET
    | POST
    | DELETE
    | PUT



-- there's more


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


type alias Uri =
    String


type alias Kind =
    String


type alias Status =
    Int


type alias Headers =
    Dict String String


type alias Body =
    String


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



{-
   Pass a list of linkExtractors to nose, along with the handling for the final link
     HM.chain creds [
       HM.browse ["events"] (HM.ByType "ViewAction")
     ] Http.emptyBody modelRes handleGetResult

-}


chain : Auth.Cred -> List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> ResToMsg Http.Error a msg -> Cmd msg
chain =
    chainFrom (link GET "/api")


chainFrom : Affordance -> Auth.Cred -> List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> ResToMsg Http.Error a msg -> Cmd msg
chainFrom start cred extractors headers body makeRes toMsg =
    let
        plan =
            browseFrom start cred extractors headers body makeRes
    in
    Task.attempt toMsg plan


browseFrom : Affordance -> Auth.Cred -> List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> Task Http.Error a
browseFrom start cred extractors headers body makeRes =
    let
        nextHop ex task =
            task |> andThen (follow cred [] Http.emptyBody ex)
    in
    List.foldl nextHop (Task.succeed start) extractors
        |> andThen (follow cred headers body makeRes)


request : Auth.Cred -> Method -> String -> Http.Body -> BodyToRes String a -> ResToMsg Http.Error a msg -> Cmd msg
request maybeCred method url body makeRes toMsg =
    Task.attempt toMsg
        (follow maybeCred [] body (\r -> makeRes r.body) (link method url))


follow : Auth.Cred -> List Http.Header -> Http.Body -> ResponseToResult a -> Affordance -> Task Http.Error a
follow maybeCred headers body makeRes aff =
    Http.task
        (Debug.log "hop"
            { method = methodName aff.method
            , url = aff.uri
            , body = body
            , timeout = Nothing
            , resolver = baseResolver makeRes
            , headers = Auth.credHeader maybeCred ++ headers
            }
        )



{-
   Key to the Hypermedia style is the ability to attach "affordances" to a resource -
   in essence to be able to put links and forms and buttons in the respresentation of
   a resources that let the user know what kinds of things they can do with it.
   In JSON-LD with Hydra (and Schema.org Actions), affordances are attached to
   Resources via an operation(s) property. The document returned represents a resource itself,
   and might have fields whose values are Resources as well,
   so you can indicate a path in the JSON-LD response
   where the resource in question is "at" (with an empty list ([]) being the thing itself)
   then with operation you want to invoke, either by index (ick), "first by method" (okay)
   or by kind (in JSON-LD this will be its @type, generally a specialization of Action)
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



{-
   Utility function for decoding optional fields into Maybes
-}


decodeMaybe : String -> D.Decoder a -> D.Decoder (Maybe a -> b) -> D.Decoder b
decodeMaybe name dec =
    DP.optional name (D.map Just dec) Nothing



{-
   Utility function for encoding Maybes into optional fields
-}


encodeMaybe : (a -> E.Value) -> Maybe a -> E.Value
encodeMaybe enc ma =
    case ma of
        Just a ->
            enc a

        Nothing ->
            E.null



{-
   Finally, some operations use a URI template as their @id, e.g. a search operation might have
   a query parameter. Provide the variables for that template via the "vars"
   You can use fillIn to provide those where needed; the signature is appropriate for `|>`
   e.g.
      HM.browse [] (ByType "FindAction") |> HM.fillIn (Dict.fromList [("event_id", id)])
-}


fillIn : TemplateVars -> AffordanceExtractor -> AffordanceExtractor
fillIn vars affex =
    \r ->
        affex r
            |> Result.map (\aff -> { aff | uri = Debug.log "fillIn" (Url.Interpolate.interpolate (Debug.log "aff.uri" aff.uri) (Debug.log "fill vars" vars)) })



{-
   fill is appropriate for using at the head of a `chainFrom`, where the first request has to be constructed.
-}


fill : TemplateVars -> Affordance -> Affordance
fill vars aff =
    { aff | uri = Url.Interpolate.interpolate aff.uri vars }


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


type alias TemplateVars =
    Dict String String


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


jsonRequest : Auth.Cred -> Method -> String -> Http.Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
jsonRequest maybeCred method url body decoder toMsg =
    let
        toRes =
            \b -> Result.mapError D.errorToString (D.decodeString decoder b)
    in
    request maybeCred method url body toRes toMsg


get : Auth.Cred -> String -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
get maybeCred url decoder toMsg =
    jsonRequest maybeCred GET url Http.emptyBody decoder toMsg


put : Auth.Cred -> String -> Http.Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
put maybeCred url body decoder toMsg =
    jsonRequest maybeCred PUT url body decoder toMsg


post : Auth.Cred -> String -> Http.Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
post maybeCred url body decoder toMsg =
    jsonRequest maybeCred POST url body decoder toMsg


delete : Auth.Cred -> String -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
delete maybeCred url decoder toMsg =
    jsonRequest maybeCred DELETE url Http.emptyBody decoder toMsg


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
