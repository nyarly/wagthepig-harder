module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Encode exposing (Value)
import Url
import Dict

import Auth
import Router
import Pages
import State
import OutMsg

type alias Model =
  { key : Nav.Key
  , url : Url.Url
  , page: Router.Target
  , pages: Pages.Models
  , creds: Auth.Cred
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
    baseModel = Model key finalUrl target Pages.init Auth.unauthenticated
    fromStore = State.loadAll flags
    model = Dict.foldl loadIntoModel baseModel fromStore
  in
    routeToPage url model
    |> consumeOutmsg


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
      |> consumeOutmsg

    StoreChange (key, value) ->
      ( loadIntoModel key value model, Cmd.none )

    SignOut -> ({model | creds = Auth.unauthenticated}, Auth.logout )

    PageMsg submsg ->
      Pages.bidiupdate submsg model.pages
      |> OutMsg.mapBoth (\pagemodel -> {model | pages = pagemodel}) (Cmd.map PageMsg)
      |> consumeOutmsg

consumeOutmsg : (Model, Cmd Msg, OutMsg.Msg) -> (Model, Cmd Msg)
consumeOutmsg (model, msg, out) =
  case out of
    OutMsg.Main(mymsg) ->
      case mymsg of
        OutMsg.Nav target -> (model, Cmd.batch [
          msg
          , Nav.pushUrl model.key (Router.buildFromTarget target)
          ])
        OutMsg.NewCred newcred target -> ({model | creds = newcred}, Cmd.batch [
          msg
          , Auth.storeCred newcred
          , Nav.pushUrl model.key (Router.buildFromTarget target)
          ])
    _ -> (model, msg)


loadIntoModel : String -> Value -> Model -> Model
loadIntoModel key value model =
  case State.asString value of
    Just s ->
      -- add an if clause for each storage field
      if key == Auth.storageField then
        { model | creds = Auth.loadCred s }
      else
        model
    Nothing -> model

routeToPage : Url.Url -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
routeToPage url model =
  case (Router.routeToTarget url) of
    Just target ->
      Pages.pageNav target model.creds model.pages
      |> OutMsg.mapBoth
        (\pagemodel -> { model | url = url , pages = pagemodel, page = target })
        (Cmd.map PageMsg)
    Nothing ->
      ( model, Nav.pushUrl model.key "/", OutMsg.None )

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
          a [ onClick (PathRequested (Router.buildFromTarget Router.Register)) ] [
            img [ src "/assets/wagthepig-med.png" ] []
          ]
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
  if (Auth.loggedIn model.creds) then
    li [] [ button [ class "header", onClick SignOut ] [ text "Sign Out" ] ]
  else
    headerButton "Log In" "/login"

headerButton : String -> String -> Html Msg
headerButton txt path =
  li [] [ button [ class "header", onClick (PathRequested path) ] [ text txt ] ]
