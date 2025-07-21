module Game.View exposing
    ( Game
    , GameAndSearch
    , Msg(..)
    , Nick
    , Toast
    , bggLink
    , decoder
    , encoder
    , init
    , nickDecode
    , updaters
    , view
    , viewToast
    )

import BGGAPI exposing (BGGGame(..), BGGThing, requestBGGSearch, shotgunGames)
import Html exposing (Html, a, button, div, img, p, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (class, disabled, href, name, src, type_)
import Html.Events exposing (onClick)
import Html.Extra as HtmlExtra
import Http exposing (Error(..))
import Hypermedia exposing (Method(..), OperationSelector(..), decodeMaybe, encodeMaybe)
import Json.Decode as D
import Json.Encode as E
import Maybe exposing (withDefault)
import Toast
import Updaters exposing (Updater, childUpdate)
import ViewUtil as Eww



-- XXX There's a general pattern to note:
-- we sometimes have proposed vs. accepted resources
-- a proposed resource (e.g. during create) doesn't have a URL yet
-- and there's the larger issue of the gradual transition from nothing to a valid resource
-- (i.e. at 0% we have no user input, and at 100% we have something we might be able to POST)
-- likewise, there's the interesting distinction between a Show, where we Maybe have the resource,
-- but if so it will be fully formed and a Create where we definitely have a resource that might be 0%.
--
-- Considering: a (Resource)Field type, as Server|User|Unset. "encodeField" and "decodeField"
-- (like the maybe versions here). Would also begin support for smart 409 resolution
-- also helps with client-side validation, since you only consider fields that are User
--
-- Further thinking: original: Default v | Server v, updated: Maybe v
-- IOW: we used a default value, or the backend provided a value;
-- the user hasn't/has updated that with v.
-- the v is valid...? Always trust original values?
-- or Default v | Server v | DefaultUpdated v, v | ServerUpdated v, v
--
-- Original v = Default v | Server v
-- Value v = IsOriginal Original v | IsUpdated Original v, v
--
-- That then would mean either at the encode or put phases,
-- we could check the validity of our models,
-- knowing e.g. that our Default isn't allowed by the server,
-- trusting Original/Server values implicitly,
-- validating User input
-- XXX c&p from EventShow
{-
   , id : Maybe Affordance
   , update : Maybe Affordance
   , template : Maybe Affordance
   , nick : Nick
        |> custom (D.map (\u -> Just (HM.link GET u)) (D.field "id" D.string))
        |> custom (D.map (HM.selectAffordance (ByType "UpdateAction")) HM.affordanceListDecoder)
        |> custom (D.map (HM.selectAffordance (ByType "FindAction")) HM.affordanceListDecoder)
        |> required "nick" nickDecode
-}


type alias Game =
    { name : Maybe String
    , minPlayers : Maybe Int
    , maxPlayers : Maybe Int
    , durationSecs : Maybe Int
    , bggID : Maybe String
    , pitch : Maybe String
    , interested : Maybe Bool
    , canTeach : Maybe Bool
    , notes : Maybe String
    }


type alias Nick =
    { game_id : Int
    , user_id : String
    }


type alias GameAndSearch gas =
    { gas | resource : Game, bggSearchResults : List BGGGame }


init : Game
init =
    Game
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing


decoder : D.Decoder Game
decoder =
    D.succeed Game
        |> decodeMaybe "name" D.string
        |> decodeMaybe "minPlayers" D.int
        |> decodeMaybe "maxPlayers" D.int
        |> decodeMaybe "durationSecs" D.int
        |> decodeMaybe "bggId" D.string
        |> decodeMaybe "pitch" D.string
        |> decodeMaybe "interested" D.bool
        |> decodeMaybe "canTeach" D.bool
        |> decodeMaybe "notes" D.string


nickDecode : D.Decoder Nick
nickDecode =
    D.map2 Nick
        (D.field "game_id" D.int)
        (D.field "user_id" D.string)


encoder : Game -> E.Value
encoder g =
    E.object
        [ ( "name", encodeMaybe E.string g.name )
        , ( "minPlayers", encodeMaybe E.int g.minPlayers )
        , ( "maxPlayers", encodeMaybe E.int g.maxPlayers )
        , ( "durationSecs", encodeMaybe E.int g.durationSecs )
        , ( "bggId", encodeMaybe E.string g.bggID )
        , ( "pitch", encodeMaybe E.string g.pitch )
        , ( "interested", encodeMaybe E.bool g.interested )
        , ( "canTeach", encodeMaybe E.bool g.canTeach )
        , ( "notes", encodeMaybe E.string g.notes )
        ]


type Msg
    = ChangeName String
    | ChangeMinPlayers Int
    | ChangeMaxPlayers Int
    | ChangeDurationSecs Int
    | ChangeBggID String
    | ChangePitch String
    | ChangeInterested Bool
    | ChangeCanTeach Bool
    | ChangeNotes String
    | Pick BGGThing
    | SearchName
    | BGGSearchResult (Result BGGAPI.Error (List BGGGame))
    | BGGThingResult (Result BGGAPI.Error BGGThing)


type Toast
    = Unknown



-- XXX this should be editView, and there should also be showView


view : Bool -> GameAndSearch gas -> List (Html Msg)
view showInterest model =
    let
        game =
            model.resource

        foundGames =
            model.bggSearchResults

        numMsg msg v =
            msg (withDefault 0 (String.toInt v))

        dstr =
            withDefault ""

        dnum =
            withDefault 0
    in
    [ div [ class "field search" ]
        (Eww.bareInputPair [] "Name" (dstr game.name) ChangeName
            ++ [ button [ type_ "button", onClick SearchName, Eww.disabledMaybe game.name ] [ Eww.svgIcon "search" ] ]
        )
    , searchResults foundGames
    , Eww.inputPair [] "MinPlayers" (String.fromInt (dnum game.minPlayers)) (numMsg ChangeMinPlayers)
    , Eww.inputPair [] "MaxPlayers" (String.fromInt (dnum game.maxPlayers)) (numMsg ChangeMaxPlayers)
    , Eww.inputPair [] "DurationSecs" (String.fromInt (dnum game.durationSecs)) (numMsg ChangeDurationSecs)
    , Eww.inputPair [] "BggID" (dstr game.bggID) ChangeBggID
    , Eww.inputPair [] "Pitch" (dstr game.pitch) ChangePitch
    , interestedInput showInterest game
    , Eww.checkbox [] "CanTeach" (withDefault False game.canTeach) ChangeCanTeach
    , Eww.inputPair [] "Notes" (dstr game.notes) ChangeNotes
    ]


bggLink : { game | name : Maybe String, bggID : Maybe String } -> Html msg
bggLink { name, bggID } =
    let
        nameHTML =
            text (Maybe.withDefault "(name missing)" name)

        makeLink id =
            a [ href ("https://boardgamegeek.com/boardgame/" ++ id) ] [ nameHTML ]
    in
    Maybe.withDefault nameHTML (Maybe.map makeLink bggID)


searchResults : List BGGGame -> Html Msg
searchResults bggSearchResults =
    if List.length bggSearchResults > 0 then
        table []
            [ thead []
                [ th [ class "image" ] [ text "Cover" ]
                , th [ class "name" ] [ text "Name" ]
                , th [ class "description" ] [ text "Description" ]
                , th [ class "pick" ] [ text "Pick" ]
                ]
            , tbody []
                (List.map
                    viewBggResult
                    bggSearchResults
                )
            ]

    else
        HtmlExtra.nothing


viewBggResult : BGGGame -> Html Msg
viewBggResult game =
    case game of
        SearchResult bggRes ->
            tr []
                [ td [ class "image" ] [ text "placeholder" ]
                , td [ class "name" ] [ text bggRes.name ]
                , td [ class "description" ] [ text "?" ]
                , td [ class "pick" ] [ button [ type_ "button", disabled True ] [ text "Pick" ] ]
                ]

        Thing thing ->
            tr []
                [ td [ class "image" ] [ img [ src thing.thumbnail ] [] ]
                , td [ class "name" ] [ text thing.name ]
                , td [ class "description" ] [ text thing.description ]
                , td [ class "pick" ] [ button [ type_ "button", onClick (Pick thing) ] [ text "Pick" ] ]
                ]


interestedInput : Bool -> Game -> Html Msg
interestedInput showInterest g =
    if showInterest then
        Eww.checkbox [] "Interested" (withDefault False g.interested) ChangeInterested

    else
        HtmlExtra.nothing


gameUpdaters : (Updater Game Msg -> Updater model msg) -> Msg -> Updater model msg
gameUpdaters gameLocalUpdate msg =
    case msg of
        ChangeName n ->
            gameLocalUpdate (\m -> ( { m | name = Just n }, Cmd.none ))

        ChangeMinPlayers v ->
            gameLocalUpdate (\m -> ( { m | minPlayers = Just v }, Cmd.none ))

        ChangeMaxPlayers v ->
            gameLocalUpdate (\m -> ( { m | maxPlayers = Just v }, Cmd.none ))

        ChangeDurationSecs l ->
            gameLocalUpdate (\m -> ( { m | durationSecs = Just l }, Cmd.none ))

        ChangeBggID i ->
            gameLocalUpdate (\m -> ( { m | bggID = Just i }, Cmd.none ))

        ChangePitch p ->
            gameLocalUpdate (\m -> ( { m | pitch = Just p }, Cmd.none ))

        ChangeInterested i ->
            gameLocalUpdate (\m -> ( { m | interested = Just i }, Cmd.none ))

        ChangeCanTeach t ->
            gameLocalUpdate (\m -> ( { m | canTeach = Just t }, Cmd.none ))

        ChangeNotes n ->
            gameLocalUpdate (\m -> ( { m | notes = Just n }, Cmd.none ))

        Pick thing ->
            gameLocalUpdate
                (\m ->
                    ( { m
                        | name = Just thing.name
                        , bggID = Just thing.bggId
                        , minPlayers = Just thing.minPlayers
                        , maxPlayers = Just thing.maxPlayers
                        , durationSecs = Just (thing.durationMinutes * 60)
                      }
                    , Cmd.none
                    )
                )

        _ ->
            Updaters.noChange


searchUpdaters :
    { iface
        | searchLocalUpdate : Updater (List BGGGame) Msg -> Updater model msg
        , sendToast : Toast -> Updater model msg
    }
    -> Msg
    -> Updater model msg
searchUpdaters { searchLocalUpdate, sendToast } msg =
    case msg of
        Pick thing ->
            let
                onlyPicked g =
                    case g of
                        SearchResult _ ->
                            False

                        Thing t ->
                            t.bggId == thing.bggId
            in
            searchLocalUpdate (\m -> ( List.filter onlyPicked m, Cmd.none ))

        BGGSearchResult r ->
            case r of
                Ok l ->
                    searchLocalUpdate (\_ -> ( l, shotgunGames l ))

                Err _ ->
                    sendToast Unknown

        BGGThingResult r ->
            case r of
                Ok newGame ->
                    searchLocalUpdate (\m -> ( enrichGame m newGame, Cmd.none ))

                Err _ ->
                    sendToast Unknown

        _ ->
            Updaters.noChange


type alias Interface base gas model msg =
    { base
        | localUpdate : Updater (GameAndSearch gas) Msg -> Updater model msg
        , sendToast : Toast -> Updater model msg
    }


updaters : Interface base gas model msg -> Msg -> Updater model msg
updaters { localUpdate, sendToast } msg =
    let
        gameLocalUpdate =
            localUpdate << childUpdate .resource (\m -> \g -> { m | resource = g }) identity

        searchLocalUpdate =
            localUpdate << childUpdate .bggSearchResults (\m -> \g -> { m | bggSearchResults = g }) identity
    in
    case msg of
        ChangeName n ->
            gameLocalUpdate (\m -> ( { m | name = Just n }, Cmd.none ))

        ChangeMinPlayers v ->
            gameLocalUpdate (\m -> ( { m | minPlayers = Just v }, Cmd.none ))

        ChangeMaxPlayers v ->
            gameLocalUpdate (\m -> ( { m | maxPlayers = Just v }, Cmd.none ))

        ChangeDurationSecs l ->
            gameLocalUpdate (\m -> ( { m | durationSecs = Just l }, Cmd.none ))

        ChangeBggID i ->
            gameLocalUpdate (\m -> ( { m | bggID = Just i }, Cmd.none ))

        ChangePitch p ->
            gameLocalUpdate (\m -> ( { m | pitch = Just p }, Cmd.none ))

        ChangeInterested i ->
            gameLocalUpdate (\m -> ( { m | interested = Just i }, Cmd.none ))

        ChangeCanTeach t ->
            gameLocalUpdate (\m -> ( { m | canTeach = Just t }, Cmd.none ))

        ChangeNotes n ->
            gameLocalUpdate (\m -> ( { m | notes = Just n }, Cmd.none ))

        Pick thing ->
            let
                onlyPicked g =
                    case g of
                        SearchResult _ ->
                            False

                        Thing t ->
                            t.bggId == thing.bggId
            in
            Updaters.compose
                (searchLocalUpdate (\m -> ( List.filter onlyPicked m, Cmd.none )))
                (gameLocalUpdate
                    (\m ->
                        ( { m
                            | name = Just thing.name
                            , bggID = Just thing.bggId
                            , minPlayers = Just thing.minPlayers
                            , maxPlayers = Just thing.maxPlayers
                            , durationSecs = Just (thing.durationMinutes * 60)
                          }
                        , Cmd.none
                        )
                    )
                )

        BGGSearchResult r ->
            case r of
                Ok l ->
                    searchLocalUpdate (\_ -> ( l, shotgunGames l ))

                Err _ ->
                    sendToast Unknown

        BGGThingResult r ->
            case r of
                Ok newGame ->
                    searchLocalUpdate (\m -> ( enrichGame m newGame, Cmd.none ))

                Err _ ->
                    sendToast Unknown

        SearchName ->
            localUpdate
                (\model ->
                    ( model, requestBGGSearch BGGSearchResult (withDefault "" model.resource.name) )
                )



{-
   Updaters.compose
       (searchUpdaters { searchLocalUpdate = searchLocalUpdate, sendToast = sendToast } msg)
       (gameUpdaters gameLocalUpdate msg)
-}


viewToast : Toast.Info Toast -> List (Html Msg)
viewToast toastInfo =
    case toastInfo.content of
        Unknown ->
            [ p [] [ text "there was an error from the BGG servers; try that again?" ] ]


shotgunGames : List BGGGame -> Cmd Msg
shotgunGames list =
    let
        getID sres =
            case sres of
                SearchResult res ->
                    Just res.id

                _ ->
                    Nothing
    in
    BGGAPI.shotgunGames getID (\_ -> BGGThingResult) list


enrichGame : List BGGGame -> BGGThing -> List BGGGame
enrichGame list newGame =
    let
        swapGame oldGame =
            case oldGame of
                SearchResult res ->
                    if res.id == newGame.bggId then
                        Thing newGame

                    else
                        oldGame

                _ ->
                    oldGame
    in
    List.map swapGame list
