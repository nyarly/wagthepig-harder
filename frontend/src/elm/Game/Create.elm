module Game.Create exposing
    ( EventId
    , Interface
    , Model
    , Msg(..)
    , browseToCreate
    , init
    , nickToVars
    , putGame
    , updaters
    , view
    , viewToast
    )

import Auth
import BGGAPI exposing (BGGGame)
import Dict
import Game.View as V
import Html exposing (Html, a, button, div, form, text)
import Html.Attributes exposing (class, href)
import Html.Events exposing (onSubmit)
import Http exposing (Error)
import Hypermedia as HM exposing (Affordance, OperationSelector(..), Response)
import ResourceUpdate as Up exposing (apiRoot, resultDispatch)
import Router
import Toast
import Updaters exposing (Updater, childUpdate)


type alias EventId =
    Int


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag

    -- XXX + event sorting
    , event_id : EventId
    , bggSearchResults : List BGGGame
    , resource : V.Game -- XXX Maybe?
    }


type Msg
    = Entered Auth.Cred EventId
    | Submit
    | CreatedGame
    | ErrGetGame HM.Error
    | GameMsg V.Msg


init : Model
init =
    Model
        Auth.unauthenticated
        Nothing
        0
        []
        V.init


view : Model -> List (Html Msg)
view model =
    [ a [ href (Router.buildFromTarget (Router.EventShow model.event_id Nothing)) ] [ text "Back to Event" ]
    , form [ onSubmit Submit ]
        (List.map (Html.map GameMsg) (V.view False model)
            ++ [ div [ class "actions" ] [ button [] [ text "Submit" ] ]
               ]
        )
    ]


viewToast : Toast.Info V.Toast -> List (Html Msg)
viewToast toastInfo =
    List.map (Html.map GameMsg) (V.viewToast toastInfo)


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , requestNav : Router.Target -> Updater model msg
        , lowerModel : model -> Model
        , sendToast : V.Toast -> Updater model msg
        , handleError : Error -> Updater model msg
    }


updaters : Interface base model msg -> Msg -> Updater model msg
updaters { localUpdate, lowerModel, requestNav, sendToast, handleError } msg =
    let
        updateRes : (V.Game -> V.Game) -> Model -> Model
        updateRes f m =
            { m | resource = f m.resource }
    in
    case msg of
        GameMsg gmsg ->
            let
                gameInterface :
                    { localUpdate : Updater Model V.Msg -> model -> ( model, Cmd msg )
                    , sendToast : V.Toast -> model -> ( model, Cmd msg )
                    }
                gameInterface =
                    { localUpdate = localUpdate << childUpdate identity (\_ -> identity) GameMsg
                    , sendToast = sendToast
                    }
            in
            V.updaters gameInterface gmsg

        Entered creds ev ->
            localUpdate
                (\_ ->
                    ( { init | event_id = ev, creds = creds } |> updateRes (\r -> { r | interested = Just True })
                    , Cmd.none
                    )
                )

        Submit ->
            localUpdate (\m -> ( m, putGame m.creds m ))

        CreatedGame ->
            \model -> requestNav (Router.EventShow (lowerModel model).event_id Nothing) model

        ErrGetGame err ->
            handleError err


nickToVars : Auth.Cred -> Int -> Dict.Dict String String
nickToVars cred event_id =
    Dict.fromList
        [ ( "event_id", String.fromInt event_id )
        , ( "user_id", Auth.accountID cred )
        ]


browseToCreate : HM.TemplateVars -> List (Response -> Result String Affordance)
browseToCreate vars =
    [ HM.browse [ "events" ] (ByType "ViewAction")
    , HM.browse [ "eventById" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "games" ] (ByType "AddAction") |> HM.fillIn vars
    ]


putGame : Auth.Cred -> Model -> Cmd Msg
putGame creds model =
    Up.create
        { resource = model.resource
        , etag = Just model.etag
        , encode = V.encoder
        , resMsg = resultDispatch ErrGetGame (\_ -> CreatedGame)
        , startAt = apiRoot
        , browsePlan = browseToCreate (nickToVars creds model.event_id)
        , headers = Auth.credHeader creds
        }
