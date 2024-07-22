module Landing exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Url

type alias Model = { }

type Msg =
  ClickedSomething

view : Model -> List (Html Msg)
view model =
  [
   h1 [] [ text "Welcome to Wag the Pig!" ]
   , div [ class "account" ] [
      viewLink "Sign up" "/sign-up"
     , viewLink "Log In" "/log-in"
   ]
  ]

viewLink : String -> String -> Html msg
viewLink txt  path =
  a [ href path ] [ text txt ]
