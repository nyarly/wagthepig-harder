module ResourceUpdate exposing
    ( Etag
    , MakeMsg
    , Representation(..)
    , apiRoot
    , create
    , delete
    , resultDispatch
    , retrieve
    , roundTrip
    , taggedResultDispatch
    , update
    )

import Dict
import Http
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import Json.Decode as D
import Json.Encode as E
import Task



{-
   Goal with this module is to handle the exchanges with the HM server that are standard

   We want to be able to
   - create a resource from whole cloth, and browse to "where to put it"
     - then either load the server's response
     - or fetch the response from the Location returned
   - browse to a resource based on a "nickname" stored in a FE route
   - edit and update (via a local affordance) a resource we have "in hand"

   So far:
   * FE needs to be able to fetch a resource based on its own router, so we need to take a nickname locator
     from the API and then be able to plug it into a URIT we can find easily.
     Or load directly from a URL.
     Or load nothing because we're actually creating a new instance... (debatable: maybe should have different pages...)

   * FE needs to be able send an update and process either the new data in a 200 or follow the Location of a 201

   interface to this module is in development

   consumers will need
   their own nickname type, that can be encoded and parsed from their Route
   their own resource type, with .update and .template fields (both Maybe Affordance) and the nickname
   encode function and decoder for the resource
   (assumed: the BE has an API For the resource that provides this data)

   encodeEvent : Resource -> E.Value
   decoder : D.Decoder Resource

   you'll want to define a few adaptors:

   makeMsg : Auth.Cred -> Up.Representation Resource -> Msg -- going to be a case
   nickToVars : nick -> Dict.Dict String String
   browseToIt : HM.TemplateVars -> List (Response -> Result String Affordance)

-}
{-
   makeMsg like....
   makeMsg cred rep =
     case rep of
       Up.Loc aff -> Entered cred (Url aff)
       Up.Res res out -> GotThing res out
       Up.Error err -> ErrGetThing err

   makeMsg = (then creds)
-}
{- The encodes the response from creating/updating a resource -}


type Representation e r
    = Loc Affordance
    | Res Etag r
    | Error e


type alias Etag =
    Maybe String


etagHeader : Etag -> List Http.Header
etagHeader etag =
    case etag of
        Just e ->
            [ Http.header "Etag" e ]

        Nothing ->
            []


type alias MakeMsg e r msg =
    Representation e r -> msg


type alias ResToMsg e r msg =
    Result e r -> msg


apiRoot : Affordance
apiRoot =
    HM.link HM.GET "/api"


resultDispatch : (error -> a) -> (value -> a) -> Result error value -> a
resultDispatch fromErr fromOk =
    taggedResultDispatch (\_ -> fromErr) (\_ -> fromOk) ()


taggedResultDispatch : (req -> error -> msg) -> (req -> value -> msg) -> req -> Result error value -> msg
taggedResultDispatch fromErr fromOk req res =
    case res of
        Ok v ->
            fromOk req v

        Err x ->
            fromErr req x



{-
   When you are sending data to the backend and only care if it was successfully received
-}


type alias Create s msg =
    { resource : s
    , etag : Maybe Etag
    , encode : s -> E.Value
    , resMsg : ResToMsg HM.Error () msg
    , startAt : Affordance
    , browsePlan : List AffordanceExtractor
    , headers : List Http.Header
    }


create : Create s msg -> Cmd msg
create { headers, resource, etag, encode, resMsg, startAt, browsePlan } =
    let
        etagH =
            Maybe.withDefault [] (Maybe.map etagHeader etag)

        trip =
            HM.browseFrom startAt browsePlan (etagH ++ headers) (resource |> encode >> Http.jsonBody) emptyResponse
    in
    Task.attempt resMsg trip



{- When you are requesting data from the server without a payload -}


type alias Retrieve r msg =
    { decoder : D.Decoder r
    , resMsg : ResToMsg HM.Error ( Etag, r ) msg
    , startAt : Affordance
    , browsePlan : List AffordanceExtractor
    , headers : List Http.Header
    }


retrieve : Retrieve r msg -> Cmd msg
retrieve { headers, decoder, resMsg, startAt, browsePlan } =
    let
        trip =
            HM.browseFrom startAt browsePlan headers Http.emptyBody (modelRes decoder)
    in
    Task.attempt resMsg trip



{- When you are sending data to the server and expecting data in response -}


