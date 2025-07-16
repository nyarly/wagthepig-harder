module Landing exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Router


type alias Model =
    {}


type Msg
    = ClickedSomething
    | Entered


view : Model -> List (Html Msg)
view _ =
    [ h1 [] [ text "Welcome to Wag the Pig!" ]
    , p [] [ text """
    Let's speed up the "What are we going to play?" game, so that we can get to playing
    the games we want to be playing!
    """ ]
    , p [] [ text """
    Wag the Pig let's you describe a gaming event (a convention, for instance),
    and then add games that you're interested in playing. If you see games other folks have
    listed that appeal to you, mark that you're interested in playing them. You can also
    indicate that you know a game well enough to teach the rules.
    """ ]
    , p [] [ text """
    When the time comes, you can click the "what should we play?" button, and you'll
    get a list of games that have space for your current group, sorted by how many of you
    are interested in playing them. Pick the first one, or scroll down if you're second guessing,
    or collecting stuff from a game library to play in a batch.
    """ ]
    , p [] [ text """
    So, get started thinking about what you want to play now, so that when you can get playing faster, then!
    """ ]
    , div [ class "account" ]
        [ viewLink "Sign up" Router.Register
        , viewLink "Log In" Router.Login
        ]
    ]


viewLink : String -> Router.Target -> Html msg
viewLink txt path =
    a [ class "button", href (Router.buildFromTarget path) ] [ text txt ]
