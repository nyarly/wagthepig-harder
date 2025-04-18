module EventShow exposing (Bookmark(..), Model, Msg(..), bidiupdate, init, view)

import Auth
import Dict
import Event exposing (browseToEvent, nickToVars)
import Game.Edit
import Game.View as G
import Html exposing (Html, a, button, dd, dl, dt, span, table, td, text, th, thead, tr)
import Html.Attributes exposing (href)
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Http
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..))
import Iso8601
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, optional, required)
import OutMsg
import ResourceUpdate as Up
import Router
import Time
import ViewUtil as Ew


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
    , nick : G.Nick
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


gameNickDecoder : D.Decoder G.Nick
gameNickDecoder =
    D.map2 G.Nick
        (D.field "game_id" D.int)
        (D.field "user_id" D.string)


gameDecoder : D.Decoder Game
gameDecoder =
    D.succeed Game
        |> custom (D.map (HM.link GET) (D.field "id" D.string))
        |> required "nick" gameNickDecoder
        |> decodeMaybe "name" D.string
        |> decodeMaybe "minPlayers" D.int
        |> decodeMaybe "maxPlayers" D.int
        |> decodeMaybe "bggLink" D.string
        |> decodeMaybe "durationSecs" D.int
        |> decodeMaybe "bggId" D.string
        |> decodeMaybe "pitch" D.string
        |> decodeMaybe "interested" D.bool
        |> decodeMaybe "canTeach" D.bool
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
        (D.map (HM.selectAffordance (ByType "ViewAction")) HM.affordanceListDecoder |> mustHave "no view action!")
        (D.field "games" (D.map (HM.selectAffordance (ByType "FindAction")) HM.affordanceListDecoder) |> mustHave "no games template!")
        (D.field "name" D.string)
        (D.field "time" Iso8601.decoder)
        (D.field "location" D.string)


gameListDecoder : D.Decoder (List Game)
gameListDecoder =
    D.field "games" (D.list gameDecoder)


mustHave : String -> D.Decoder (Maybe a) -> D.Decoder a
mustHave emsg =
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
    | UpdateGameInterest Bool Int G.Nick
    | UpdatedGameInterest Bool G.Nick
    | UpdateGameTeaching Bool Int G.Nick
    | UpdatedGameTeaching Bool G.Nick
    | UpdateError HM.Error


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    case msg of
        Entered creds loc ->
            case loc of
                Nickname id ->
                    ( { model | creds = creds }, fetchByNick creds id, OutMsg.None )

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

        UpdateGameInterest val event_id nick ->
            ( model, updateInterest val model.creds event_id nick, OutMsg.None )

        -- XXX need to update table
        UpdatedGameInterest val nick ->
            ( { model
                | games = gameItemUpdate nick (\g -> { g | interested = Just val }) model.games
              }
            , Cmd.none
            , OutMsg.None
            )

        UpdateGameTeaching val event_id nick ->
            ( model, updateTeaching val model.creds event_id nick, OutMsg.None )

        -- XXX need to update table
        UpdatedGameTeaching val nick ->
            ( { model
                | games = gameItemUpdate nick (\g -> { g | canTeach = Just val }) model.games
              }
            , Cmd.none
            , OutMsg.None
            )

        UpdateError _ ->
            ( model, Cmd.none, OutMsg.None )


gameItemUpdate : G.Nick -> (Game -> Game) -> Maybe GameList -> Maybe GameList
gameItemUpdate nick doUpdate games =
    Maybe.map
        (List.map
            (\g ->
                if g.nick == nick then
                    doUpdate g

                else
                    g
            )
        )
        games


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
            , a [ href (Router.buildFromTarget (Router.CreateGame ev.nick)) ] [ text "Add a Game" ]
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
    case ( model.resource, model.games ) of
        ( Just ev, Just list ) ->
            [ table []
                [ thead []
                    [ th [] [ text "name" ]
                    , th [] [ text "minPlayers" ]
                    , th [] [ text "maxPlayers" ]
                    , th [] [ text "bggLink" ]
                    , th [] [ text "durationSecs" ]
                    , th [] [ text "bggID" ]
                    , th [] [ text "pitch" ]
                    , th [] [ text "my interest" ]
                    , th [] [ text "tools" ]
                    , th [] [ text "notes" ]
                    ]
                , Keyed.node "tbody" [] (List.map (makeGameRow ev.nick) list)
                ]
            ]

        _ ->
            []


