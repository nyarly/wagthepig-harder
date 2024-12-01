module ResourceUpdate exposing (Etag, Representation(..), fetchByNick, fetchFromUrl, put)

import Auth
import Dict
import Http
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import Json.Decode as D
import Json.Encode as E
import OutMsg
import Router



{-
   Goal with this module is to handle the exchanges with the HM server that are standard

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


type Representation r
    = Loc Affordance
    | Res Etag r OutMsg.Msg
    | Error HM.Error
    | None


type alias Etag =
    Maybe String


etagHeader : Etag -> List Http.Header
etagHeader etag =
    case etag of
        Just e ->
            [ Http.header "Etag" e ]

        Nothing ->
            []


type alias MakeMsg r msg =
    Representation r -> msg


put : ({ r | update : Maybe Affordance } -> E.Value) -> D.Decoder { r | update : Maybe Affordance } -> MakeMsg { r | update : Maybe Affordance } msg -> Auth.Cred -> Etag -> { r | update : Maybe Affordance } -> Cmd msg
put encode decoder makeMsg cred etag resource =
    case resource.update of
        Just aff ->
            HM.chainFrom cred aff [] (etagHeader etag) (resource |> encode >> Http.jsonBody) (putResponse decoder) (handlePutResult makeMsg)

        _ ->
            Cmd.none


fetchByNick : D.Decoder r -> MakeMsg r msg -> (n -> Dict.Dict String String) -> (Dict.Dict String String -> List AffordanceExtractor) -> Maybe Affordance -> Auth.Cred -> n -> Cmd msg
fetchByNick decoder makeMsg nickToVars browsePath template creds nick =
    let
        handleNickGetResult =
            handleGetResult (\_ -> OutMsg.None) makeMsg
    in
    case template of
        Just aff ->
            HM.chainFrom creds
                (HM.fill (nickToVars nick) aff)
                []
                []
                HM.emptyBody
                (modelRes decoder)
                handleNickGetResult

        Nothing ->
            HM.chain creds (browsePath (nickToVars nick)) [] HM.emptyBody (modelRes decoder) handleNickGetResult


fetchFromUrl : D.Decoder r -> MakeMsg r msg -> (r -> Router.Target) -> Auth.Cred -> HM.Uri -> Cmd msg
fetchFromUrl decoder makeMsg routeByHasNick creds access =
    HM.chainFrom creds
        (HM.link
            HM.GET
            access
        )
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


handleResult : (r -> OutMsg.Msg) -> MakeMsg r msg -> Result HM.Error (HopOrResource r) -> msg
handleResult makeOut makeMsg res =
    makeMsg <|
        case res of
            Ok (Hop url) ->
                Loc (HM.link GET url)

            Ok (Got etag rs) ->
                Res etag rs (makeOut rs)

            Err err ->
                Error err


handlePutResult : MakeMsg r msg -> Result HM.Error (HopOrResource r) -> msg
handlePutResult makeMsg res =
    handleResult (\_ -> OutMsg.None) makeMsg res


handleGetResult : (r -> OutMsg.Msg) -> MakeMsg r msg -> Result HM.Error ( Etag, r ) -> msg
handleGetResult makeOut makeMsg rz =
    handleResult makeOut makeMsg (Result.map gotFromTuple rz)
