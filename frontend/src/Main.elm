module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Encode exposing (Value)
import Url
import Dict

import Api
import Router
import Pages
import State

import User

import Login


type alias Model =
  { key : Nav.Key
  , url : Url.Url
  , user: Maybe User.User
  , page: Router.Target
  , pages: Pages.Models
  , creds: Api.Cred
  }

type Msg
  = LinkClicked Browser.UrlRequest
  | PathRequested String
  | UrlChanged Url.Url
  | SignOut
  | StoreChange (String, Value)
  | PageMsg Pages.Msg

main : Program Value Model Msg
main =
  Browser.application
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    , onUrlChange = UrlChanged
    , onUrlRequest = LinkClicked
    }

init : Value -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
  let
    startingPage = Router.routeToTarget url
    (finalUrl, target) = case startingPage of
      Just t -> (url, t)
      Nothing -> ({ url | path = "/" }, Router.Landing)
    baseModel = Model key finalUrl Nothing target Pages.init Api.unauthenticated
    fromStore = State.loadAll flags
    model = Dict.foldl loadIntoModel baseModel fromStore
  in
    routeToPage url model


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    LinkClicked urlRequest ->
      case urlRequest of
        Browser.Internal url ->
          ( model, Nav.pushUrl model.key (Url.toString url) )

        Browser.External href ->
          ( model, Nav.load href )

    PathRequested path ->
      ( model, Nav.pushUrl model.key path )

    UrlChanged url ->
      routeToPage url model

    StoreChange (key, value) ->
      ( loadIntoModel key value model, Cmd.none )

    SignOut -> ({model | creds = Api.unauthenticated}, Api.logout )

    PageMsg submsg ->
      let
        (pagemodel, cmd) = Pages.update submsg model.pages
        newmodel = {model | pages = pagemodel}
        default _ = (newmodel, Cmd.map PageMsg cmd)
      in
        case submsg of
          Pages.LoginMsg (Login.AuthResponse (Ok newcred)) -> (
            {newmodel | creds = newcred},
            Cmd.batch [
              Api.storeCred newcred
              , Nav.pushUrl model.key "/"
              ])

          _ -> default ()

loadIntoModel : String -> Value -> Model -> Model
loadIntoModel key value model =
  case State.asString value of
    Just s ->
      -- add an if clause for each storage field
      if key == Api.storageField then
        { model | creds = Api.loadCred s }
      else
        model
    Nothing -> model

routeToPage : Url.Url -> Model -> ( Model, Cmd Msg )
routeToPage url model =
  case (Router.routeToTarget url) of
    Just target ->
      let
        (pagemodel, pagecmd) = Pages.update (Pages.Routed (target, model.creds) ) model.pages
        newmodel = { model | url = url , pages = pagemodel, page = target }
      in
        (newmodel, Cmd.map PageMsg pagecmd)
    Nothing ->
      ( model, Nav.pushUrl model.key "/" )

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions _ =
  State.onStoreChange StoreChange

-- VIEW

view : Model -> Browser.Document Msg
view model =
  { title = "Wag The Pig"
  , body = [
      div [ class "page", class (Router.pageName model.page) ] (
        nav [] [
          img [ src "/assets/wagthepig-med.png" ] []
          , ul [ class "menu" ] [
              headerButton "Profile" "/profile"
            , headerButton "Events" "/events"
            , authButton model
          ]
        ] :: Pages.view model.page model.pages PageMsg ++ [
          div [ class "footer" ] [
            a [ href "https://github.com/nyarly/wagthepig" ] [ text "Contribute!" ]
          , a [ href "https://github.com/nyarly/wagthepig/issues" ] [ s [] [text "Complain!"], text "Suggest!" ]
          ]
        ])
    ]
  }

authButton : Model -> Html Msg
authButton model =
  if (Api.loggedIn model.creds) then
    li [] [ button [ class "header", onClick SignOut ] [ text "Sign Out" ] ]
  else
    headerButton "Log In" "/login"

headerButton : String -> String -> Html Msg
headerButton txt path =
  li [] [ button [ class "header", onClick (PathRequested path) ] [ text txt ] ]
