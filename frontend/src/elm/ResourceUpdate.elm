module ResourceUpdate exposing
    ( Etag
    , FetchPlan(..)
    , MakeMsg
    , Representation(..)
    , browseToSend
    , doRoundTrip
    , fetchByNick
    , fetchFromUrl
    , put
    )

import Auth
import Dict
import Http
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import Json.Decode as D
import Json.Encode as E
import OutMsg
import Router
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

   -- then you can wrap ResourceUpdate.put, ResourceUpdate.fetchFromUrl and ResourceUpdate.fetchByNick
   -- e.g.
   putThing : Auth.Cred -> Model -> Cmd Msg
   putThing creds model =
     Up.put encodeEvent decoder (makeMsg creds) creds model.resource
     -- put : ({r | update: Maybe Affordance} -> E.Value) -> D.Decoder {r|update: Maybe Affordance} -> MakeMsg {r|update: Maybe Affordance} msg -> Auth.Cred -> {r | update: Maybe Affordance} -> Cmd msg

   fetchByNick : Auth.Cred -> Model -> String -> Cmd Msg
   fetchByNick creds model id =
     Up.fetchByNick decoder (makeMsg creds) nickToVars browseToEvent model.resource.template creds id
     -- fetchByNick : D.Decoder r -> MakeMsg r msg -> (n -> Dict.Dict String String)  -> (Dict.Dict String String -> List(AffordanceExtractor)) -> Maybe Affordance -> Auth.Cred -> n -> Cmd msg

   fetchFromUrl : Auth.Cred -> Affordance -> Cmd Msg
   fetchFromUrl creds url =
     Up.fetchFromUrl decoder (makeMsg creds) (Router.EventEdit << .nick) creds url
     -- fetchFromUrl : D.Decoder r -> MakeMsg r msg -> (r -> Router.Target) -> Auth.Cred -> Affordance -> Cmd msg
-}
{-
   makeMsg like....
   makeMsg cred rep =
     case rep of
       Up.None -> Entered cred None
       Up.Loc aff -> Entered cred (Url aff)
       Up.Res res out -> GotThing res out
       Up.Error err -> ErrGetThing err

   makeMsg = (then creds)
-}
{- The encodes the response from creating/updating a resource -}


type Representation e r
    = Loc Affordance
    | Res Etag r OutMsg.Msg
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


type alias BrowsePath =
    Dict.Dict String String -> List AffordanceExtractor


type FetchPlan
    = Browse BrowsePath
    | Template Affordance


browseToSend : (r -> E.Value) -> D.Decoder r -> MakeMsg HM.Error r msg -> (n -> Dict.Dict String String) -> BrowsePath -> n -> Auth.Cred -> r -> Cmd msg
browseToSend encode decoder makeMsg nickToVars browsePath nick creds resource =
    HM.chain creds (browsePath (nickToVars nick)) [] (resource |> encode >> Http.jsonBody) (putResponse decoder) (handlePutResult makeMsg)



-- XXX "has an affordance called 'update'" hits weird
-- XXX even moreso, should we consider a generic Model with etag, affordances, and (generic) resource


type alias Updateable r =
    { r | update : Maybe Affordance }


type alias RoundTrip r msg =
    { encode : r -> E.Value
    , decoder : D.Decoder r
    , makeMsg : MakeMsg Http.Error r msg
    , browsePlan : List AffordanceExtractor
    , updateRes : r -> Result Http.Error ( r, Affordance )
    , creds : Auth.Cred
    }


doRoundTrip : RoundTrip rz msg -> Cmd msg
doRoundTrip { encode, decoder, makeMsg, browsePlan, updateRes, creds } =
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
            HM.browseFrom (HM.link HM.GET "/api") creds browsePlan [] HM.emptyBody (modelRes decoder)
                |> Task.andThen doUpdate
                |> Task.andThen
                    (\( etag, resource, aff ) ->
                        HM.browseFrom aff creds [] (etagHeader etag) (resource |> encode >> Http.jsonBody) (putResponse decoder)
                    )
    in
    Task.attempt toMsg trip


put : (Updateable r -> E.Value) -> D.Decoder (Updateable r) -> MakeMsg HM.Error (Updateable r) msg -> Auth.Cred -> Etag -> Updateable r -> Cmd msg
put encode decoder makeMsg cred etag resource =
    case resource.update of
        Just aff ->
            HM.chainFrom aff cred [] (etagHeader etag) (resource |> encode >> Http.jsonBody) (putResponse decoder) (handlePutResult makeMsg)

        _ ->
            Cmd.none


fetchByNick : D.Decoder r -> MakeMsg HM.Error r msg -> (n -> Dict.Dict String String) -> BrowsePath -> Auth.Cred -> n -> Cmd msg
fetchByNick decoder makeMsg nickToVars browsePath creds nick =
    let
        handleNickGetResult =
            handleGetResult (\_ -> OutMsg.None) makeMsg
    in
    HM.chain creds (browsePath (nickToVars nick)) [] HM.emptyBody (modelRes decoder) handleNickGetResult



-- XXX Consider having Representation.Loc wrap an opaque type and use that instead of HM.Uri


fetchFromUrl : D.Decoder r -> MakeMsg HM.Error r msg -> (r -> Router.Target) -> Auth.Cred -> HM.Uri -> Cmd msg
fetchFromUrl decoder makeMsg routeByHasNick creds access =
    HM.chainFrom
        (HM.link
            HM.GET
            access
        )
        creds
        []
        []
        HM.emptyBody
        (modelRes decoder)
        (handleGetResult (OutMsg.Main << OutMsg.Nav << routeByHasNick) makeMsg)


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


handleResult : (r -> OutMsg.Msg) -> MakeMsg e r msg -> Result e (HopOrResource r) -> msg
handleResult makeOut makeMsg res =
    makeMsg <|
        case res of
            Ok (Hop url) ->
                Loc (HM.link GET url)

            Ok (Got etag rs) ->
                Res etag rs (makeOut rs)

            Err err ->
                Error err


handlePutResult : MakeMsg e r msg -> Result e (HopOrResource r) -> msg
handlePutResult makeMsg res =
    handleResult (\_ -> OutMsg.None) makeMsg res


handleGetResult : (r -> OutMsg.Msg) -> MakeMsg e r msg -> Result e ( Etag, r ) -> msg
handleGetResult makeOut makeMsg rz =
    handleResult makeOut makeMsg (Result.map gotFromTuple rz)