makeGameRow : Int -> Game -> ( String, Html Msg )
makeGameRow event_id game =
    let
        checkbox bool =
            if bool then
                Ew.svgIcon "checkbox-checked"

            else
                Ew.svgIcon "checkbox-unchecked"
    in
    ( Maybe.withDefault "noid" game.bggID
    , tr []
        [ td [] [ text (Maybe.withDefault "(missing)" game.name) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.minPlayers)) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.maxPlayers)) ]
        , td [] [ text (Maybe.withDefault "(missing)" game.bggLink) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.durationSecs)) ]
        , td [] [ text (Maybe.withDefault "(missing)" game.bggID) ]
        , td [] [ text (Maybe.withDefault "(missing)" game.pitch) ]
        , td []
            [ let
                current =
                    Maybe.withDefault True game.interested
              in
              button [ onClick (UpdateGameInterest (not current) event_id game.nick) ] [ span [] [ text "Interested" ], checkbox current ]
            , let
                current =
                    Maybe.withDefault True game.canTeach
              in
              button [ onClick (UpdateGameTeaching (not current) event_id game.nick) ] [ span [] [ text "Can Teach" ], checkbox current ]
            ]
        , td []
            [ a [ href (Router.buildFromTarget (Router.EditGame event_id game.nick.game_id)) ] [ span [] [ text "Edit" ], Ew.svgIcon "pencil" ]
            ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map boolStr game.notes)) ]
        ]
    )


updateGame :
    { doUpdate : a -> G.Game -> G.Game
    , successMsg : a -> G.Nick -> Msg
    , failMsg : Http.Error -> Msg
    }
    -> a
    -> Auth.Cred
    -> Int
    -> G.Nick
    -> Cmd Msg
updateGame { doUpdate, successMsg, failMsg } val creds event_id game_nick =
    let
        mkMsg rep =
            -- Representation e r -> msg
            case rep of
                Up.Loc _ ->
                    successMsg val game_nick

                Up.Res _ _ _ ->
                    successMsg val game_nick

                Up.Error e ->
                    failMsg e
    in
    Game.Edit.roundTrip mkMsg (doUpdate val) creds event_id game_nick


updateInterest : Bool -> Auth.Cred -> Int -> G.Nick -> Cmd Msg
updateInterest =
    updateGame
        { doUpdate = \v -> \g -> { g | interested = Just v }
        , successMsg = UpdatedGameInterest
        , failMsg = UpdateError
        }


updateTeaching : Bool -> Auth.Cred -> Int -> G.Nick -> Cmd Msg
updateTeaching =
    updateGame
        { doUpdate = \v -> \g -> { g | canTeach = Just v }
        , successMsg = UpdatedGameTeaching
        , failMsg = UpdateError
        }


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
    HM.chainFrom (HM.fill credvars tmpl) creds [] [] Http.emptyBody (HM.decodeBody gameListDecoder) handleGameListResult


handleGameListResult : Result Http.Error GameList -> Msg
handleGameListResult res =
    case res of
        Ok list ->
            GotGameList list

        Err err ->
            ErrGameList err


fetchByNick : Auth.Cred -> Int -> Cmd Msg
fetchByNick creds id =
    Up.fetchByNick decoder (makeMsg creds) nickToVars browseToEvent creds id


fetchFromUrl : Auth.Cred -> HM.Uri -> Cmd Msg
fetchFromUrl creds url =
    let
        routeByHasNick =
            Router.EventShow << .nick
    in
    Up.fetchFromUrl decoder (makeMsg creds) routeByHasNick creds url


makeMsg : Auth.Cred -> Up.Representation HM.Error Resource -> Msg
makeMsg cred ex =
    case ex of
        Up.Loc aff ->
            Entered cred (Url aff.uri)

        Up.Res etag res out ->
            GotEvent etag res out

        Up.Error err ->
            ErrGetEvent err
