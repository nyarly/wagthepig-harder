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
    fromStore = Debug.log "State.loadAll" (State.loadAll flags)
      |> Result.toMaybe -- XXX ewwww
    loadedCred = fromStore
      |> Maybe.andThen (Dict.get Api.storageField)
      |> Maybe.andThen State.asString
      |> Debug.log "loaded 'credentials'"
      |> Maybe.andThen Api.loadCred
      |> Debug.log "api.loadCred"
    (pagesModel, pagesCmd) = Pages.init loadedCred
  in
    case (Router.routeToTarget url) of
      Just target ->
        ( Model key url Nothing target pagesModel loadedCred, Cmd.map PageMsg pagesCmd )
      Nothing ->
        ( Model key { url | path = "/" } Nothing Router.Landing pagesModel loadedCred, Cmd.map PageMsg pagesCmd )

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
      case (Router.routeToTarget url) of
        Just target ->
          let
            (pagemodel, pagecmd) = Pages.update (Pages.Routed (target, model.creds) ) model.pages
            newmodel = { model | url = url , pages = pagemodel, page = target }
          in
            (newmodel, Cmd.map PageMsg pagecmd)
        Nothing ->
          ( model, Nav.pushUrl model.key "/" )

    StoreChange (key, value) ->
      if key == Api.storageField then
        case State.asString value of
          Just s -> ({model | creds = Api.loadCred s} , Cmd.none )
          Nothing -> (model, Cmd.none)
      else
        (model , Cmd.none)

    SignOut -> ({model | creds = Nothing}, Api.logout )

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
        a [ href "https://github.com/nyarly/wagthepig" ] [ text "Contribute!" ]
        , a [ href "https://github.com/nyarly/wagthepig/issues" ] [ s [] [text "Complain!"], text "Suggest!" ]
        ])
    ]
  }

authButton : Model -> Html Msg
authButton model =
  case model.creds of
    Just _ ->
      li [] [ button [ class "header", onClick SignOut ] [ text "Sign Out" ] ]
    Nothing ->
      headerButton "Log In" "/login"

headerButton : String -> String -> Html Msg
headerButton txt path =
  li [] [ button [ class "header", onClick (PathRequested path) ] [ text txt ] ]
