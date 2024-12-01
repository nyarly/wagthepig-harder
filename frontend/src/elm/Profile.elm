module Profile exposing (Bookmark(..), Model, Msg(..), bidiupdate, init, view)

import Auth
import Dict
import Html exposing (Html, button, form, span, text)
import Html.Attributes exposing (class, disabled, type_)
import Html.Attributes.Extra exposing (attributeIf, attributeMaybe)
import Html.Events exposing (onSubmit)
import Html.Extra exposing (viewIf)
import Http
import Hypermedia as HM exposing (Affordance, OperationSelector(..), emptyResponse)
import Json.Decode as D
import Json.Encode as E
import OutMsg
import ResourceUpdate as Up
import Router
import String exposing (length)
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
    | GotProfile Up.Etag Profile OutMsg.Msg
    | ErrProfileGet Http.Error
    | ChangeOldPassword String
    | ChangeNewPassword String
    | ChangeNewPasswordAgain String
    | SubmitPassword
    | AuthResponse (Result Http.Error ())


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


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    let
        updateProfile f =
            { model | profile = f model.profile }

        updatePassword f =
            { model | password = f model.password }
    in
    case msg of
        Entered creds loc ->
            case loc of
                Creds ->
                    ( { model | creds = creds }, fetchByCreds creds model, OutMsg.None )

                Url url ->
                    ( { model | creds = creds }, fetchFromUrl creds url.uri, OutMsg.None )

        ChangeName n ->
            ( updateProfile (\pf -> { pf | name = n }), Cmd.none, OutMsg.None )

        ChangeEmail e ->
            ( updateProfile (\pf -> { pf | email = e }), Cmd.none, OutMsg.None )

        ChangeBGG b ->
            ( updateProfile (\pf -> { pf | bgg_username = b }), Cmd.none, OutMsg.None )

        SubmitProfile ->
            ( model, putProfile model.creds model, OutMsg.None )

        GotProfile etag m out ->
            ( { model | etag = etag, profile = m }, Cmd.none, out )

        ErrProfileGet _ ->
            ( model, Cmd.none, OutMsg.None )

        -- XXX
        ChangeOldPassword p ->
            ( updatePassword (\pw -> { pw | old = p }), Cmd.none, OutMsg.None )

        ChangeNewPassword p ->
            ( updatePassword (\pw -> { pw | new = p }), Cmd.none, OutMsg.None )

        ChangeNewPasswordAgain p ->
            ( updatePassword (\pw -> { pw | newAgain = p }), Cmd.none, OutMsg.None )

        SubmitPassword ->
            ( model, submitPasswordUpdate model, OutMsg.None )

        AuthResponse res ->
            case res of
                Ok () ->
                    ( model, Cmd.none, OutMsg.Main (OutMsg.Nav Router.Login) )

                Err _ ->
                    ( model, Cmd.none, OutMsg.None )


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
    HM.chain model.creds
        [ HM.browse [ "authenticate" ] (ByType "UpdateAction") |> HM.fillIn (Dict.fromList [ ( "user_id", email ) ])
        ]
        []
        reqBody
        emptyResponse
        AuthResponse


makeMsg : Auth.Cred -> Up.Representation Profile -> Msg
makeMsg cred rep =
    case rep of
        Up.None ->
            Entered cred Creds

        Up.Loc aff ->
            Entered cred (Url aff)

        Up.Res etag res out ->
            GotProfile etag res out

        Up.Error err ->
            ErrProfileGet err


nickToVars : String -> Dict.Dict String String
nickToVars nick =
    Dict.fromList [ ( "user_id", nick ) ]


browseToProfile : HM.TemplateVars -> List (HM.Response -> Result String Affordance)
browseToProfile vars =
    [ HM.browse [ "profile" ] (ByType "FindAction") |> HM.fillIn vars ]


putProfile : Auth.Cred -> Model -> Cmd Msg
putProfile creds model =
    Up.put encode decoder (makeMsg creds) creds model.etag model.profile


fetchByCreds : Auth.Cred -> Model -> Cmd Msg
fetchByCreds creds model =
    Up.fetchByNick decoder (makeMsg creds) nickToVars browseToProfile model.profile.template creds (Auth.accountID creds)


fetchFromUrl : Auth.Cred -> HM.Uri -> Cmd Msg
fetchFromUrl creds url =
    Up.fetchFromUrl decoder (makeMsg creds) (\_ -> Router.Profile) creds url
