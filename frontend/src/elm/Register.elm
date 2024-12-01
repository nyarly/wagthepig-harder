module Register exposing (..)

import Auth
import Dict
import Html exposing (Html, button, form, text)
import Html.Attributes exposing (disabled)
import Html.Attributes.Extra exposing (attributeMaybe)
import Html.Events exposing (onClick, onSubmit)
import Http
import Hypermedia as HM exposing (Method(..), OperationSelector(..), emptyResponse)
import Json.Encode as E
import OutMsg
import ViewUtil as Eww


type alias Model =
    { email : String
    , name : String
    , bgg_username : String
    , fromServer : Maybe (Result Http.Error ())
    }


type Msg
    = Entered
    | Submit
    | ChangeEmail String
    | ChangeName String
    | ChangeBGG String
    | ServerResponse (Result Http.Error ())


init : Model
init =
    Model "" "" "" Nothing


view : Model -> List (Html Msg)
view model =
    case model.fromServer of
        Nothing ->
            [ form [ onSubmit Submit ]
                [ Eww.inputPair [] "Email" model.email ChangeEmail
                , Eww.inputPair [] "Name" model.name ChangeName
                , Eww.inputPair [] "BGG Username" model.bgg_username ChangeBGG
                , button [ attributeMaybe (\_ -> disabled True) model.fromServer ] [ text "Submit" ]
                ]
            ]

        Just _ ->
            [ text "Great! You should receive an email presently with a link to complete your registration process."
            ]


encodeModel : Model -> E.Value
encodeModel model =
    E.object
        [ ( "name", E.string model.name )
        , ( "bggUsername", E.string model.bgg_username )
        ]


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    case msg of
        Entered ->
            ( { model | fromServer = Nothing }, Cmd.none, OutMsg.None )

        ChangeEmail email ->
            ( { model | email = email }, Cmd.none, OutMsg.None )

        ChangeName name ->
            ( { model | name = name }, Cmd.none, OutMsg.None )

        ChangeBGG bgg ->
            ( { model | bgg_username = bgg }, Cmd.none, OutMsg.None )

        Submit ->
            ( model, put model, OutMsg.None )

        ServerResponse res ->
            ( { model | fromServer = Just res }, Cmd.none, OutMsg.None )


put : Model -> Cmd Msg
put model =
    let
        _ =
            Debug.log "reg model" model
    in
    HM.chain Auth.unauthenticated
        [ HM.browse [ "profile" ] (HM.ByType "CreateAction") |> HM.fillIn (Dict.fromList [ ( "user_id", model.email ) ])
        ]
        []
        (model |> encodeModel >> Http.jsonBody)
        emptyResponse
        ServerResponse
