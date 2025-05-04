module EventShow exposing (Bookmark(..), Model, Msg(..), bidiupdate, init, view)

import Auth
import BGGAPI
import Dict
import Event exposing (browseToEvent, nickToVars)
import Game.Edit
import Game.View as G exposing (bggLink)
import Html exposing (Html, a, button, dd, dl, dt, h3, img, li, span, table, td, text, th, thead, tr, ul)
import Html.Attributes exposing (class, href, src)
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Http
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), decodeMaybe)
import Iso8601
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, hardcoded, required)
import OutMsg
import Players exposing (OtherPlayers(..), closeOtherPlayers, otherPlayersDecoder, playerName)
import ResourceUpdate as Up exposing (taggedResultDispatch)
import Router exposing (GameSortBy(..))
import TableSort exposing (SortOrder(..), compareMaybeBools, compareMaybes, sortingHeader)
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


type alias GameSorting =
    TableSort.Sorting GameSortBy


type alias Game =
    { id : Affordance
    , users : Affordance
    , nick : G.Nick
    , name : Maybe String
    , minPlayers : Maybe Int
    , maxPlayers : Maybe Int
    , durationSecs : Maybe Int
    , bggID : Maybe String
    , pitch : Maybe String
    , interested : Maybe Bool
    , canTeach : Maybe Bool
    , notes : Maybe Bool
    , whoElse : OtherPlayers
    , thumbnail : Maybe String
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
        |> custom (D.map (HM.link GET) (D.at [ "users", "id" ] D.string))
        |> required "nick" gameNickDecoder
        |> decodeMaybe "name" D.string
        |> decodeMaybe "minPlayers" D.int
        |> decodeMaybe "maxPlayers" D.int
        |> decodeMaybe "durationSecs" D.int
        |> decodeMaybe "bggId" D.string
        |> decodeMaybe "pitch" D.string
        |> decodeMaybe "interested" D.bool
        |> decodeMaybe "canTeach" D.bool
        |> decodeMaybe "notes" D.bool
        |> hardcoded Empty
        |> hardcoded Nothing


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
    | ChangeSort GameSorting
    | GotEvent Up.Etag Resource OutMsg.Msg
    | GotGameList GameList
    | GetOtherPlayers G.Nick Affordance
    | GotOtherPlayers G.Nick OtherPlayers
    | GotBGGData G.Nick BGGAPI.BGGThing
    | CloseOtherPlayers G.Nick
    | UpdateGameInterest Bool Int G.Nick
    | UpdatedGameInterest Bool G.Nick
    | UpdateGameTeaching Bool Int G.Nick
    | UpdatedGameTeaching Bool G.Nick
    | UpdateError HM.Error
    | ErrOtherPlayers HM.Error
    | ErrGetEvent HM.Error
    | ErrGameList HM.Error
    | ErrGetBGGData BGGAPI.Error


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

        ChangeSort newsort ->
            case model.resource of
                Just event ->
                    ( model, Cmd.none, OutMsg.Main << OutMsg.UpdatePage <| Router.EventShow event.nick (Just newsort) )

                Nothing ->
                    ( model, Cmd.none, OutMsg.None )

        GotEvent etag ev outmsg ->
            ( { model | etag = etag, resource = Just ev }, fetchGamesList model.creds ev.gamesTemplate, outmsg )

        GotGameList list ->
            ( { model | games = Just list }, fetchBGGData list, OutMsg.None )

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

        CloseOtherPlayers nick ->
            let
                closeGame game =
                    { game | whoElse = closeOtherPlayers game.whoElse }
            in
            ( { model | games = gameItemUpdate nick closeGame model.games }, Cmd.none, OutMsg.None )

        GetOtherPlayers nick aff ->
            let
                closeGame game =
                    { game | whoElse = closeOtherPlayers game.whoElse }

                closeAll games =
                    Maybe.map (List.map closeGame) games
            in
            ( { model | games = closeAll model.games }, fetchOtherPlayers model.creds nick aff, OutMsg.None )

        GotOtherPlayers nick list ->
            ( { model
                | games =
                    gameItemUpdate nick (\g -> { g | whoElse = list }) model.games
              }
            , Cmd.none
            , OutMsg.None
            )

        GotBGGData gameId bggData ->
            ( { model
                | games =
                    gameItemUpdate gameId (\g -> { g | thumbnail = Just bggData.thumbnail }) model.games
              }
            , Cmd.none
            , OutMsg.None
            )

        ErrOtherPlayers _ ->
            ( model, Cmd.none, OutMsg.None )

        ErrGetBGGData _ ->
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


view : Model -> Maybe GameSorting -> List (Html Msg)
view model maybeSort =
    eventView model
        ++ gamesView model maybeSort


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
            , a [ class "button", href (Router.buildFromTarget (Router.EventEdit ev.nick)) ] [ text "Edit Event" ]
            , a [ class "button", href (Router.buildFromTarget (Router.CreateGame ev.nick)) ] [ text "Add a Game" ]
            , a [ class "button", href (Router.buildFromTarget (Router.WhatShouldWePlay ev.nick Nothing)) ] [ text "What Should We Play?!" ]
            ]

        Nothing ->
            [ text "no event loaded yet" ]


