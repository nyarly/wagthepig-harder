module Pages exposing (Msg(..), Models, init, view, update)

import Html exposing (Html)

import Router
import Api

import Landing
import Login
import Profile

type Msg
  = Routed (Router.Target, Api.Cred)
  | LandingMsg Landing.Msg
  | LoginMsg Login.Msg
  | ProfileMsg Profile.Msg

type alias Models =
  { landing: Landing.Model
  , login: Login.Model
  , profile: Profile.Model
  }

init : Api.Cred -> (Models, Cmd Msg)
init cred =
  let
      (profilemodel, profilecmd) = Profile.init cred
  in
    (Models
      Landing.Model
      Login.init
      profilemodel
      , Cmd.batch [
        Cmd.map ProfileMsg profilecmd
      ])

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


update : Msg -> Models -> ( Models, Cmd Msg )
update msg models =
  let
      dispatch submsg updateFn pmodel toModel toMsg =
        let
            (pagemodel, cmd) = updateFn submsg pmodel
        in
        ((toModel pagemodel), Cmd.map toMsg cmd)
  in
  case msg of
    ProfileMsg submsg ->
      dispatch submsg Profile.update models.profile (\pm -> {models | profile = pm}) ProfileMsg
    LoginMsg submsg ->
      dispatch submsg Login.update models.login (\pm -> {models | login = pm}) LoginMsg
    LandingMsg _ -> ( models, Cmd.none )
    Routed (Router.Profile, creds) ->
      dispatch (Profile.Entered creds) Profile.update models.profile (\pm -> {models | profile = pm}) ProfileMsg
    Routed _ -> ( models, Cmd.none )
