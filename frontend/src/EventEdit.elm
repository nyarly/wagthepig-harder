module EventEdit exposing (Model, Bookmark(..), Msg(..), init, forCreate, view, bidiupdate)

import Dict
import Time
import Json.Decode as D
import Json.Encode as E
import Html exposing (Html, form, button, text)
import Html.Events exposing (onClick)
import Html.Attributes exposing (id, type_)
import Iso8601

import Auth
import Hypermedia as HM exposing (Affordance, OperationSelector(..), Response, Method(..))
import ViewUtil as Eww
import OutMsg
import Router
import Http

-- I would like this to be create-or-edit
-- update Affordance controls where and how to send the data
type alias Model =
  { creds: Auth.Cred
  , resource: Resource -- XXX Maybe?
  }

type alias Resource =
  { bookmark: Bookmark
  , nick: String
  , template: Maybe Affordance
  , update: Maybe Affordance
  , name: String
  , time: Time.Posix
  , location: String
  }

type Bookmark
  = None
  | Nickname String
  | Url Affordance

init : Model
init =
  Model
    Auth.unauthenticated
    (Resource
      None
      ""
      Nothing
      Nothing
      ""
      (Time.millisToPosix 0)
      ""
    )

forCreate : Affordance -> Model
forCreate aff =
  Model
    Auth.unauthenticated
    (Resource
      None
      ""
      Nothing
      (Just aff)
      ""
      (Time.millisToPosix 0)
      ""
    )

encodeModel : Model -> E.Value
encodeModel model =
  let
      ev = model.resource
  in
  E.object
    [ ("name", E.string ev.name)
    , ("time", Iso8601.encode ev.time)
    , ("location", E.string ev.location)
    ]

decoder : D.Decoder Resource
decoder =
  D.map7 Resource
    (D.map (\u -> Url (HM.link GET u)) (D.field "id" D.string))
    (D.field "nick" D.string)
    (D.map (\laff -> HM.selectAffordance (ByType "FindAction") laff) HM.affordanceListDecoder)
    (D.map (\laff -> HM.selectAffordance (ByType "UpdateAction") laff) HM.affordanceListDecoder)
    (D.field "name" D.string)
    (D.field "time" Iso8601.decoder)
    (D.field "location" D.string)

type Msg
  = Entered Auth.Cred Bookmark
  | ChangeName String
  | ChangeTime String
  | ChangeLocation String
  | Submit Affordance
  | GotEvent Resource OutMsg.Msg
  | ErrGetEvent HM.Error

view : Model -> List (Html Msg)
view model =
  let
      ev = model.resource
  in
  [
    form []
      [ (Eww.inputPair [] "Name" ev.name ChangeName)
      -- 90% sure this is dropping the UTC TZ, which is going to make this annoying
      , (Eww.inputPair [type_ "datetime-local"] "Time" (Iso8601.fromTime ev.time |> String.dropRight 1) ChangeTime)
      , (Eww.inputPair [] "Location" ev.location ChangeLocation)
      , submitButton model
      ]
  ]


submitButton : Model -> Html Msg
submitButton model =
  case model.resource.update of
    Just aff -> button [ onClick (Submit aff) ] [ text "Submit" ]
    _ -> button [] [ text "edit not available" ]

bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
  let
      updateRes f m =
        {m| resource = f m.resource}
  in
  case msg of
    Entered creds None -> ({init | creds = creds}, Cmd.none, OutMsg.None) -- creating a new Event
    Entered creds (Nickname id) -> ({model | creds = creds}, fetchByNick creds model id, OutMsg.None)
    Entered creds (Url url) -> ({model | creds = creds}, fetchFromUrl creds url, OutMsg.None )

    ChangeName n -> (updateRes (\r -> {r | name = n}) model, Cmd.none, OutMsg.None)
    ChangeTime t -> case Iso8601.toTime t of
      Ok(nt) -> (updateRes (\r -> {r | time = nt}) model, Cmd.none, OutMsg.None)
      Err(_) ->  (model, Cmd.none, OutMsg.None) -- XXX silent rejection of errors :(
    ChangeLocation l -> (updateRes (\r -> {r | location = l}) model, Cmd.none, OutMsg.None)
    GotEvent ev outmsg -> ({model | resource = ev}, Cmd.none, outmsg)
    ErrGetEvent _ -> (model, Cmd.none, OutMsg.None) -- XXX
    Submit aff -> (model, (putEvent model.creds model aff), OutMsg.None)

putEvent : Auth.Cred -> Model -> Affordance -> Cmd Msg
putEvent cred model aff =
  HM.chainFrom cred aff [] (model |> encodeModel >> Http.jsonBody) putResponse (handlePutResult cred)

type HopOrModel
  = Hop String
  | Got Resource

putResponse : Response -> Result String HopOrModel
putResponse res =
  case res.status of
    200 -> res.body
      |> D.decodeString decoder
      |> Result.mapError D.errorToString
      |> Result.map Got
    201 -> case Dict.get "location" res.headers of
      Just url -> Ok(Hop url)
      Nothing -> Err("Expected location of new Event")
    other -> Err("Unexpected status sending Event: " ++ String.fromInt other)

handlePutResult : Auth.Cred -> Result HM.Error HopOrModel -> Msg
handlePutResult cred res =
  case res of
    Ok(Got event) -> GotEvent event OutMsg.None
    Ok(Hop url) -> Entered cred (Url (HM.link GET url))
    Err(err) -> ErrGetEvent err

fetchByNick : Auth.Cred -> Model -> String -> Cmd Msg
fetchByNick creds model id =
  let
    handleNickGetResult = handleGetResult (\_ -> OutMsg.None)
  in
  case model.resource.template of
    Just aff ->
      HM.chainFrom creds (HM.fill (Dict.fromList [("event_id", id)]) aff)
        [] HM.emptyBody modelRes handleNickGetResult
    Nothing -> HM.chain creds
      [ HM.browse ["events"] (ByType "ViewAction")
      , HM.browse [] (ByType "FindAction") |> HM.fillIn (Dict.fromList [("event_id", id)])
      ] HM.emptyBody modelRes handleNickGetResult

fetchFromUrl : Auth.Cred -> Affordance -> Cmd Msg
fetchFromUrl creds access =
  HM.chainFrom creds access [] HM.emptyBody modelRes
    (handleGetResult (OutMsg.Main << OutMsg.Nav << Router.EventEdit << .nick))

handleGetResult : (Resource -> OutMsg.Msg ) -> Result HM.Error Resource -> Msg
handleGetResult  makeOut res =
  case res of
    Ok event -> GotEvent event (makeOut event)
    Err err -> ErrGetEvent err

modelRes : {a| body: String} -> Result String Resource
modelRes res =
  res.body
  |> D.decodeString decoder
  |> Result.mapError D.errorToString
