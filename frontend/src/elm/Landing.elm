module Landing exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Router
import ViewUtil exposing (viewLink)


type alias Model =
    {}


type Msg
    = ClickedSomething


view : Model -> List (Html Msg)
view _ =
    [ h1 [] [ text "Welcome to Wag the Pig!" ]
    , div [ class "account" ]
        [ viewLink "Sign up" Router.Register
        , viewLink "Log In" Router.Login
        ]
    ]