type alias Update s r msg =
    { resource : s
    , etag : Maybe Etag
    , encode : s -> E.Value
    , decoder : D.Decoder r
    , resMsg : ResToMsg HM.Error ( Etag, r ) msg
    , startAt : Affordance
    , browsePlan : List AffordanceExtractor
    , headers : List Http.Header
    }


update : Update s r msg -> Cmd msg
update { headers, resource, etag, encode, decoder, resMsg, startAt, browsePlan } =
    let
        etagH =
            Maybe.withDefault [] (Maybe.map etagHeader etag)

        trip =
            HM.browseFrom startAt browsePlan (etagH ++ headers) (resource |> encode >> Http.jsonBody) (putResponse decoder)
                |> Task.andThen followHop

        followHop rep =
            case rep of
                Hop url ->
                    HM.browseFrom (HM.link HM.GET url) [] headers Http.emptyBody (landPutResponse decoder)

                Got e res ->
                    Task.succeed ( e, res )
    in
    Task.attempt resMsg trip



{- When you're making an empty request of the server, and only care if it was successful -}


type alias Delete msg =
    { resMsg : ResToMsg HM.Error () msg
    , startAt : Affordance
    , browsePlan : List AffordanceExtractor
    , headers : List Http.Header
    }


delete : Delete msg -> Cmd msg
delete { headers, resMsg, startAt, browsePlan } =
    let
        trip =
            HM.browseFrom startAt browsePlan headers Http.emptyBody emptyResponse
    in
    Task.attempt resMsg trip


type alias RoundTrip r msg =
    { encode : r -> E.Value
    , decoder : D.Decoder r
    , makeMsg : MakeMsg Http.Error r msg
    , browsePlan : List AffordanceExtractor
    , updateRes : r -> Result Http.Error ( r, Affordance )
    , headers : List Http.Header
    }


roundTrip : RoundTrip rz msg -> Cmd msg
roundTrip { encode, decoder, makeMsg, browsePlan, updateRes, headers } =
    let
        doUpdate ( e, r ) =
            case updateRes r of
                Ok ( new, aff ) ->
                    Task.succeed ( e, new, aff )

                Err x ->
                    Task.fail x

        toMsg =
            handlePutResult makeMsg

        trip =
            HM.browseFrom (HM.link HM.GET "/api") browsePlan headers HM.emptyBody (modelRes decoder)
                |> Task.andThen doUpdate
                |> Task.andThen
                    (\( etag, resource, aff ) ->
                        HM.browseFrom aff [] (etagHeader etag ++ headers) (resource |> encode >> Http.jsonBody) (putResponse decoder)
                    )
    in
    Task.attempt toMsg trip


type HopOrResource r
    = Hop String
    | Got Etag r


type alias AffordanceExtractor =
    Response -> Result String Affordance


gotFromTuple : ( Etag, r ) -> HopOrResource r
gotFromTuple ( etag, r ) =
    Got etag r


modelRes : D.Decoder r -> { a | body : String, headers : HM.Headers } -> Result String ( Etag, r )
modelRes decoder res =
    let
        etag =
            Dict.get "etag" (Debug.log "headers" res.headers)
    in
    res.body
        |> D.decodeString decoder
        |> Result.map (\r -> ( etag, r ))
        |> Result.mapError D.errorToString


putResponse : D.Decoder r -> Response -> Result String (HopOrResource r)
putResponse decoder res =
    case res.status of
        200 ->
            modelRes decoder res
                |> Result.map gotFromTuple

        201 ->
            case Dict.get "location" res.headers of
                Just url ->
                    Ok (Hop url)

                Nothing ->
                    Err "Expected location of new resource"

        other ->
            Err ("Unexpected status sending resource: " ++ String.fromInt other)


emptyResponse : Response -> Result String ()
emptyResponse res =
    case res.status of
        200 ->
            Ok ()

        201 ->
            Ok ()

        other ->
            Err ("Unexpected status sending resource: " ++ String.fromInt other)


landPutResponse : D.Decoder r -> Response -> Result String ( Etag, r )
landPutResponse decoder res =
    case res.status of
        200 ->
            modelRes decoder res

        201 ->
            Err "Second 201; assuming a loop"

        other ->
            Err ("Unexpected status sending resource: " ++ String.fromInt other)


handlePutResult : MakeMsg e r msg -> Result e (HopOrResource r) -> msg
handlePutResult makeMsg res =
    makeMsg <|
        case res of
            Ok (Hop url) ->
                Loc (HM.link GET url)

            Ok (Got etag rs) ->
                Res etag rs

            Err err ->
                Error err
