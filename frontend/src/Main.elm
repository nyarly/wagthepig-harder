module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Url
import Landing

main : Program () Model Msg
main =
  Browser.application
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    , onUrlChange = UrlChanged
    , onUrlRequest = LinkClicked
    }

type alias Model =
  { key : Nav.Key
  , url : Url.Url
  , page: Page
  , landing: Landing.Model
  }

init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
  ( Model key url Landing (Landing.Model), Cmd.none )

type Page =
  Landing

type Msg
  = LinkClicked Browser.UrlRequest
  | PathRequested String
  | UrlChanged Url.Url
  | LandingMsg Landing.Msg

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
      ( { model | url = url }
      , Cmd.none
      )

    LandingMsg _ -> ( model, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
  Sub.none



-- VIEW


view : Model -> Browser.Document Msg
view model =
  { title = "Wag The Pig"
  , body = [
      div [ class "page", class (pageName model) ] ([

        nav [] [
          img [ src "/assets/wagthepig-med.png" ] []
          , ul [ class "menu" ] [
            headerButton "Profile" "/profile"
            , headerButton "Events" "/events"
            , headerButton "Sign out" "/sign-out"
          ]
        ]
      ] ++ renderPage model)
    ]
  }



pageName : Model -> String
pageName model =
  case model.page of
    Landing -> "landing"

renderPage model =
  case model.page of
    Landing -> List.map (Html.map (\lm -> LandingMsg lm)) (Landing.view model.landing) -- but consider how pages share information

headerButton : String -> String -> Html Msg
headerButton txt path =
  li [] [ button [ class "header", href path, onClick (PathRequested path) ] [ text txt ] ]