gamesView : Model -> Maybe GameSorting -> List (Html Msg)
gamesView model maybeSort =
    let
        sorting =
            sortDefault (Debug.log "game-sort" maybeSort)

        sortingHeader =
            TableSort.sortingHeader ChangeSort sorting

        sort l =
            TableSort.sort sortWith sorting l
    in
    case ( model.resource, model.games ) of
        ( Just ev, Just list ) ->
            [ table []
                [ thead []
                    [ th [] []
                    , sortingHeader "Name" GameName
                    , sortingHeader "Min Players" MinPlayers
                    , sortingHeader "Max Players" MaxPlayers
                    , sortingHeader "Duration" Duration
                    , th [] [ text "Pitch" ]
                    , sortingHeader "My Interest" Interest
                    , th [] [ text "Tools" ]
                    , th [] [ text "My Notes" ]
                    ]
                , Keyed.node "tbody" [] (List.map (makeGameRow ev.nick) (sort list))
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
        [ td []
            (case game.thumbnail of
                Just th ->
                    [ img [ src th ] [] ]

                Nothing ->
                    []
            )
        , td [] [ bggLink game ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.minPlayers)) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.maxPlayers)) ]
        , td [] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.durationSecs)) ]
        , td [] [ text (Maybe.withDefault "" game.pitch) ]
        , td []
            [ let
                current =
                    Maybe.withDefault True game.interested
              in
              button [ class "interest", onClick (UpdateGameInterest (not current) event_id game.nick) ] [ span [] [ text "Interested" ], checkbox current ]
            , let
                current =
                    Maybe.withDefault True game.canTeach
              in
              button [ class "canteach", onClick (UpdateGameTeaching (not current) event_id game.nick) ] [ span [] [ text "Can Teach" ], checkbox current ]
            ]
        , td []
            [ a [ class "button edit", href (Router.buildFromTarget (Router.EditGame event_id game.nick.game_id)) ] [ span [] [ text "Edit" ], Ew.svgIcon "pencil" ]
            , button [ class "whoelse", onClick (GetOtherPlayers game.nick game.users) ] [ span [] [ text "Who Else?" ] ]
            ]
        , td [] [ text (Maybe.withDefault "" (Maybe.map boolStr game.notes)) ]
        , whoElseTD game
        ]
    )


whoElseTD : Game -> Html Msg
whoElseTD { whoElse, nick } =
    case whoElse of
        Open list ->
            td [ class "whoelse" ]
                [ h3 []
                    [ text "Interested Players" ]
                , ul
                    []
                    (List.map
                        (\p -> li [] [ text (playerName p) ])
                        list
                    )
                , button [ class "close close-whoelse", onClick (CloseOtherPlayers nick) ] [ text "close" ]
                ]

        _ ->
            td [ class "empty whoelse" ] []


defPair : String -> String -> List (Html msg)
defPair term def =
    [ dt [] [ text term ]
    , dd [] [ text def ]
    ]


sortWith : GameSortBy -> Game -> Game -> Order
sortWith by l r =
    case by of
        GameName ->
            compareMaybes l.name r.name

        MinPlayers ->
            compareMaybes l.minPlayers r.minPlayers

        MaxPlayers ->
            compareMaybes l.maxPlayers r.maxPlayers

        Duration ->
            compareMaybes l.durationSecs r.durationSecs

        Interest ->
            case compareMaybeBools l.interested r.interested of
                EQ ->
                    compareMaybeBools l.canTeach r.canTeach

                order ->
                    order


sortDefault : Maybe ( GameSortBy, SortOrder ) -> ( GameSortBy, SortOrder )
sortDefault =
    Maybe.withDefault ( GameName, Descending )


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


handleResponse : { a | onResult : value -> Msg, onErr : error -> Msg } -> Result error value -> Msg
handleResponse { onResult, onErr } res =
    case res of
        Ok list ->
            onResult list

        Err err ->
            onErr err


fetchOtherPlayers : Auth.Cred -> G.Nick -> Affordance -> Cmd Msg
fetchOtherPlayers creds nick aff =
    let
        handle =
            handleResponse { onResult = GotOtherPlayers nick, onErr = ErrOtherPlayers }
    in
    HM.chainFrom aff creds [] [] Http.emptyBody (HM.decodeBody otherPlayersDecoder) handle


fetchGamesList : Auth.Cred -> Affordance -> Cmd Msg
fetchGamesList creds tmpl =
    let
        credvars =
            Dict.fromList [ ( "user_id", Auth.accountID creds ) ]

        handle =
            handleResponse { onResult = GotGameList, onErr = ErrGameList }
    in
    HM.chainFrom (HM.fill credvars tmpl) creds [] [] Http.emptyBody (HM.decodeBody gameListDecoder) handle


fetchBGGData : List Game -> Cmd Msg
fetchBGGData gameList =
    BGGAPI.shotgunGames .bggID (taggedResultDispatch (\_ -> ErrGetBGGData) (\game -> GotBGGData game.nick)) gameList


fetchByNick : Auth.Cred -> Int -> Cmd Msg
fetchByNick creds id =
    Up.fetchByNick decoder (makeMsg creds) nickToVars browseToEvent creds id


fetchFromUrl : Auth.Cred -> HM.Uri -> Cmd Msg
fetchFromUrl creds url =
    let
        routeByHasNick m =
            Router.EventShow m.nick Nothing
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
