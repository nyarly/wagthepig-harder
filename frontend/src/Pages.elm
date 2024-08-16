module Pages exposing (Msg(..), Models, init, view, update)

import Html exposing (Html)

import Router
import Api

import Landing
import Login
import Profile
import Events

type Msg
  = Routed (Router.Target, Api.Cred)
  | LandingMsg Landing.Msg
  | LoginMsg Login.Msg
  | ProfileMsg Profile.Msg
  | EventsMsg Events.Msg

type alias Models =
  { landing: Landing.Model
  , login: Login.Model
  , profile: Profile.Model
  , events: Events.Model
  }

init : Models
init =
  Models
    Landing.Model
    Login.init
    Profile.init
    Events.init

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


update : Msg -> Models -> ( Models, Cmd Msg )
update msg models =
  case msg of
    ProfileMsg submsg ->
      Profile.update submsg models.profile |> Tuple.mapBoth (\pm -> {models | profile = pm}) (Cmd.map ProfileMsg)
    LoginMsg submsg ->
      Login.update submsg models.login |> Tuple.mapBoth (\pm -> {models | login = pm}) (Cmd.map LoginMsg)
    EventsMsg submsg ->
      Events.update submsg models.events |> Tuple.mapBoth (\pm -> {models | events = pm}) (Cmd.map EventsMsg)
    LandingMsg _ -> ( models, Cmd.none )
    Routed (Router.Profile, creds) ->
      update (ProfileMsg (Profile.Entered creds)) models
    Routed (Router.Events, creds) ->
      update (EventsMsg (Events.Entered creds)) models
    Routed _ -> ( models, Cmd.none )
