module CompleteRegistration exposing (FromServer, Interface, Model, Msg(..), init, updaters, view)

import Auth
import Dict
import Html exposing (Html, form, h1, span, text)
import Html.Attributes exposing (class, type_)
import Html.Attributes.Extra exposing (attributeIf)
import Html.Events exposing (onSubmit)
import Html.Extra exposing (viewIf)
import Http
import Hypermedia as HM exposing (OperationSelector(..))
import Json.Encode as E
import LinkFollowing as HM
import Router
import Updaters exposing (Updater)
import ViewUtil as Eww


type alias Model =
    { creds : Auth.Cred
    , email : String
    , password : String
    , passwordAgain : String
    , fromServer : FromServer
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
    | Failed -- XXX a 4xx response is only captured like that



-- no body, so B/E can't tell the user anything
-- consider https://package.elm-lang.org/packages/jzxhuang/http-extras/latest/Http-Detailed


view : Model -> List (Html Msg)
view model =
    let
        passwordsMatch : Bool
        passwordsMatch =
            model.password == model.passwordAgain

        passwordInputAttrs : List (Html.Attribute msg)
        passwordInputAttrs =
            [ type_ "password", attributeIf (not passwordsMatch) (class "input-problem") ]
    in
    [ h1 [] [ text "Please enter your new password. It must be at least 12 characters long." ]
    , viewIf (not passwordsMatch) (span [ class "warning" ] [ text "Passwords have to match" ])
    , form [ onSubmit UpdateAttempted ]
        [ Eww.inputPair passwordInputAttrs "Password" model.password ChangePassword
        , Eww.inputPair passwordInputAttrs "Password Again" model.passwordAgain ChangePasswordAgain
        , Eww.maybeSubmit passwordsMatch "Update Password"
        ]
    ]


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , requestNav : Router.Target -> Updater model msg
    }


updaters : Interface base model msg -> Msg -> Updater model msg
updaters { localUpdate, requestNav } msg =
    case msg of
        Entered cred email ->
            localUpdate (\m -> ( { m | creds = cred, email = email }, Cmd.none ))

        ChangePassword newpassword ->
            localUpdate (\m -> ( { m | password = newpassword }, Cmd.none ))

        ChangePasswordAgain newpassword ->
            localUpdate (\m -> ( { m | passwordAgain = newpassword }, Cmd.none ))

        UpdateAttempted ->
            localUpdate (\m -> ( { m | fromServer = None }, updatePassword m.creds m.email m.password ))

        AuthResponse res ->
            case res of
                Ok () ->
                    -- n.b. we could do the login ourselves, but I want to avoid a folk "magic-link" pattern here
                    Updaters.compose (localUpdate (\m -> ( { m | fromServer = Success }, Cmd.none )))
                        (requestNav Router.Login)

                Err _ ->
                    localUpdate (\m -> ( { m | fromServer = Failed }, Cmd.none ))


updatePassword : Auth.Cred -> String -> String -> Cmd Msg
updatePassword creds email password =
    let
        reqBody : Http.Body
        reqBody =
            Http.jsonBody
                (E.object [ ( "new_password", E.string password ) ])
    in
    HM.chain
        [ HM.browse [ "authenticate" ] (ByType "UpdateAction") |> HM.fillIn (Dict.fromList [ ( "user_id", email ) ])
        ]
        (Auth.credHeader creds)
        reqBody
        emptyResponse
        AuthResponse


emptyResponse : HM.Response -> Result String ()
emptyResponse rx =
    if rx.status >= 200 && rx.status < 300 then
        Ok ()

    else
        Err rx.body
