module Profile exposing
    ( Bookmark(..)
    , Model
    , Msg(..)
    , Toast
    , init
    , updaters
    , view
    , viewToast
    )

import Auth
import Dict
import Html exposing (Html, button, form, p, span, text)
import Html.Attributes exposing (class, disabled, type_)
import Html.Attributes.Extra exposing (attributeIf, attributeMaybe)
import Html.Events exposing (onSubmit)
import Html.Extra exposing (viewIf)
import Http exposing (Error)
import Hypermedia as HM exposing (Affordance, OperationSelector(..), emptyResponse)
import LinkFollowing as HM
import Json.Decode as D
import Json.Encode as E
import ResourceUpdate as Up exposing (apiRoot, resultDispatch)
import Router
import String exposing (length)
import Toast
import Updaters exposing (Updater)
import ViewUtil as Eww


type Bookmark
    = Creds
    | Url Affordance


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag
    , profile : Profile
    , password : Password
    }


type alias Profile =
    { name : String
    , email : String
    , bgg_username : String
    , update : Maybe Affordance
    , template : Maybe Affordance
    }


type alias Password =
    { old : String
    , new : String
    , newAgain : String
    }


init : Model
init =
    Model
        Auth.unauthenticated
        Nothing
        (Profile "" "" "" Nothing Nothing)
        (Password "" "" "")


encode : Profile -> E.Value
encode profile =
    E.object
        [ ( "name", E.string profile.name )
        , ( "email", E.string profile.email )
        , ( "bgg_username", E.string profile.bgg_username )
        ]


decoder : D.Decoder Profile
decoder =
    D.map5 Profile
        (D.field "name" D.string)
        (D.field "email" D.string)
        (D.field "bgg_username" D.string)
        (D.map (\laff -> HM.selectAffordance (ByType "UpdateAction") laff) HM.affordanceListDecoder)
        (D.map (\laff -> HM.selectAffordance (ByType "ViewAction") laff) HM.affordanceListDecoder)


type Msg
    = Entered Auth.Cred Bookmark
    | ChangeEmail String
    | ChangeName String
    | ChangeBGG String
    | SubmitProfile
    | GotProfile Up.Etag Profile
    | ErrProfileGet Http.Error
    | ChangeOldPassword String
    | ChangeNewPassword String
    | ChangeNewPasswordAgain String
    | SubmitPassword
    | AuthResponse (Result Http.Error ())


type Toast
    = Unknown


view : Model -> List (Html Msg)
view model =
    let
        passwordsMatch =
            model.password.new == model.password.newAgain

        passwordEmpty =
            length model.password.new == 0

        passwordLongEnough =
            length model.password.new >= 12

        passwordInputAttrs =
            [ type_ "password", attributeIf (not passwordsMatch) (class "input-problem") ]
    in
    [ form [ onSubmit SubmitProfile ]
        [ Eww.inputPair [] "Name" model.profile.name ChangeName
        , Eww.inputPair [] "Email" model.profile.email ChangeEmail
        , Eww.inputPair [] "BGG Username" model.profile.bgg_username ChangeBGG
        , button [ attributeMaybe (\_ -> disabled True) model.profile.update ] [ text "Update Profile" ]
        ]
    , form [ onSubmit SubmitPassword ]
        [ Eww.inputPair [ type_ "password" ] "Old Password" model.password.old ChangeOldPassword
        , Eww.inputPair passwordInputAttrs "New Password" model.password.new ChangeNewPassword
        , Eww.inputPair passwordInputAttrs "New Password Again" model.password.newAgain ChangeNewPasswordAgain
        , Eww.maybeSubmit (passwordsMatch && passwordLongEnough) "Update Password"
        , viewIf (not passwordsMatch) (span [ class "warning" ] [ text "Passwords have to match" ])
        , viewIf (not (passwordEmpty || passwordLongEnough)) (span [ class "warning" ] [ text "Password has to be at least 12 characters long" ])
        ]
    ]


viewToast : Toast.Info Toast -> List (Html Msg)
viewToast toastInfo =
    case toastInfo.content of
        Unknown ->
            [ p [] [ text "there was a problem updating your password; try again, please?" ] ]


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , requestNav : Router.Target -> Updater model msg
        , handleError : Error -> Updater model msg
        , sendToast : Toast -> Updater model msg
    }


