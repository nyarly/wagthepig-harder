module Game.Edit exposing (Model, Msg(..), bidiupdate, init, roundTrip, updaters, view)

import Auth
import BGGAPI exposing (BGGGame(..))
import Dict
import Game.Create exposing (putGame)
import Game.View as V
import Html exposing (Html, a, button, div, form, text)
import Html.Attributes exposing (class, href)
import Html.Events exposing (onSubmit)
import Http
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, hardcoded, required)
import Json.Encode as E
import OutMsg
import ResourceUpdate as Up exposing (apiRoot, resultDispatch)
import Router
import Updaters exposing (UpdateList, Updater, childUpdate)


type alias EventId =
    Int


type alias GameId =
    Int


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag
    , event_id : EventId
    , resource : Resource
    }


type Resource
    = NotLoaded
    | Loaded LoadedResource


type alias LoadedResource =
    { id : Affordance
    , update : Maybe Affordance
    , template : Maybe Affordance
    , nick : V.Nick
    , bggSearchResults : List BGGGame
    , resource : V.Game
    }


type Msg
    = Entered Auth.Cred EventId GameId
    | LoadLoc Affordance
    | Submit
    | CreatedGame
    | GotGame Up.Etag LoadedResource
    | ErrGetGame HM.Error
    | GameMsg V.Msg


init : Model
init =
    Model
        Auth.unauthenticated
        Nothing
        0
        NotLoaded


decoder : D.Decoder LoadedResource
decoder =
    D.succeed LoadedResource
        |> custom (D.map (\u -> HM.link GET u) (D.field "id" D.string))
        |> custom (D.map (HM.selectAffordance (ByType "UpdateAction")) HM.affordanceListDecoder)
        |> custom (D.map (HM.selectAffordance (ByType "FindAction")) HM.affordanceListDecoder)
        |> required "nick" V.nickDecode
        |> hardcoded []
        |> custom V.decoder


encoder : LoadedResource -> E.Value
encoder lr =
    V.encoder lr.resource


view : Model -> List (Html Msg)
view model =
    [ a [ href (Router.buildFromTarget (Router.EventShow model.event_id Nothing)) ] [ text "Back to Event" ]
    , form [ onSubmit Submit ]
        (case model.resource of
            NotLoaded ->
                []

            Loaded res ->
                List.map (Html.map GameMsg) (V.view False res)
                    ++ [ div [ class "actions" ] [ button [] [ text "Submit" ] ]
                       ]
        )
    ]


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , lowerModel : model -> Model
        , requestNav : Router.Target -> Updater model msg
    }


childUpdate : (LoadedResource -> ( LoadedResource, Cmd V.Msg )) -> Updater Model Msg
childUpdate upper model =
    case model.resource of
        NotLoaded ->
            ( model, Cmd.none )

        Loaded res ->
            upper res
                |> Tuple.mapBoth (\m -> { model | resource = Loaded m }) (Cmd.map GameMsg)


