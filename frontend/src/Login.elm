module Login exposing (view, Msg(..), Model, init, update)

import Html exposing (..)
import Html.Attributes exposing (id, for, type_)
import Html.Events exposing (onInput, onSubmit)
import Http

import Api

type alias Model =
  { email: String
  , password: String
  , fromServer: AuthResponse
  }

init : Model
init =
  Model "" "" None

type Msg
  = ChangeEmail String
  | ChangePassword String
  | AuthenticationAttempted
  | AuthResponse (Result Http.Error Api.Cred)

type AuthResponse
  = None
  | Success Api.Cred
  | Failed Http.Error

view : Model -> List (Html Msg)
view _ =
  [ h1 [] [ text "Log in" ]
  , form [ onSubmit AuthenticationAttempted ]
    [ (inputPair "Email" [] ChangeEmail)
    , (inputPair "Password" [ type_ "password" ] ChangePassword)
    , button [ type_ "submit" ] [ text "Log in" ]
    ]
  ]

inputPair : String -> List (Attribute msg) -> (String -> msg) -> Html msg
inputPair name attrs event =
  let
      pid = String.toLower name
  in
    div []
    [ label [ for pid ] [ text name ]
    , input ([ id pid, onInput event ] ++ attrs) []
    ]

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    ChangeEmail newemail -> ( {model | email = newemail }, Cmd.none )
    ChangePassword newpassword -> ( {model | password = newpassword }, Cmd.none )
    AuthenticationAttempted ->
      ( {model | fromServer = None}
      , Api.login model.email model.password AuthResponse
      )
    AuthResponse res ->
      case res of
        Ok user ->
          ({ model | fromServer = Success user }, Cmd.none)
        Err err ->
          ({ model | fromServer = Failed err }, Cmd.none)
