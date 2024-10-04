module Landing exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)

import Router

type alias Model = { }

type Msg =
  ClickedSomething

view : Model -> List (Html Msg)
view _ =
  [
   h1 [] [ text "Welcome to Wag the Pig!" ]
   , div [ class "account" ]
     [ viewLink "Sign up" (Router.buildFromTarget Router.Register)
     , viewLink "Log In" (Router.buildFromTarget Router.Login)
   ]
  ]

viewLink : String -> String -> Html msg
viewLink txt  path =
  a [ href path ] [ text txt ]
