module EventShow exposing
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
import BGGAPI
import Dict
import Event exposing (browseToEvent, nickToVars)
import Game.Edit
import Game.View as G exposing (bggLink)
import Html exposing (Html, a, button, dd, dl, dt, h3, img, li, p, span, table, td, text, th, thead, tr, ul)
import Html.Attributes exposing (class, href, src)
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Http exposing (Error)
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), decodeMaybe)
import Iso8601
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, hardcoded, required)
import Players exposing (OtherPlayers(..), closeOtherPlayers, otherPlayersDecoder, playerName)
import ResourceUpdate as Up exposing (apiRoot, resultDispatch, taggedResultDispatch)
import Retries exposing (Tried, entryUpdater)
import Router exposing (GameSortBy(..))
import TableSort exposing (SortOrder(..), compareMaybeBools, compareMaybes, sortingHeader)
import Time
import Toast
import Updaters exposing (Updater, noChange)
import ViewUtil as Ew


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag
    , resource : Maybe Resource
    , games : Maybe GameList
    , retry : Maybe (Tried Msg Int)
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
    , interestLevel : Int
    , teachers : Int
    , notes : Maybe String
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
        |> required "interestLevel" D.int
        |> required "teachers" D.int
        |> decodeMaybe "notes" D.string
        |> hardcoded Empty
        |> hardcoded Nothing


init : Model
init =
    Model
        Auth.unauthenticated
        Nothing
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
    | None


type Msg
    = Entered Auth.Cred Bookmark
    | ChangeSort GameSorting
    | GotEvent Up.Etag Resource
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
    | Retry Msg


type Toast
    = Retryable (Tried Msg Int)
    | Unknown


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , requestUpdatePath : Router.Target -> Updater model msg
        , lowerModel : model -> Model
        , handleErrorWithRetry : Updater model msg -> Error -> Updater model msg
        , sendToast : Toast -> Updater model msg
    }


updaters : Interface base model msg -> Msg -> Updater model msg
updaters ({ localUpdate, requestUpdatePath, lowerModel, handleErrorWithRetry, sendToast } as iface) msg =
    let
        justTried model =
            Maybe.map (\r -> Tried msg r.nick) model.resource
    in
    case msg of
        Entered creds loc ->
            case loc of
                Nickname id ->
                    let
                        fetchUpdater m =
                            ( { m | creds = creds, retry = justTried m }
                            , fetchByNick creds id
                            )

                        retryUpdater m =
                            ( { m | creds = creds }, Cmd.none )
                    in
                    entryUpdater iface fetchUpdater retryUpdater updaters id

                None ->
                    localUpdate (\m -> ( { m | creds = creds }, Cmd.none ))

        ChangeSort newsort ->
            \model ->
                case (lowerModel model).resource of
                    Just res ->
                        requestUpdatePath (Router.EventShow res.nick (Just newsort)) model

                    Nothing ->
                        ( model, Cmd.none )

        GotEvent etag ev ->
            localUpdate (\m -> ( { m | etag = etag, resource = Just ev, retry = justTried m }, fetchGamesList m.creds ev.gamesTemplate ))

        GotGameList list ->
            localUpdate (\m -> ( { m | games = Just list, retry = justTried m }, fetchBGGData list ))

        UpdateGameInterest val event_id nick ->
            localUpdate (\m -> ( { m | retry = justTried m }, updateInterest val m.creds event_id nick ))

        UpdatedGameInterest val nick ->
            localUpdate
                (\m ->
                    ( { m
                        | games = gameItemUpdate nick (\g -> { g | interested = Just val }) m.games
                        , retry = Nothing
                      }
                    , Cmd.none
                    )
                )

        UpdateGameTeaching val event_id nick ->
            localUpdate (\m -> ( { m | retry = justTried m }, updateTeaching val m.creds event_id nick ))

        UpdatedGameTeaching val nick ->
            localUpdate
                (\m ->
                    ( { m
                        | games = gameItemUpdate nick (\g -> { g | canTeach = Just val }) m.games
                        , retry = Nothing
                      }
                    , Cmd.none
                    )
                )

        CloseOtherPlayers nick ->
            let
                closeGame game =
                    { game | whoElse = closeOtherPlayers game.whoElse }

                updateGames m =
                    ( { m
                        | games = gameItemUpdate nick closeGame m.games
                      }
                    , Cmd.none
                    )
            in
            localUpdate updateGames

        GetOtherPlayers nick aff ->
            let
                closeGame game =
                    { game | whoElse = closeOtherPlayers game.whoElse }

                closeAll games =
                    Maybe.map (List.map closeGame) games

                fetchOthers m =
                    ( { m
                        | games = closeAll m.games
                        , retry = justTried m
                      }
                    , fetchOtherPlayers m.creds nick aff
                    )
            in
            localUpdate fetchOthers

        GotOtherPlayers nick list ->
            localUpdate
                (\m ->
                    ( { m
                        | games =
                            gameItemUpdate nick (\g -> { g | whoElse = list }) m.games
                        , retry = Nothing
                      }
                    , Cmd.none
                    )
                )

        GotBGGData gameId bggData ->
            localUpdate
                (\m ->
                    ( { m
                        | games =
                            gameItemUpdate gameId (\g -> { g | thumbnail = Just bggData.thumbnail }) m.games
                        , retry = Nothing
                      }
                    , Cmd.none
                    )
                )

        ErrGetEvent err ->
            handleErrorWithRetry (maybeRetry iface) err

        ErrGameList err ->
            handleErrorWithRetry (maybeRetry iface) err

        UpdateError err ->
            handleErrorWithRetry (maybeRetry iface) err

        ErrOtherPlayers err ->
            handleErrorWithRetry (maybeRetry iface) err

        ErrGetBGGData _ ->
            \model ->
                let
                    toast =
                        case (lowerModel model).retry of
                            Just r ->
                                Retryable r

                            Nothing ->
                                Unknown
                in
                sendToast toast model

        Retry m ->
            case m of
                Retry _ ->
                    noChange

                _ ->
                    updaters iface m