updaters : Interface base model msg -> Msg -> UpdateList model msg
updaters { requestNav, localUpdate, lowerModel } msg =
    case msg of
        Entered creds ev i ->
            [ localUpdate (\m -> ( { m | event_id = ev, creds = creds }, fetchByNick creds ev (V.Nick i (Auth.accountID creds)) )) ]

        LoadLoc aff ->
            [ localUpdate (\m -> ( m, fetchFromUrl m.creds m.event_id aff.uri )) ]

        GameMsg gmsg ->
            let
                interface =
                    { localUpdate = localUpdate << childUpdate
                    }
            in
            V.updaters interface gmsg

        Submit ->
            [ \model ->
                let
                    gmod =
                        lowerModel model
                in
                case gmod.resource of
                    NotLoaded ->
                        ( model, Cmd.none )

                    Loaded res ->
                        localUpdate (\m -> ( m, putGame gmod.creds gmod.etag res )) model
            ]

        CreatedGame ->
            [ \m -> requestNav (Router.EventShow (lowerModel m).event_id Nothing) m
            ]

        GotGame etag g ->
            [ localUpdate (\m -> ( { m | etag = etag, resource = Loaded g }, Cmd.none )) ]

        ErrGetGame _ ->
            []


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    case msg of
        GameMsg gmsg ->
            case model.resource of
                NotLoaded ->
                    ( model, Cmd.none, OutMsg.None )

                Loaded res ->
                    V.bidiupdate gmsg res
                        |> OutMsg.mapBoth (\m -> { model | resource = Loaded m }) (Cmd.map GameMsg)

        Entered creds ev i ->
            ( { init | event_id = ev, creds = creds }, fetchByNick creds ev (V.Nick i (Auth.accountID creds)), OutMsg.None )

        LoadLoc aff ->
            ( model, fetchFromUrl model.creds model.event_id aff.uri, OutMsg.None )

        Submit ->
            case model.resource of
                NotLoaded ->
                    ( model, Cmd.none, OutMsg.None )

                Loaded res ->
                    ( model, putGame model.creds model.etag res, OutMsg.None )

        CreatedGame ->
            ( model, Cmd.none, OutMsg.Main (OutMsg.Nav (Router.EventShow model.event_id Nothing)) )

        GotGame etag g ->
            ( { model | etag = etag, resource = Loaded g }, Cmd.none, OutMsg.None )

        ErrGetGame _ ->
            ( model, Cmd.none, OutMsg.None )


nickToVars : Auth.Cred -> Int -> V.Nick -> Dict.Dict String String
nickToVars cred event_id nick =
    Dict.fromList
        [ ( "event_id", String.fromInt event_id )
        , ( "user_id", Auth.accountID cred )
        , ( "game_id", String.fromInt nick.game_id )
        ]


browseToFetch : HM.TemplateVars -> List (Response -> Result String Affordance)
browseToFetch vars =
    [ HM.browse [ "events" ] (ByType "ViewAction")
    , HM.browse [ "eventById" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "games" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "game" ] (ByType "FindAction") |> HM.fillIn vars
    ]


putGame : Auth.Cred -> Up.Etag -> LoadedResource -> Cmd Msg
putGame creds etag res =
    case res.update of
        Nothing ->
            Cmd.none

        Just aff ->
            Up.create
                { resource = res
                , etag = Just etag
                , encode = encoder
                , resMsg = resultDispatch ErrGetGame (\_ -> CreatedGame)
                , startAt = aff
                , browsePlan = []
                , creds = creds
                }


fetchByNick : Auth.Cred -> Int -> V.Nick -> Cmd Msg
fetchByNick creds event_id nick =
    Up.retrieve
        { creds = creds
        , decoder = decoder
        , resMsg = resultDispatch ErrGetGame (\( etag, ps ) -> GotGame etag ps)
        , startAt = apiRoot
        , browsePlan = browseToFetch (nickToVars creds event_id nick)
        }


fetchFromUrl : Auth.Cred -> Int -> HM.Uri -> Cmd Msg
fetchFromUrl creds _ url =
    Up.retrieve
        { creds = creds
        , decoder = decoder
        , resMsg = resultDispatch ErrGetGame (\( etag, ps ) -> GotGame etag ps)
        , startAt = HM.link HM.GET url
        , browsePlan = []
        }


roundTrip : Up.MakeMsg Http.Error LoadedResource msg -> (V.Game -> V.Game) -> Auth.Cred -> Int -> V.Nick -> Cmd msg
roundTrip makeMsg update cred event_id nick =
    let
        updateRz lr =
            let
                rz =
                    update lr.resource
            in
            case lr.update of
                Just aff ->
                    Ok ( { lr | resource = rz }, aff )

                Nothing ->
                    Err (Http.BadStatus 429)
    in
    Up.roundTrip
        { encode = encoder
        , decoder = decoder
        , makeMsg = makeMsg
        , browsePlan = browseToFetch (nickToVars cred event_id nick)
        , updateRes = updateRz
        , creds = cred
        }
