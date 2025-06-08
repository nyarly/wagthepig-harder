module Login exposing (Model, Msg(..), init, logout, nextPageUpdater, updaters, view)

import Auth
import Dict
import Html exposing (..)
import Html.Attributes exposing (type_)
import Html.Events exposing (onClick, onSubmit)
import Http
import Hypermedia as HM exposing (OperationSelector(..), emptyBody, emptyResponse)
import Json.Encode as E
import Router exposing (Target(..))
import Updaters exposing (UpdateList, Updater)
import ViewUtil as Eww


type alias Model =
    { email : String
    , password : String
    , fromServer : AuthResponse
    , nextPage : Router.Target
    }


init : Model
init =
    Model "" "" None Router.Landing


type Msg
    = Entered
    | ChangeEmail String
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


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , requestNav : Router.Target -> Updater model msg
        , installNewCred : Auth.Cred -> Updater model msg
        , lowerModel : model -> Model
    }


nextPageUpdater :
    { iface
        | localUpdate : Updater Model Msg -> Updater model msg
    }
    -> Router.Target
    -> Updater model msg
nextPageUpdater { localUpdate } target =
    localUpdate (\m -> ( { m | nextPage = target }, Cmd.none ))


updaters : Interface base model msg -> Msg -> UpdateList model msg
updaters { localUpdate, installNewCred, requestNav, lowerModel } msg =
    case msg of
        Entered ->
            []

        ChangeEmail newemail ->
            [ localUpdate (\m -> ( { m | email = newemail }, Cmd.none )) ]

        ChangePassword newpassword ->
            [ localUpdate (\m -> ( { m | password = newpassword }, Cmd.none )) ]

        AuthenticationAttempted ->
            [ localUpdate (\m -> ( { m | fromServer = None }, login m.email m.password )) ]

        AuthResponse res ->
            case res of
                Ok user ->
                    [ localUpdate (\m -> ( { m | fromServer = Success user, password = "" }, Cmd.none ))
                    , installNewCred user
                    , \m -> requestNav (lowerModel m).nextPage m
                    ]

                -- XXX error handling
                Err err ->
                    [ localUpdate (\m -> ( { m | fromServer = Failed err, password = "" }, Cmd.none )) ]

        WantsReg ->
            [ requestNav Router.Register ]

        LoggedOut _ ->
            [ localUpdate (\m -> ( m, Auth.logout )) ]


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