maybeRetry :
    { iface
        | sendToast : Toast -> Updater model msg
        , lowerModel : model -> Model
    }
    -> Updater model msg
maybeRetry { sendToast, lowerModel } model =
    let
        toast =
            case (lowerModel model).retry of
                Just r ->
                    Retryable r

                Nothing ->
                    Unknown
    in
    sendToast toast model


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


viewToast : Toast.Info Toast -> List (Html Msg)
viewToast toastInfo =
    case toastInfo.content of
        Retryable r ->
            [ p []
                [ text "There was a hiccup displaying the event" ]
            , button [ onClick (Retry r.msg) ] [ text "Retry" ]
            ]

        Unknown ->
            [ text "something went wrong editing an event" ]


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
                    [ th [ class "thumbnail" ] []
                    , sortingHeader "Name" [ class "game" ] GameName
                    , sortingHeader "Min Players" [ class "minplayers" ] MinPlayers
                    , sortingHeader "Max Players" [ class "maxplayers" ] MaxPlayers
                    , sortingHeader "Duration" [ class "duration" ] Duration
                    , sortingHeader "Interested" [ class "interested" ] InterestCount
                    , sortingHeader "Teachers" [ class "teachers" ] TeacherCount
                    , th [ class "pitch" ] [ text "Pitch" ]
                    , sortingHeader "My Interest" [ class "me" ] Interest
                    , th [ class "tools" ] [ text "Tools" ]
                    , th [ class "notes" ] [ text "My Notes" ]
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
        [ td [ class "thumbnail" ]
            (case game.thumbnail of
                Just th ->
                    [ img [ src th ] [] ]

                Nothing ->
                    []
            )
        , td [ class "game" ] [ bggLink game ]
        , td [ class "minplayers" ] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.minPlayers)) ]
        , td [ class "maxplayers" ] [ text (Maybe.withDefault "(missing)" (Maybe.map String.fromInt game.maxPlayers)) ]
        , td [ class "duration" ] [ text (Maybe.withDefault "(missing)" (Maybe.map (\seconds -> String.fromInt (seconds // 60)) game.durationSecs)) ]
        , td [ class "interest-level" ] [ text (String.fromInt game.interestLevel) ]
        , td [ class "teachers" ] [ text (String.fromInt game.teachers) ]
        , td [ class "pitch" ] [ text (Maybe.withDefault "" game.pitch) ]
        , td [ class "me" ]
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
        , td [ class "tools" ]
            [ a [ class "button edit", href (Router.buildFromTarget (Router.EditGame event_id game.nick.game_id)) ] [ span [] [ text "Edit" ], Ew.svgIcon "pencil" ]
            , button [ class "whoelse", onClick (GetOtherPlayers game.nick game.users) ] [ span [] [ text "Who Else?" ] ]
            ]
        , td [ class "notes" ] [ text (Maybe.withDefault "" game.notes) ]
        , whoElseTD game
        ]
    )


whoElseTD : Game -> Html Msg
whoElseTD { whoElse, nick, name } =
    case whoElse of
        Open list ->
            td [ class "whoelse" ]
                [ h3 []
                    [ text ("Players interested in " ++ Maybe.withDefault "that game" name) ]
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

        InterestCount ->
            compare l.interestLevel r.interestLevel

        TeacherCount ->
            compare l.teachers r.teachers

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
            case rep of
                Up.Loc _ ->
                    successMsg val game_nick

                Up.Res _ _ ->
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
    Up.retrieve
        { creds = creds
        , decoder = decoder
        , resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps)
        , startAt = apiRoot
        , browsePlan = browseToEvent (nickToVars id)
        }