updaters : Interface base model msg -> Msg -> Updater model msg
updaters { localUpdate, requestNav, handleError, sendToast } msg =
    let
        updateProfile f =
            localUpdate (\m -> ( { m | profile = f m.profile }, Cmd.none ))

        updatePassword f =
            localUpdate (\m -> ( { m | password = f m.password }, Cmd.none ))
    in
    case msg of
        Entered creds loc ->
            case loc of
                Creds ->
                    localUpdate (\m -> ( { m | creds = creds }, fetchByCreds creds ))

                Url url ->
                    localUpdate (\m -> ( { m | creds = creds }, fetchFromUrl creds url.uri ))

        ChangeName n ->
            updateProfile (\pf -> { pf | name = n })

        ChangeEmail e ->
            updateProfile (\pf -> { pf | email = e })

        ChangeBGG b ->
            updateProfile (\pf -> { pf | bgg_username = b })

        SubmitProfile ->
            localUpdate (\m -> ( m, putProfile m.creds m ))

        GotProfile etag prof ->
            localUpdate (\m -> ( { m | etag = etag, profile = prof }, Cmd.none ))

        ErrProfileGet err ->
            handleError err

        ChangeOldPassword p ->
            updatePassword (\pw -> { pw | old = p })

        ChangeNewPassword p ->
            updatePassword (\pw -> { pw | new = p })

        ChangeNewPasswordAgain p ->
            updatePassword (\pw -> { pw | newAgain = p })

        SubmitPassword ->
            localUpdate (\m -> ( m, submitPasswordUpdate m ))

        AuthResponse res ->
            case res of
                Ok () ->
                    requestNav Router.Login

                Err _ ->
                    sendToast Unknown


submitPasswordUpdate : Model -> Cmd Msg
submitPasswordUpdate model =
    let
        email =
            model.profile.email

        password =
            model.password

        reqBody =
            Http.jsonBody
                (E.object
                    [ ( "old_password", E.string password.old )
                    , ( "new_password", E.string password.new )
                    ]
                )
    in
    HM.chain
        [ HM.browse [ "authenticate" ] (ByType "UpdateAction") |> HM.fillIn (Dict.fromList [ ( "user_id", email ) ])
        ]
        (Auth.credHeader model.creds)
        reqBody
        emptyResponse
        AuthResponse


nickToVars : String -> Dict.Dict String String
nickToVars nick =
    Dict.fromList [ ( "user_id", nick ) ]


browseToProfile : HM.TemplateVars -> List (HM.Response -> Result String Affordance)
browseToProfile vars =
    [ HM.browse [ "profile" ] (ByType "FindAction") |> HM.fillIn vars ]


putProfile : Auth.Cred -> Model -> Cmd Msg
putProfile creds model =
    --Up.put encode decoder (makeMsg creds) creds model.etag model.profile
    --put encode decoder makeMsg cred etag resource =
    case model.profile.update of
        Just aff ->
            Up.update
                { resource = model.profile -- s
                , etag = Just model.etag -- Maybe Etag
                , encode = encode -- s -> E.Value
                , decoder = decoder -- D.Decoder r
                , resMsg = resultDispatch ErrProfileGet (\( etag, ps ) -> GotProfile etag ps)
                , startAt = aff
                , browsePlan = [] -- List AffordanceExtractor
                , headers = Auth.credHeader creds -- Auth.Cred
                }

        Nothing ->
            Cmd.none


fetchByCreds : Auth.Cred -> Cmd Msg
fetchByCreds creds =
    --Up.fetchByNick decoder (makeMsg creds) nickToVars browseToProfile creds (Auth.accountID creds)
    Up.retrieve
        { headers = Auth.credHeader creds
        , decoder = decoder
        , resMsg = resultDispatch ErrProfileGet (\( etag, ps ) -> GotProfile etag ps)
        , startAt = apiRoot
        , browsePlan = browseToProfile (nickToVars (Auth.accountID creds))
        }


fetchFromUrl : Auth.Cred -> HM.Uri -> Cmd Msg
fetchFromUrl creds url =
    Up.retrieve
        { headers = Auth.credHeader creds
        , decoder = decoder
        , resMsg = resultDispatch ErrProfileGet (\( etag, ps ) -> GotProfile etag ps)
        , startAt = HM.link HM.GET url
        , browsePlan = []
        }
