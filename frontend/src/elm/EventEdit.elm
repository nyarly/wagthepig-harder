module EventEdit exposing (Model, Bookmark(..), Msg(..), init, forCreate, view, bidiupdate)

import Dict
import Time
import Json.Decode as D
import Json.Encode as E
import Html exposing (Html, form, button, text)
import Html.Events exposing (onSubmit)
import Html.Attributes exposing (id, type_, disabled)
import Html.Attributes.Extra as Attr
import Iso8601

import Auth
import Hypermedia as HM exposing (Affordance, OperationSelector(..), Response, Method(..))
import ViewUtil as Eww
import ResourceUpdate as Up
import OutMsg
import Router
import Task

-- I would like this to be create-or-edit
-- update Affordance controls where and how to send the data
type alias Model =
  { creds: Auth.Cred
  , resource: Resource -- XXX Maybe?
  }

type alias Resource =
  { id: Maybe Affordance
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
      Nothing
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
      Nothing
      ""
      Nothing
      (Just aff)
      ""
      (Time.millisToPosix 0)
      ""
    )

encodeEvent : Resource -> E.Value
encodeEvent ev =
  E.object
    [ ("name", E.string ev.name)
    , ("time", Iso8601.encode ev.time)
    , ("location", E.string ev.location)
    ]

decoder : D.Decoder Resource
decoder =
  D.map7 Resource
    (D.map (\u -> Just (HM.link GET u)) (D.field "id" D.string))
    (D.field "nick" D.string)
    (D.map (\laff -> HM.selectAffordance (ByType "FindAction") laff) HM.affordanceListDecoder)
    (D.map (\laff -> HM.selectAffordance (ByType "UpdateAction") laff) HM.affordanceListDecoder)
    (D.field "name" D.string)
    (D.field "time" Iso8601.decoder)
    (D.field "location" D.string)

type Msg
  = Entered Auth.Cred Bookmark
  | TimeNow Time.Posix
  | ChangeName String
  | ChangeTime String
  | ChangeLocation String
  | Submit
  | GotEvent Resource OutMsg.Msg
  | ErrGetEvent HM.Error

view : Model -> List (Html Msg)
view model =
  let
      ev = model.resource
  in
  [
    form [ onSubmit Submit ]
      [ (Eww.inputPair [] "Name" ev.name ChangeName)
      , (Eww.inputPair [type_ "datetime-local"] "Time" (Iso8601.fromTime ev.time |> String.dropRight 1) ChangeTime)
      , (Eww.inputPair [] "Location" ev.location ChangeLocation)
      , button [ case model.resource.update of
           Just _ -> Attr.empty
           Nothing -> disabled True
        ] [ text "Submit" ]

      ]
  ]

bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
  let
      updateRes f m =
        {m| resource = f m.resource}
  in
  case msg of
    Entered creds loc -> case loc of
      None -> ({model | creds = creds}, getCurrentTime, OutMsg.None) -- creating a new Event
      Nickname id -> ({model | creds = creds}, fetchByNick creds model id, OutMsg.None)
      Url url -> ({model | creds = creds}, fetchFromUrl creds url, OutMsg.None )

    TimeNow t -> (updateRes (\r -> {r | time = t}) model, Cmd.none, OutMsg.None)
    ChangeName n -> (updateRes (\r -> {r | name = n}) model, Cmd.none, OutMsg.None)
    ChangeTime t -> case Iso8601.toTime t of
      Ok nt -> (updateRes (\r -> {r | time = nt}) model, Cmd.none, OutMsg.None)
      Err _ ->  (model, Cmd.none, OutMsg.None) -- XXX silent rejection of errors :(
    ChangeLocation l -> (updateRes (\r -> {r | location = l}) model, Cmd.none, OutMsg.None)

    GotEvent ev outmsg -> ({model | resource = ev}, Cmd.none, outmsg)
    ErrGetEvent _ -> (model, Cmd.none, OutMsg.None) -- XXX
    Submit -> (model, (putEvent model.creds model), OutMsg.None)

getCurrentTime : Cmd Msg
getCurrentTime =
  Task.perform TimeNow Time.now


makeMsg : Auth.Cred -> Up.Representation Resource -> Msg
makeMsg cred ex =
  case ex of
    Up.None -> Entered cred None
    Up.Loc aff -> Entered cred (Url aff)
    Up.Res res out -> GotEvent res out
    Up.Error err -> ErrGetEvent err

nickToVars : String -> Dict.Dict String String
nickToVars id =
  Dict.fromList [("event_id", id)]

browseToEvent : HM.TemplateVars -> List (Response -> Result String Affordance)
browseToEvent vars =
  [ HM.browse ["events"] (ByType "ViewAction")
  , HM.browse [] (ByType "FindAction") |> HM.fillIn vars
  ]

putEvent : Auth.Cred -> Model -> Cmd Msg
putEvent creds model =
  Up.put encodeEvent decoder (makeMsg creds) (Debug.log "creds" creds) model.resource

fetchByNick : Auth.Cred -> Model -> String -> Cmd Msg
fetchByNick creds model id =
  Up.fetchByNick decoder (makeMsg creds) nickToVars browseToEvent model.resource.template creds id

fetchFromUrl : Auth.Cred -> Affordance -> Cmd Msg
fetchFromUrl creds url =
  let
    routeByHasNick = Router.EventEdit << .nick
  in
    Up.fetchFromUrl decoder (makeMsg creds) routeByHasNick creds url
