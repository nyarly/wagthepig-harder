module Game.Edit exposing (..)

import Auth
import BGGAPI exposing (BGGGame(..))
import Dict
import Game.View as V
import Html exposing (Html, a, button, div, form, text)
import Html.Attributes exposing (class, href)
import Html.Events exposing (onSubmit)
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, hardcoded, required)
import Json.Encode as E
import OutMsg
import ResourceUpdate as Up
import Router


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


type Bookmark
    = None
    | New Affordance
    | Nickname V.Nick
    | Url HM.Uri


type Msg
    = Entered Auth.Cred EventId GameId
    | LoadLoc Affordance
    | Submit
    | CreatedGame
    | GotGame Up.Etag LoadedResource OutMsg.Msg
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
    [ a [ href (Router.buildFromTarget (Router.EventShow model.event_id)) ] [ text "Back to Event" ]
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
            ( model, Cmd.none, OutMsg.Main (OutMsg.Nav (Router.EventShow model.event_id)) )

        GotGame etag g outmsg ->
            ( { model | etag = etag, resource = Loaded g }, Cmd.none, outmsg )

        ErrGetGame _ ->
            ( model, Cmd.none, OutMsg.None )


updateMsg : Up.Representation HM.Error LoadedResource -> Msg
updateMsg ex =
    case ex of
        Up.Loc aff ->
            LoadLoc aff

        Up.Res etag res out ->
            GotGame etag res out

        Up.Error err ->
            ErrGetGame err


createMsg : Up.Representation HM.Error r -> Msg
createMsg ex =
    case ex of
        Up.Loc _ ->
            CreatedGame

        Up.Res _ _ _ ->
            CreatedGame

        Up.Error err ->
            ErrGetGame err


nickToVars : Auth.Cred -> Int -> V.Nick -> Dict.Dict String String
nickToVars cred event_id nick =
    Dict.fromList
        [ ( "event_id", String.fromInt event_id )
        , ( "user_id", Auth.accountID cred )
        , ( "game_id", String.fromInt nick.game_id )
        ]


browseToCreate : HM.TemplateVars -> List (Response -> Result String Affordance)
browseToCreate vars =
    [ HM.browse [ "events" ] (ByType "ViewAction")
    , HM.browse [ "eventById" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "games" ] (ByType "AddAction") |> HM.fillIn vars
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
    Up.put encoder decoder updateMsg creds etag res


fetchByNick : Auth.Cred -> Int -> V.Nick -> Cmd Msg
fetchByNick creds event_id =
    Up.fetchByNick decoder updateMsg (nickToVars creds event_id) browseToFetch creds


fetchFromUrl : Auth.Cred -> Int -> HM.Uri -> Cmd Msg
fetchFromUrl creds event_id =
    let
        routeByNick r =
            Router.EditGame event_id r.nick.game_id
    in
    Up.fetchFromUrl decoder updateMsg routeByNick creds
