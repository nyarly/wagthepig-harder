module Login exposing (Model, Msg(..), bidiupdate, init, logout, view)

import Auth
import Dict
import Html exposing (..)
import Html.Attributes exposing (type_)
import Html.Events exposing (onClick, onSubmit)
import Http
import Hypermedia as HM exposing (OperationSelector(..), emptyBody, emptyResponse)
import Json.Encode as E
import OutMsg
import Router exposing (Target(..))
import ViewUtil as Eww


type alias Model =
    { email : String
    , password : String
    , fromServer : AuthResponse
    }


init : Model
init =
    Model "" "" None


type Msg
    = ChangeEmail String
    | ChangePassword String
    | AuthenticationAttempted
    | AuthResponse (Result Http.Error Auth.Cred)
    | WantsReg
    | LoggedOut (Result Http.Error ())


type AuthResponse
    = None
    | Success Auth.Cred
    | Failed Http.Error


view : Model -> List (Html Msg)
view model =
    [ h1 [] [ text "Log in" ]
    , form [ onSubmit AuthenticationAttempted ]
        [ Eww.inputPair [] "Email" model.email ChangeEmail
        , Eww.inputPair [ type_ "password" ] "Password" model.password ChangePassword
        , button [ type_ "submit" ] [ text "Log in" ]
        ]
    , p []
        [ text "Don't have an account? No problem!"
        , a [ onClick WantsReg ] [ text "Sign up here" ]
        ]
    ]


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    case msg of
        ChangeEmail newemail ->
            ( { model | email = newemail }, Cmd.none, OutMsg.None )

        ChangePassword newpassword ->
            ( { model | password = newpassword }, Cmd.none, OutMsg.None )

        AuthenticationAttempted ->
            ( { model | fromServer = None }
            , login model.email model.password
            , OutMsg.None
            )

        AuthResponse res ->
            case res of
                Ok user ->
                    ( { model | fromServer = Success user, password = "" }, Cmd.none, OutMsg.Main (OutMsg.NewCred user Router.Landing) )

                Err err ->
                    ( { model | fromServer = Failed err, password = "" }, Cmd.none, OutMsg.None )

        WantsReg ->
            ( model, Cmd.none, OutMsg.Main (OutMsg.Nav Router.Register) )

        LoggedOut _ ->
            ( model, Auth.logout, OutMsg.None )



-- type alias ResToMsg x a msg = (Result x a -> msg)


login : String -> String -> Cmd Msg
login email password =
    let
        reqBody =
            Http.jsonBody
                (E.object
                    [ ( "email", E.string email )
                    , ( "password", E.string password )
                    ]
                )
    in
    HM.chain Auth.unauthenticated
        [ HM.browse [ "authenticate" ] (ByType "LoginAction") |> HM.fillIn (Dict.fromList [ ( "user_id", email ) ])
        ]
        []
        reqBody
        (Auth.credExtractor email)
        AuthResponse


logout : Auth.Cred -> Cmd Msg
logout cred =
    HM.chain cred
        [ HM.browse [ "authenticate" ] (ByType "LogoutAction") |> HM.fillIn (Dict.fromList [ ( "user_id", Auth.accountID cred ) ])
        ]
        []
        emptyBody
        emptyResponse
        LoggedOut
