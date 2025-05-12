module Game.Create exposing (..)

import Auth
import BGGAPI exposing (BGGGame(..))
import Dict
import Game.View as V
import Html exposing (Html, a, button, div, form, text)
import Html.Attributes exposing (class, href)
import Html.Events exposing (onSubmit)
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import OutMsg
import ResourceUpdate as Up exposing (apiRoot, resultDispatch)
import Router


type alias EventId =
    Int


type alias GameId =
    Int


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag

    -- XXX + event sorting
    , event_id : EventId
    , bggSearchResults : List BGGGame
    , resource : V.Game -- XXX Maybe?
    }


type Bookmark
    = None
    | New Affordance
    | Nickname V.Nick
    | Url HM.Uri


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


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    let
        updateRes f m =
            { m | resource = f m.resource }
    in
    case msg of
        GameMsg gmsg ->
            V.bidiupdate gmsg model
                |> OutMsg.mapBoth (\m -> m) (Cmd.map GameMsg)

        Entered creds ev ->
            ( { init | event_id = ev, creds = creds } |> updateRes (\r -> { r | interested = Just True }), Cmd.none, OutMsg.None )

        Submit ->
            ( model, putGame model.creds model, OutMsg.None )

        CreatedGame ->
            ( model, Cmd.none, OutMsg.Main (OutMsg.Nav (Router.EventShow model.event_id Nothing)) )

        ErrGetGame _ ->
            ( model, Cmd.none, OutMsg.None )


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
        , creds = creds
        }
