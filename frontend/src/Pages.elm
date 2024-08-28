module Pages exposing (Msg(..), Models, init, view, bidiupdate, pageNav)

import Html exposing (Html)

import Router
import Auth
import OutMsg

import Landing
import Login
import Profile
import Events
import EventEdit
import Router exposing (Target(..))

type Msg
  = LandingMsg Landing.Msg
  | LoginMsg Login.Msg
  | ProfileMsg Profile.Msg
  | EventsMsg Events.Msg
  | EventEditMsg EventEdit.Msg

type alias Models =
  { landing: Landing.Model
  , login: Login.Model
  , profile: Profile.Model
  , events: Events.Model
  , event: EventEdit.Model
  }

init : Models
init =
  Models
    Landing.Model
    Login.init
    Profile.init
    Events.init
    EventEdit.init

view : Router.Target -> Models -> (Msg -> msg) -> List (Html msg)
view target models toMsg =
  let
    wrapMsg msg htmls =
        List.map (Html.map (\m -> toMsg (msg m))) htmls
  in
  case target of
    Router.Landing -> Landing.view models.landing
      |> wrapMsg LandingMsg
    Router.Login -> Login.view models.login
      |> wrapMsg LoginMsg
    Router.Profile -> Profile.view models.profile
      |> wrapMsg ProfileMsg
    Router.Events -> Events.view models.events
      |> wrapMsg EventsMsg
    Router.EventEdit _ -> EventEdit.view models.event
      |> wrapMsg EventEditMsg
    Router.CreateEvent -> EventEdit.view models.event
      |> wrapMsg EventEditMsg


pageNav : Router.Target -> Auth.Cred -> Models -> ( Models, Cmd Msg, OutMsg.Msg )
pageNav target creds models =
  case target of
    Router.Profile ->
      bidiupdate (ProfileMsg (Profile.Entered creds)) models
    Router.Events ->
      bidiupdate (EventsMsg (Events.Entered creds)) models
    Router.EventEdit name ->
      bidiupdate (EventEditMsg (EventEdit.Entered creds (EventEdit.Nickname name))) models
    _ -> ( models, Cmd.none, OutMsg.None )

bidiupdate : Msg -> Models -> ( Models, Cmd Msg, OutMsg.Msg )
bidiupdate msg models =
  case msg of
    LandingMsg _ -> ( models, Cmd.none, OutMsg.None )
    ProfileMsg submsg ->
      Profile.update submsg models.profile |> OutMsg.addNone
        |> OutMsg.mapBoth (\pm -> {models | profile = pm}) (Cmd.map ProfileMsg)
        |> consumeOutmsg
    LoginMsg submsg ->
      Login.bidiupdate submsg models.login
        |> OutMsg.mapBoth (\pm -> {models | login = pm}) (Cmd.map LoginMsg)
        |> consumeOutmsg
    EventsMsg submsg ->
      Events.bidiupdate submsg models.events
        |> OutMsg.mapBoth (\pm -> {models | events = pm}) (Cmd.map EventsMsg)
        |> consumeOutmsg
    EventEditMsg submsg ->
      EventEdit.bidiupdate submsg models.event
        |> OutMsg.mapBoth (\pm -> {models | event = pm}) (Cmd.map EventEditMsg)
        |> consumeOutmsg

consumeOutmsg : ( Models, Cmd Msg, OutMsg.Msg ) -> ( Models, Cmd Msg, OutMsg.Msg )
consumeOutmsg ( models, cmd, out ) =
  case out of
    OutMsg.Page (pagemsg) ->
      case pagemsg of
        OutMsg.CreateEvent aff ->
          ({models | event = EventEdit.forCreate aff}, cmd, OutMsg.Main << OutMsg.Nav <| Router.CreateEvent)
        OutMsg.EditEvent creds aff ->
          EventEdit.bidiupdate (EventEdit.Entered creds (EventEdit.Url aff)) EventEdit.init
            |> OutMsg.mapBoth (\pm -> {models | event = pm}) (Cmd.map EventEditMsg)
    _ -> (models, cmd, out)
