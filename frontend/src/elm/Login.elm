module Login exposing (Model, Msg(..), Toast, init, logout, nextPageUpdater, updaters, view, viewToast)

import Auth
import Dict
import Html exposing (Html, a, button, div, form, h1, p, text)
import Html.Attributes exposing (class, type_)
import Html.Events exposing (onClick, onSubmit)
import Http exposing (Error(..))
import Hypermedia as HM exposing (OperationSelector(..), emptyBody, emptyResponse)
import Json.Encode as E
import LinkFollowing as HM
import Router exposing (Target(..))
import Toast
import Updaters exposing (Updater)
import ViewUtil as Eww


type alias Model =
    { email : String
    , password : String
    , fromServer : AuthResponse
    , nextPage : Router.Target
    }


init : Model
init =
    Model "" "" None (Router.Events Nothing)


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
    | Failed


type Toast
    = NotAuthorized


view : Model -> List (Html Msg)
view model =
    [ h1 [] [ text "Log in" ]
    , form [ onSubmit AuthenticationAttempted ]
        [ Eww.inputPair [] "Email" model.email ChangeEmail
        , Eww.inputPair [ type_ "password" ] "Password" model.password ChangePassword
        , button [ type_ "submit" ] [ text "Log in" ]
        ]
    , div [ class "need-reg" ]
        [ p [ class "need-reg" ]
            [ text "Don't have an account? No problem!" ]
        , a [ class "button", onClick WantsReg ] [ text "Sign up here" ]
        ]
    ]


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , requestNav : Router.Target -> Updater model msg
        , installNewCred : Auth.Cred -> Updater model msg
        , lowerModel : model -> Model
        , handleError : Error -> Updater model msg
        , sendToast : Toast -> Updater model msg
    }


nextPageUpdater :
    { iface
        | localUpdate : Updater Model Msg -> Updater model msg
    }
    -> Router.Target
    -> Updater model msg
nextPageUpdater { localUpdate } target =
    localUpdate (\m -> ( { m | nextPage = target }, Cmd.none ))


updaters : Interface base model msg -> Msg -> Updater model msg
updaters ({ localUpdate, installNewCred, requestNav, lowerModel, handleError } as iface) msg =
    case msg of
        Entered ->
            Updaters.noChange

        ChangeEmail newemail ->
            localUpdate (\m -> ( { m | email = newemail }, Cmd.none ))

        ChangePassword newpassword ->
            localUpdate (\m -> ( { m | password = newpassword }, Cmd.none ))

        AuthenticationAttempted ->
            localUpdate (\m -> ( { m | fromServer = None }, login m.email m.password ))

        AuthResponse res ->
            case res of
                Ok user ->
                    Updaters.composeList
                        [ localUpdate (\m -> ( { m | fromServer = Success user, password = "" }, Cmd.none ))
                        , installNewCred user
                        , \m -> requestNav (lowerModel m).nextPage m
                        ]

                Err err ->
                    Updaters.compose
                        (localUpdate (\m -> ( { m | fromServer = Failed, password = "" }, Cmd.none )))
                        (handleServerError iface err)

        WantsReg ->
            requestNav Router.Register

        LoggedOut res ->
            case res of
                Ok () ->
                    localUpdate (\m -> ( m, Auth.logout ))

                Err err ->
                    Updaters.compose
                        (localUpdate (\m -> ( m, Auth.logout )))
                        (handleError err)


handleServerError :
    { iface
        | handleError : Error -> Updater model msg
        , sendToast : Toast -> Updater model msg
    }
    -> Error
    -> Updater model msg
handleServerError { handleError, sendToast } err =
    case err of
        BadStatus status ->
            case status of
                401 ->
                    sendToast NotAuthorized

                403 ->
                    sendToast NotAuthorized

                _ ->
                    handleError err

        _ ->
            handleError err


viewToast : Toast.Info Toast -> List (Html Msg)
viewToast toastInfo =
    case toastInfo.content of
        NotAuthorized ->
            [ p [] [ text "User name or password not recognized - please, try again" ] ]


login : String -> String -> Cmd Msg
login email password =
    let
        reqBody : Http.Body
        reqBody =
            Http.jsonBody
                (E.object
                    [ ( "email", E.string email )
                    , ( "password", E.string password )
                    ]
                )
    in
    HM.chain
        [ HM.browse [ "authenticate" ] (ByType "LoginAction") |> HM.fillIn (Dict.fromList [ ( "user_id", email ) ])
        ]
        []
        reqBody
        (Auth.credExtractor email)
        AuthResponse


logout : Auth.Cred -> Cmd Msg
logout cred =
    HM.chain
        [ HM.browse [ "authenticate" ] (ByType "LogoutAction") |> HM.fillIn (Dict.fromList [ ( "user_id", Auth.accountID cred ) ])
        ]
        (Auth.credHeader cred)
        emptyBody
        emptyResponse
        LoggedOut
