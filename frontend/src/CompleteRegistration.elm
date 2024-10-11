module CompleteRegistration exposing (view, Msg(..), Model, init, bidiupdate)

import Html exposing (..)
import Html.Extra as Html exposing (viewIf)
import Html.Attributes exposing (id, for, type_, class, disabled)
import Html.Attributes.Extra exposing (attributeIf)
import Html.Events exposing (onInput, onSubmit)
import Http
import Json.Encode as E

import OutMsg
import Auth
import Hypermedia as HM
import ViewUtil as Eww
import Hypermedia exposing (OperationSelector(..))
import Router exposing (Target(..))
import Dict

type alias Model =
  { creds: Auth.Cred
  , email: String
  , password: String
  , passwordAgain: String
  , fromServer: FromServer
  }

init : Model
init =
  Model Auth.unauthenticated "" "" "" None

type Msg
  = Entered Auth.Cred String
  | ChangePassword String
  | ChangePasswordAgain String
  | UpdateAttempted
  | AuthResponse (Result Http.Error ())

type FromServer
  = None
  | Success
  | Failed Http.Error -- XXX a 4xx response is only captured like that
  -- no body, so B/E can't tell the user anything
  -- consider https://package.elm-lang.org/packages/jzxhuang/http-extras/latest/Http-Detailed

view : Model -> List (Html Msg)
view model =
  let
      passwordsMismatch = (model.password /= model.passwordAgain)
      passwordInputAttrs = [ type_ "password", attributeIf passwordsMismatch (class "input-problem") ]
  in
  [ h1 [] [ text "Please enter your new password. It must be at least 12 characters long." ]
  , viewIf passwordsMismatch (span [ class "warning" ] [ text "Passwords have to match" ])
  , form [ onSubmit UpdateAttempted ]
    [ (Eww.inputPair passwordInputAttrs "Password" model.password ChangePassword)
    , (Eww.inputPair passwordInputAttrs "Password Again" model.passwordAgain ChangePasswordAgain)
    , button [type_ "submit", attributeIf passwordsMismatch (disabled True) ] [ text "Update Password" ]
    ]
  ]

bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
  case msg of
    Entered cred email -> ( {model | creds = cred, email = email }, Cmd.none, OutMsg.None )
    ChangePassword newpassword -> ( {model | password = newpassword }, Cmd.none, OutMsg.None )
    ChangePasswordAgain newpassword -> ( {model | passwordAgain = newpassword }, Cmd.none, OutMsg.None )
    UpdateAttempted ->
      ( {model | fromServer = None}
      , login model.creds model.email model.password
      , OutMsg.None
      )
    AuthResponse res ->
      case res of
        Ok () ->
          -- n.b. we could do the login ourselves, but I want to avoid a folk "magic-link" pattern here
          ({ model | fromServer = Success }, Cmd.none, (OutMsg.Main (OutMsg.Nav Router.Login)))
        Err err ->
          ({ model | fromServer = Failed err }, Cmd.none, OutMsg.None)

login : Auth.Cred -> String -> String -> Cmd Msg
login creds email password =
  let
      reqBody = (Http.jsonBody (
        E.object [ ( "password", E.string password ) ]
        ))
  in
    HM.chain creds [
        HM.browse ["authenticate"] (ByType "UpdateAction") |> HM.fillIn (Dict.fromList [("user_id", email)])
      ] reqBody emptyResponse AuthResponse

emptyResponse : HM.Response -> Result String ()
emptyResponse rx =
  if rx.status >= 200 && rx.status < 300 then
    Ok(())
  else
    Err(rx.body)
