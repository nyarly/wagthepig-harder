module EventShow exposing (Bookmark(..), Model, Msg(..), bidiupdate, init, view)

import Auth
import Dict
import Event exposing (browseToEvent, nickToVars)
import Html exposing (Html, dd, dl, dt, table, td, text, th, thead, tr)
import Html.Keyed as Keyed
import Http
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..))
import Iso8601
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, optional)
import OutMsg
import ResourceUpdate as Up
import Router
import Time


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag
    , resource : Maybe Resource
    , games : Maybe GameList
    }


type alias Resource =
    { id : Affordance
    , nick : Int
    , template : Affordance
    , gamesTemplate : Affordance
    , name : String
    , time : Time.Posix
    , location : String
    }


type alias GameList =
    List Game


type alias Game =
    { id : Affordance
    , name : Maybe String
    , minPlayers : Maybe Int
    , maxPlayers : Maybe Int
    , bggLink : Maybe String
    , durationSecs : Maybe Int
    , bggID : Maybe String
    , pitch : Maybe String
    , interested : Maybe Bool
    , canTeach : Maybe Bool
    , notes : Maybe Bool
    }


gameDecoder : D.Decoder Game
gameDecoder =
    D.succeed Game
        |> custom (D.map (HM.link GET) (D.field "id" D.string))
        |> decodeMaybe "name" D.string
        |> decodeMaybe "min_players" D.int
        |> decodeMaybe "max_players" D.int
        |> decodeMaybe "bgg_link" D.string
        |> decodeMaybe "duration_secs" D.int
        |> decodeMaybe "bgg_id" D.string
        |> decodeMaybe "pitch" D.string
        |> decodeMaybe "interested" D.bool
        |> decodeMaybe "can_teach" D.bool
        |> decodeMaybe "notes" D.bool


decodeMaybe : String -> D.Decoder a -> D.Decoder (Maybe a -> b) -> D.Decoder b
decodeMaybe name dec =
    optional name (D.map Just dec) Nothing


init : Model
init =
    Model
        Auth.unauthenticated
        Nothing
        Nothing
        Nothing


decoder : D.Decoder Resource
decoder =
    D.map7 Resource
        (D.map (\u -> HM.link GET u) (D.field "id" D.string))
        (D.at [ "nick", "event_id" ] D.int)
        (D.map (HM.selectAffordance (ByType "ViewAction")) HM.affordanceListDecoder |> required "no view action!")
        (D.field "games" (D.map (HM.selectAffordance (ByType "FindAction")) HM.affordanceListDecoder) |> required "no games template!")
        (D.field "name" D.string)
        (D.field "time" Iso8601.decoder)
        (D.field "location" D.string)


gameListDecoder : D.Decoder (List Game)
gameListDecoder =
    D.field "games" (D.list gameDecoder)


required : String -> D.Decoder (Maybe a) -> D.Decoder a
required emsg =
    D.andThen
        (\m ->
            case m of
                Just v ->
                    D.succeed v

                Nothing ->
                    D.fail emsg
        )


type Bookmark
    = Nickname Int
    | Url HM.Uri
    | None


type Msg
    = Entered Auth.Cred Bookmark
    | GotEvent Up.Etag Resource OutMsg.Msg
    | GotGameList GameList
    | ErrGetEvent HM.Error
    | ErrGameList HM.Error


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    case msg of
        Entered creds loc ->
            case loc of
                Nickname id ->
                    ( { model | creds = creds }, fetchByNick creds model id, OutMsg.None )

                Url url ->
                    ( { model | creds = creds }, fetchFromUrl creds url, OutMsg.None )

                None ->
                    ( { model | creds = creds }, Cmd.none, OutMsg.None )

        GotEvent etag ev outmsg ->
            ( { model | etag = etag, resource = Just ev }, fetchGamesList model.creds ev.gamesTemplate, outmsg )

        GotGameList list ->
            ( { model | games = Just list }, Cmd.none, OutMsg.None )

        ErrGetEvent _ ->
            ( model, Cmd.none, OutMsg.None )

        ErrGameList _ ->
            ( model, Cmd.none, OutMsg.None )


view : Model -> List (Html Msg)
view model =
    eventView model
        ++ gamesView model


eventView : Model -> List (Html Msg)
eventView model =
    case model.resource of
        Just ev ->
            [ dl []
                (defPair
                    "Name"
                    ev.name
                    ++ defPair "Time" (Event.formatTime ev)
                    ++ defPair "Location" ev.location
                )
            ]

        Nothing ->
            [ text "no event loaded yet" ]


defPair : String -> String -> List (Html msg)
defPair term def =
    [ dt [] [ text term ]
    , dd [] [ text def ]
    ]


gamesView : Model -> List (Html Msg)
gamesView model =
    case model.games of
        Just list ->
            [ table []
                [ thead []
                    [ th [] [ text "name" ]
                    , th [] [ text "minPlayers" ]
                    , th [] [ text "maxPlayers" ]
                    , th [] [ text "bggLink" ]
                    , th [] [ text "durationSecs" ]
                    , th [] [ text "bggID" ]
                    , th [] [ text "pitch" ]
                    , th [] [ text "interested" ]
                    , th [] [ text "canTeach" ]
                    , th [] [ text "notes" ]
                    ]
                ]
            , Keyed.node "tbody" [] (List.foldr addGameRow [] list)
            ]

        Nothing ->
            []


addGameRow : Game -> List ( String, Html msg ) -> List ( String, Html msg )
addGameRow game list =
    ( Maybe.withDefault "noid" game.bggID
    , tr []
        [ td [] [ text (Maybe.withDefault "(missing)" game.name) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.minPlayers)) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.maxPlayers)) ]
        , td [] [ text (Maybe.withDefault "(missing)" game.bggLink) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.durationSecs)) ]
        , td [] [ text (Maybe.withDefault "(missing)" game.bggID) ]
        , td [] [ text (Maybe.withDefault "(missing)" game.pitch) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map boolStr game.interested)) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map boolStr game.canTeach)) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map boolStr game.notes)) ]
        ]
    )
        :: list


boolStr : Bool -> String
boolStr b =
    if b then
        "yes"

    else
        "no"


fetchGamesList : Auth.Cred -> Affordance -> Cmd Msg
fetchGamesList creds tmpl =
    let
        credvars =
            Dict.fromList [ ( "user_id", Auth.accountID creds ) ]
    in
    HM.chainFrom creds (HM.fill credvars tmpl) [] [] Http.emptyBody (HM.decodeBody gameListDecoder) handleGameListResult


handleGameListResult : Result Http.Error GameList -> Msg
handleGameListResult res =
    case res of
        Ok list ->
            GotGameList list

        Err err ->
            ErrGameList err


fetchByNick : Auth.Cred -> Model -> Int -> Cmd Msg
fetchByNick creds model id =
    Up.fetchByNick decoder (makeMsg creds) nickToVars browseToEvent (Maybe.map .template model.resource) creds id


fetchFromUrl : Auth.Cred -> HM.Uri -> Cmd Msg
fetchFromUrl creds url =
    let
        routeByHasNick =
            Router.EventShow << .nick
    in
    Up.fetchFromUrl decoder (makeMsg creds) routeByHasNick creds url


makeMsg : Auth.Cred -> Up.Representation Resource -> Msg
makeMsg cred ex =
    case ex of
        Up.None ->
            Entered cred None

        Up.Loc aff ->
            Entered cred (Url aff.uri)

        Up.Res etag res out ->
            GotEvent etag res out

        Up.Error err ->
            ErrGetEvent err
