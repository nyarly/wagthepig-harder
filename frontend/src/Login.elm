module Login exposing (view, Msg(..), Model, init, bidiupdate)

import Html exposing (..)
import Html.Attributes exposing (id, for, type_)
import Html.Events exposing (onInput, onSubmit)
import Http
import Json.Encode as E

import OutMsg
import Auth
import Hypermedia as HM
import Hypermedia exposing (OperationSelector(..))
import Router exposing (Target(..))

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
  | AuthResponse (Result Http.Error Auth.Cred)

type AuthResponse
  = None
  | Success Auth.Cred
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

bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
  case msg of
    ChangeEmail newemail -> ( {model | email = newemail }, Cmd.none, OutMsg.None )
    ChangePassword newpassword -> ( {model | password = newpassword }, Cmd.none, OutMsg.None )
    AuthenticationAttempted ->
      ( {model | fromServer = None}
      , login model.email model.password
      , OutMsg.None
      )
    AuthResponse res ->
      case res of
        Ok user ->
          ({ model | fromServer = Success user }, Cmd.none, OutMsg.Main << OutMsg.NewCred <| user)
        Err err ->
          ({ model | fromServer = Failed err }, Cmd.none, OutMsg.None)

-- type alias ResToMsg x a msg = (Result x a -> msg)
login : String -> String -> Cmd Msg
login email password =
  let
      reqBody = (Http.jsonBody (
        E.object
        [ ( "email", E.string email )
        , ( "password", E.string password )
        ]))
  in
    HM.chain Auth.unauthenticated [
        HM.browse ["authenticate"] (ByType "LoginAction")
      ] reqBody (Auth.credExtractor email) AuthResponse
